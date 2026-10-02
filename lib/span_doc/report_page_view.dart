import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'docx_model.dart';
import 'fill_binding.dart';
import 'fill_values.dart';

/// How the page shows placeholders.
enum ReportPageMode {
  /// A report: values from the fill map, tappable to edit.
  report,

  /// A template: placeholders as field chips, repeating blocks outlined.
  template,
}

/// Loads a photo for a fill-map path.
typedef PagePhotoLoader = Future<Uint8List> Function(String path);

/// Builds the inline editor for the field being edited.
typedef SlotEditorBuilder = Widget Function(DocxSlot slot, TextStyle style, bool wholeParagraph);

/// Link blue used for selection and field chips (no teal in the editor).
const Color reportSelectionBlue = Color(0xFF1971C2);

/// Draws a Word document the way the report reads: one sheet per page break
/// or section, with the section's header and footer, tables, text boxes,
/// pictures and floating shapes. Units are points (1 pt = 1 logical pixel
/// before scaling to the available width).
///
/// Pagination follows explicit page breaks and sections only, so a long
/// section is one tall sheet; the downloaded Word file paginates exactly.
class ReportPageView extends StatefulWidget {
  final DocxDocument document;
  final Map<String, dynamic> fill;
  final ReportPageMode mode;
  final Map<String, String> labels;
  final PagePhotoLoader? loadPhoto;

  /// Report mode: the field being edited (its fill path, joined) and its editor.
  final String? editingKey;
  final SlotEditorBuilder? editorBuilder;
  final ValueChanged<DocxSlot>? onTapSlot;

  /// Report mode: the selected photo ([PhotoRef.id]) and photo taps.
  final String? selectedPhoto;
  final ValueChanged<PhotoRef>? onTapPhoto;

  /// Template mode: highlighted block and taps on fields / blocks.
  final String? highlightedGroup;
  final ValueChanged<String>? onTapGroup;
  final ValueChanged<String>? onTapToken;
  final String? highlightedToken;

  final double maxScale;

  const ReportPageView({
    super.key,
    required this.document,
    required this.fill,
    this.mode = ReportPageMode.report,
    this.labels = const {},
    this.loadPhoto,
    this.editingKey,
    this.editorBuilder,
    this.onTapSlot,
    this.selectedPhoto,
    this.onTapPhoto,
    this.highlightedGroup,
    this.onTapGroup,
    this.onTapToken,
    this.highlightedToken,
    this.maxScale = 1.35,
  });

  @override
  State<ReportPageView> createState() => _ReportPageViewState();
}

class _PageContent {
  final DocxSection section;
  final bool firstOfSection;
  final List<DocxBlock> blocks;

  _PageContent(this.section, this.firstOfSection, this.blocks);
}

class _ReportPageViewState extends State<ReportPageView> {
  final List<GestureRecognizer> _recognizers = [];
  final Map<String, Future<Uint8List>> _photos = {};

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<Uint8List>? _photo(String path) {
    final loader = widget.loadPhoto;
    if (loader == null || path.isEmpty) return null;
    return _photos.putIfAbsent(path, () => loader(path));
  }

  List<_PageContent> _pages() {
    final doc = widget.document;
    final sections = doc.sections;
    final pages = <_PageContent>[];
    var sectionIndex = 0;
    DocxSection section() => sections.isEmpty ? const DocxSection() : sections[sectionIndex.clamp(0, sections.length - 1)];
    var current = <DocxBlock>[];
    var first = true;

    void flush({bool force = false}) {
      if (current.isEmpty && !force) return;
      pages.add(_PageContent(section(), first, current));
      current = [];
      first = false;
    }

    for (final block in doc.body) {
      if (block is DocxParagraph) {
        if (block.pageBreakBefore && current.isNotEmpty) flush();
        final breakAt = block.inlines.indexWhere((i) => i is DocxBreak && i.page);
        if (breakAt >= 0) {
          final before = block.inlines.sublist(0, breakAt);
          final after = block.inlines.sublist(breakAt + 1);
          if (before.any(_visibleInline)) current.add(block.copyWith(inlines: before, keepSection: false));
          flush(force: current.isEmpty && pages.isEmpty);
          if (after.any(_visibleInline) || block.sectionIndex != null) current.add(block.copyWith(inlines: after));
        } else {
          current.add(block);
        }
        if (block.sectionIndex != null) {
          flush(force: true);
          sectionIndex++;
          first = true;
        }
      } else {
        current.add(block);
      }
    }
    flush();
    return pages;
  }

  static bool _visibleInline(DocxInline i) => switch (i) {
        DocxText t => t.text.trim().isNotEmpty && t.style.hidden != true,
        DocxSlot s => !s.isMarker,
        DocxImage _ || DocxShape _ => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final pages = _pages();
    final templateDoc = widget.mode == ReportPageMode.template ? _templateGroups(pages) : pages;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = templateDoc.map((p) => p.section.pageWidth).fold<double>(0, (a, b) => a > b ? a : b);
        final available = (constraints.maxWidth - 48).clamp(200.0, 4000.0);
        final scale = (available / (maxWidth == 0 ? 612 : maxWidth)).clamp(0.3, widget.maxScale);
        return Column(
          children: [
            for (var i = 0; i < templateDoc.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              _sheet(templateDoc[i], scale),
            ],
          ],
        );
      },
    );
  }

  /// Template mode: wrap BLOCK_START..END ranges in outlined groups.
  List<_PageContent> _templateGroups(List<_PageContent> pages) {
    final marker = RegExp(r'\{\{BLOCK_START:([^{}]+)\}\}');
    return [
      for (final page in pages)
        _PageContent(page.section, page.firstOfSection, () {
          var blocks = page.blocks;
          final names = {for (final b in blocks) ...marker.allMatches(blockText(b)).map((m) => m.group(1)!)};
          for (final name in names) {
            final out = <DocxBlock>[];
            List<DocxBlock>? current;
            for (final b in blocks) {
              final text = blockText(b);
              if (current == null && text.contains('{{BLOCK_START:$name}}')) current = [];
              if (current != null) {
                current.add(b);
                if (text.contains('{{BLOCK_END:$name}}')) {
                  out.add(DocxGroup(name: name, blocks: current));
                  current = null;
                }
              } else {
                out.add(b);
              }
            }
            if (current != null) out.addAll(current);
            blocks = out;
          }
          return blocks;
        }()),
    ];
  }

  Widget _sheet(_PageContent page, double scale) {
    final s = page.section;
    final parts = widget.document.parts;
    final useFirst = page.firstOfSection && s.titlePage;
    final headerId = useFirst ? s.firstHeaderId : s.headerId;
    final footerId = useFirst ? s.firstFooterId : s.footerId;
    final header = headerId == null ? null : parts[headerId];
    final footer = footerId == null ? null : parts[footerId];
    final contentWidth = s.pageWidth - s.margins.horizontal;
    final headerTop = s.headerDistance.clamp(0.0, s.margins.top);

    final floating = <Widget>[];
    void collectFloating(List<DocxBlock> blocks) {
      for (final b in blocks) {
        if (b is DocxParagraph) {
          for (final i in b.inlines) {
            final anchor = switch (i) {
              DocxImage img => img.anchor,
              DocxShape sh => sh.anchor,
              _ => null,
            };
            if (anchor != null && anchor.onPage) floating.add(_placed(i, anchor, s));
          }
        } else if (b is DocxGroup) {
          collectFloating(b.blocks);
        }
      }
    }

    collectFloating(page.blocks);
    if (header != null) collectFloating(header);
    if (footer != null) collectFloating(footer);

    final sheet = Container(
      width: s.pageWidth,
      constraints: BoxConstraints(minHeight: s.pageHeight),
      color: Colors.white,
      child: Stack(
        children: [
          ...floating.whereType<_Behind>(),
          // Like Word: the header starts at the header distance and the body
          // starts at the top margin, or below the header when it is taller.
          Padding(
            padding: EdgeInsets.fromLTRB(s.margins.left, header == null ? s.margins.top : headerTop, s.margins.right, s.margins.bottom),
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (header != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: (s.margins.top - headerTop).clamp(0.0, 400.0)),
                      child: IgnorePointer(
                        ignoring: widget.mode == ReportPageMode.template,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final b in header) _block(b, contentWidth)]),
                      ),
                    ),
                  for (final b in page.blocks) _block(b, contentWidth),
                ],
              ),
            ),
          ),
          if (footer != null)
            Positioned(
              left: s.margins.left,
              right: s.margins.right,
              bottom: s.footerDistance.clamp(0.0, s.margins.bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final b in footer) _block(b, contentWidth)]),
            ),
          ...floating.where((w) => w is! _Behind),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      width: s.pageWidth * scale,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: sheet,
      ),
    );
  }

  Widget _placed(DocxInline item, DocxAnchor anchor, DocxSection s) {
    final (width, height) = switch (item) {
      DocxImage i => (i.width, i.height),
      DocxShape sh => (sh.width, sh.height),
      _ => (0.0, 0.0),
    };
    final originX = anchor.hFrom == 'margin' ? s.margins.left : 0.0;
    final originY = anchor.vFrom == 'margin' ? s.margins.top : 0.0;
    final areaW = anchor.hFrom == 'margin' ? s.pageWidth - s.margins.horizontal : s.pageWidth;
    final areaH = anchor.vFrom == 'margin' ? s.pageHeight - s.margins.vertical : s.pageHeight;
    var x = originX + (anchor.x ?? 0);
    var y = originY + (anchor.y ?? 0);
    switch (anchor.hAlign) {
      case 'center':
        x = originX + (areaW - width) / 2;
      case 'right':
      case 'outside':
        x = originX + areaW - width;
      case 'left':
      case 'inside':
        x = originX;
    }
    switch (anchor.vAlign) {
      case 'center':
        y = originY + (areaH - height) / 2;
      case 'bottom':
        y = originY + areaH - height;
      case 'top':
        y = originY;
    }
    final grows = item is DocxShape && item.autoFit;
    final child = Positioned(left: x, top: y, width: width, height: grows ? null : height, child: _inlineBox(item, floatingSize: !grows));
    return anchor.behind ? _Behind(child: child) : child;
  }

  // --- blocks ------------------------------------------------------------------

  Widget _block(DocxBlock block, double width) {
    return switch (block) {
      DocxParagraph p => _paragraph(p, width),
      DocxTable t => _table(t, width),
      DocxGroup g => _group(g, width),
    };
  }

  Widget _group(DocxGroup g, double width) {
    final children = [for (final b in g.blocks) _block(b, width)];
    if (widget.mode != ReportPageMode.template) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    }
    final highlighted = widget.highlightedGroup == g.name;
    return MouseRegion(
      cursor: widget.onTapGroup == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTapGroup == null ? null : () => widget.onTapGroup!(g.name),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFFF5FAFF) : null,
            border: Border.all(color: highlighted ? reportSelectionBlue : const Color(0xFFADB5BD), width: highlighted ? 1.2 : 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'REPEATS FOR EACH ${_humanize(g.name).toUpperCase()}',
                  style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Color(0xFF868E96)),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _paragraph(DocxParagraph p, double width) {
    final st = p.style;
    final before = st.before ?? 0;
    final after = st.after ?? 0;
    final left = (st.indentLeft ?? 0).clamp(-72.0, width / 2);
    final right = (st.indentRight ?? 0).clamp(-72.0, width / 2);
    final firstLine = st.firstLine ?? 0;
    final hanging = st.hanging ?? 0;
    final lineHeight = st.lineExact == true ? null : ((st.line ?? 1.0) * 1.15).clamp(0.8, 3.0);
    final align = switch (st.align) {
      'center' => TextAlign.center,
      'right' || 'end' => TextAlign.right,
      'both' || 'distribute' => TextAlign.justify,
      _ => TextAlign.left,
    };

    // Floating pictures/shapes placed on the page are drawn by the sheet.
    final inlines = p.inlines.where((i) {
      final anchor = switch (i) {
        DocxImage img => img.anchor,
        DocxShape sh => sh.anchor,
        _ => null,
      };
      return anchor == null || !anchor.onPage;
    }).toList();

    final editing = widget.editingKey;
    final editorSlot = editing == null
        ? null
        : inlines.whereType<DocxSlot>().where((s) => s.path != null && s.path!.join('/') == editing).firstOrNull;
    final markHeight = (p.markStyle.size ?? 11) * (lineHeight ?? 1.15);

    Widget content;
    if (editorSlot != null && widget.editorBuilder != null && _onlyContent(inlines, editorSlot)) {
      content = widget.editorBuilder!(editorSlot, _textStyle(editorSlot.style, lineHeight), true);
    } else {
      final spans = <InlineSpan>[];
      for (final inline in inlines) {
        spans.addAll(_spans(inline, lineHeight, editorSlot));
      }
      final visible = spans.isNotEmpty && spans.any((s) => s is WidgetSpan || (s is TextSpan && (s.text ?? '').isNotEmpty));
      if (!visible) {
        final hint = widget.mode == ReportPageMode.report ? _emptyHint(inlines, lineHeight) : null;
        content = hint ?? SizedBox(height: markHeight, width: double.infinity);
      } else {
        content = Text.rich(
          TextSpan(children: spans, style: _textStyle(p.markStyle, lineHeight)),
          textAlign: align,
          strutStyle: st.lineExact == true && st.line != null
              ? StrutStyle(fontSize: (p.markStyle.size ?? 11), height: st.line! / (p.markStyle.size ?? 11), forceStrutHeight: true)
              : null,
        );
      }
    }

    final label = p.listLabel;
    if (label != null && label.isNotEmpty) {
      final gap = hanging > 0 ? hanging : 18.0;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: gap, child: Text(label, style: _textStyle(p.markStyle, lineHeight))),
          Expanded(child: content),
        ],
      );
    }

    final leftPad = (label != null && label.isNotEmpty) ? (left - (hanging > 0 ? hanging : 0)) : left + (firstLine > 0 ? 0 : 0);
    final borders = st.borders;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: before, bottom: after),
      padding: EdgeInsets.only(left: leftPad.clamp(0.0, width), right: right.clamp(0.0, width)),
      decoration: (st.shading != null || borders != null)
          ? BoxDecoration(
              color: st.shading,
              border: Border(
                top: _side(borders?.top),
                bottom: _side(borders?.bottom),
                left: _side(borders?.left),
                right: _side(borders?.right),
              ),
            )
          : null,
      child: firstLine > 0 && label == null
          ? Padding(padding: EdgeInsets.zero, child: _withFirstLine(content, firstLine))
          : content,
    );
  }

  Widget _withFirstLine(Widget content, double firstLine) {
    if (content is Text && content.textSpan != null) {
      return Text.rich(
        TextSpan(children: [WidgetSpan(child: SizedBox(width: firstLine)), content.textSpan!]),
        textAlign: content.textAlign,
        strutStyle: content.strutStyle,
      );
    }
    return content;
  }

  bool _onlyContent(List<DocxInline> inlines, DocxSlot slot) {
    for (final i in inlines) {
      if (identical(i, slot)) continue;
      if (_visibleInline(i)) return false;
    }
    return true;
  }

  /// An empty field in a report paragraph: shown so it can be filled in (the
  /// Word file drops the empty paragraph).
  Widget? _emptyHint(List<DocxInline> inlines, double? lineHeight) {
    final slot = inlines.whereType<DocxSlot>().where((s) => s.path != null && !s.blank && !s.isMarker).firstOrNull;
    if (slot == null || widget.onTapSlot == null) return null;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        onTap: () => widget.onTapSlot!(slot),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCED4DA), width: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Add ${_label(slot.token).toLowerCase()}',
            style: _textStyle(slot.style, lineHeight).copyWith(color: const Color(0xFFADB5BD), fontStyle: FontStyle.italic, fontWeight: FontWeight.normal),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _spans(DocxInline inline, double? lineHeight, DocxSlot? editorSlot) {
    switch (inline) {
      case DocxText t:
        if (t.style.hidden == true || t.text.isEmpty) return const [];
        return [TextSpan(text: t.style.caps == true ? t.text.toUpperCase() : t.text, style: _textStyle(t.style, lineHeight))];
      case DocxTab _:
        return const [TextSpan(text: '    ')];
      case DocxBreak b:
        return b.page ? const [] : const [TextSpan(text: '\n')];
      case DocxSlot s:
        return _slotSpans(s, lineHeight, editorSlot);
      case DocxImage _:
      case DocxShape _:
        return [WidgetSpan(alignment: PlaceholderAlignment.bottom, child: _inlineBox(inline))];
    }
  }

  List<InlineSpan> _slotSpans(DocxSlot s, double? lineHeight, DocxSlot? editorSlot) {
    if (s.isMarker) return const [];
    final base = _textStyle(s.style, lineHeight);
    if (widget.mode == ReportPageMode.template) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _chip(s.token, (base.fontSize ?? 11) * 0.85),
        ),
      ];
    }
    if (s.blank) return const [];
    final path = s.path;
    if (path == null) return [TextSpan(text: s.token, style: base.copyWith(color: const Color(0xFFADB5BD)))];
    if (editorSlot != null && identical(s, editorSlot) && widget.editorBuilder != null) {
      return [WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: widget.editorBuilder!(s, base, false))];
    }
    final value = fillGet(widget.fill, path);
    final runs = valueRuns(value);
    final width = maxChars(value);
    final text = runs.map((r) => r.text).join();
    var shrink = 1.0;
    if (width != null && text.trim().length > width) shrink = (width / text.trim().length).clamp(7 / (s.style.size ?? 11), 1.0);
    GestureRecognizer? recognizer;
    if (widget.onTapSlot != null) {
      recognizer = TapGestureRecognizer()..onTap = () => widget.onTapSlot!(s);
      _recognizers.add(recognizer);
    }
    return [
      for (final run in runs)
        TextSpan(
          text: s.style.caps == true ? run.text.toUpperCase() : run.text,
          recognizer: recognizer,
          mouseCursor: recognizer == null ? null : SystemMouseCursors.text,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 11) * shrink,
            fontWeight: run.bold ? FontWeight.w700 : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            decoration: TextDecoration.combine([
              if (run.underline || s.style.underline == true) TextDecoration.underline,
              if (run.strike || s.style.strike == true) TextDecoration.lineThrough,
            ]),
          ),
        ),
    ];
  }

  Widget _chip(String token, double size) {
    final label = _label(token);
    final on = widget.highlightedToken == token;
    final chip = Container(
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: on ? reportSelectionBlue : const Color(0xFFE7F5FF),
        border: Border.all(color: on ? reportSelectionBlue : const Color(0xFFA5D8FF), width: 0.7),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(fontSize: size.clamp(6.0, 14.0), color: on ? Colors.white : reportSelectionBlue, fontWeight: FontWeight.w500, height: 1.2)),
    );
    if (widget.onTapToken == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: () => widget.onTapToken!(token), child: chip),
    );
  }

  String _label(String token) => widget.labels[token] ?? _humanize(token);

  // --- pictures and shapes -------------------------------------------------------

  Widget _inlineBox(DocxInline item, {bool floatingSize = false}) {
    switch (item) {
      case DocxImage img:
        return _image(img);
      case DocxShape sh when sh.parts.isNotEmpty:
        return SizedBox(
          width: sh.width,
          height: sh.height,
          child: Stack(children: [
            for (final (rect, color) in sh.parts) Positioned.fromRect(rect: rect, child: ColoredBox(color: color)),
          ]),
        );
      case DocxShape sh:
        final inner = sh.width - 14.4;
        return Container(
          width: sh.width,
          constraints: floatingSize ? null : BoxConstraints(minHeight: sh.height),
          height: floatingSize ? sh.height : null,
          padding: const EdgeInsets.symmetric(horizontal: 7.2, vertical: 3.6),
          decoration: BoxDecoration(
            color: sh.fill,
            border: sh.line == null ? null : Border.all(color: sh.line!.color, width: sh.line!.width),
          ),
          child: sh.blocks.isEmpty
              ? null
              : () {
                  final content = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final b in sh.blocks) _block(b, inner > 20 ? inner : sh.width)],
                  );
                  // A floating box has a fixed frame; text past it is clipped
                  // (as in Word). An inline box grows with its text.
                  return floatingSize
                      ? ClipRect(child: OverflowBox(alignment: Alignment.topLeft, minHeight: 0, maxHeight: double.infinity, child: content))
                      : content;
                }(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _image(DocxImage img) {
    final size = Size(img.width <= 0 ? 72 : img.width, img.height <= 0 ? 54 : img.height);
    if (img.removed) return const SizedBox.shrink();
    if (widget.mode == ReportPageMode.template && img.slot != null) {
      return Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          border: Border.all(color: const Color(0xFFCED4DA), width: 0.8),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: (size.shortestSide / 4).clamp(10, 28), color: const Color(0xFFADB5BD)),
            const SizedBox(height: 2),
            _chip(img.slot!, 8),
          ],
        ),
      );
    }
    final photo = img.photo;
    if (photo == null) {
      if (img.bytes == null) return SizedBox(width: size.width, height: size.height);
      final crop = img.crop;
      if (crop == null || (crop.left + crop.right + crop.top + crop.bottom) == 0) {
        return Image.memory(img.bytes!, width: size.width, height: size.height, fit: BoxFit.fill, gaplessPlayback: true);
      }
      // Word crops: show only the uncropped part, stretched to the frame.
      final keepW = (1 - crop.left - crop.right).clamp(0.05, 1.0);
      final keepH = (1 - crop.top - crop.bottom).clamp(0.05, 1.0);
      return SizedBox(
        width: size.width,
        height: size.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: size.width / keepW,
            maxHeight: size.height / keepH,
            child: Transform.translate(
              offset: Offset(-crop.left * size.width / keepW, -crop.top * size.height / keepH),
              child: Image.memory(img.bytes!, width: size.width / keepW, height: size.height / keepH, fit: BoxFit.fill, gaplessPlayback: true),
            ),
          ),
        ),
      );
    }
    final path = fillGet(widget.fill, photo.imagePath)?.toString() ?? '';
    final selected = widget.selectedPhoto == photo.id;
    final future = _photo(path);
    final picture = future == null
        ? Container(color: const Color(0xFFE9ECEF))
        : FutureBuilder<Uint8List>(
            future: future,
            builder: (context, snap) {
              if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
              return Container(
                color: const Color(0xFFE9ECEF),
                alignment: Alignment.center,
                child: snap.hasError
                    ? const Icon(Icons.broken_image_outlined, color: Color(0xFFADB5BD))
                    : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5)),
              );
            },
          );
    return Semantics(
      label: selected ? 'Selected photo in report' : 'Photo in report',
      button: widget.onTapPhoto != null,
      child: MouseRegion(
      cursor: widget.onTapPhoto == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTapPhoto == null ? null : () => widget.onTapPhoto!(photo),
        child: Container(
          width: size.width,
          height: size.height,
          foregroundDecoration: selected ? BoxDecoration(border: Border.all(color: reportSelectionBlue, width: 3)) : null,
          child: picture,
        ),
      ),
    ),
    );
  }

  // --- tables ------------------------------------------------------------------------

  Widget _table(DocxTable t, double available) {
    final grid = t.grid.isEmpty ? [available] : t.grid;
    final total = grid.fold<double>(0, (a, b) => a + b);
    final factor = total > available + (t.indent ?? 0) + 40 ? available / total : 1.0;
    final cols = [for (final g in grid) g * factor];
    final rows = <Widget>[];
    for (var r = 0; r < t.rows.length; r++) {
      final row = t.rows[r];
      final cells = <Widget>[];
      var col = row.gridBefore;
      if (row.gridBefore > 0) {
        cells.add(SizedBox(width: cols.take(row.gridBefore.clamp(0, cols.length)).fold<double>(0, (a, b) => a + b)));
      }
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        final span = cell.gridSpan.clamp(1, 40);
        final end = (col + span).clamp(0, cols.length);
        var width = 0.0;
        for (var k = col; k < end; k++) {
          width += cols[k];
        }
        if (width <= 0) width = 40;
        final borders = t.borders.over(cell.borders);
        final isFirstRow = r == 0;
        final isLastRow = r == t.rows.length - 1;
        final isFirstCol = col == 0;
        final isLastCol = end >= cols.length;
        final continued = cell.vMerge == 'continue';
        final margin = cell.margin ?? t.cellMargin;
        cells.add(
          Container(
            width: width,
            padding: EdgeInsets.fromLTRB(margin.left, margin.top + 1, margin.right, margin.bottom + 1),
            decoration: BoxDecoration(
              color: cell.shading,
              border: Border(
                top: continued ? BorderSide.none : _side(isFirstRow ? borders.top : (cell.borders?.top ?? t.borders.insideH)),
                left: _side(isFirstCol ? borders.left : (cell.borders?.left ?? t.borders.insideV)),
                right: isLastCol ? _side(borders.right) : _side(cell.borders?.right ?? t.borders.insideV),
                bottom: isLastRow ? _side(borders.bottom) : (cell.borders?.bottom != null ? _side(cell.borders!.bottom) : BorderSide.none),
              ),
            ),
            alignment: switch (cell.vAlign) {
              'center' => Alignment.centerLeft,
              'bottom' => Alignment.bottomLeft,
              _ => Alignment.topLeft,
            },
            child: continued
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final b in cell.blocks) _block(b, (width - margin.horizontal).clamp(10.0, 2000.0))],
                  ),
          ),
        );
        col = end;
      }
      Widget rowWidget = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: cells),
      );
      if (row.height != null && row.height! > 0) {
        rowWidget = ConstrainedBox(
          constraints: row.exactHeight ? BoxConstraints.tightFor(height: row.height) : BoxConstraints(minHeight: row.height!),
          child: rowWidget,
        );
      }
      rows.add(rowWidget);
    }
    final table = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: rows);
    final indent = (t.indent ?? 0).clamp(-36.0, available / 2);
    return Container(
      width: double.infinity,
      alignment: switch (t.align) {
        'center' => Alignment.topCenter,
        'right' || 'end' => Alignment.topRight,
        _ => Alignment.topLeft,
      },
      padding: EdgeInsets.only(left: indent > 0 ? indent : 0),
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: table),
    );
  }

  BorderSide _side(DocxBorder? b) =>
      b == null || b.width <= 0 ? BorderSide.none : BorderSide(color: b.color, width: b.width);

  // --- text ----------------------------------------------------------------------------

  TextStyle _textStyle(DocxRunStyle s, double? lineHeight) {
    final size = s.size ?? 11;
    var style = _font(s.font).copyWith(
      fontSize: s.vertAlign == 'superscript' || s.vertAlign == 'subscript' ? size * 0.65 : size,
      color: s.color ?? Colors.black,
      fontWeight: s.bold == true ? FontWeight.w700 : FontWeight.w400,
      fontStyle: s.italic == true ? FontStyle.italic : FontStyle.normal,
      height: lineHeight,
      backgroundColor: s.highlight,
      decoration: TextDecoration.combine([
        if (s.underline == true) TextDecoration.underline,
        if (s.strike == true) TextDecoration.lineThrough,
      ]),
      decorationColor: s.color ?? Colors.black,
      letterSpacing: 0,
    );
    if (s.caps == true) style = style.copyWith(letterSpacing: 0.2);
    return style;
  }

  static final Map<String, TextStyle> _fonts = {};

  /// Word fonts drawn with metric-compatible open fonts.
  TextStyle _font(String? name) {
    final key = (name ?? 'Calibri').toLowerCase();
    return _fonts.putIfAbsent(key, () {
      String family;
      if (key.contains('calibri') || key.contains('aptos') || key.contains('segoe') || key.contains('candara')) {
        family = 'Carlito';
      } else if (key.contains('cambria') || key.contains('georgia')) {
        family = 'Caladea';
      } else if (key.contains('times') || key.contains('garamond') || key.contains('book antiqua') || key.contains('serif') && !key.contains('sans')) {
        family = 'Tinos';
      } else if (key.contains('courier') || key.contains('consolas') || key.contains('mono')) {
        family = 'Cousine';
      } else {
        family = 'Arimo';
      }
      try {
        return GoogleFonts.getFont(family);
      } catch (_) {
        return GoogleFonts.arimo();
      }
    });
  }
}

class _Behind extends StatelessWidget {
  final Widget child;

  const _Behind({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// "{{SITE_VISIT_DATE}}" -> "Site visit date".
String _humanize(String token) {
  final bare = token.replaceAll(RegExp(r'[{}]'), '').replaceFirst(RegExp(r'^BLOCK[_:](START|END)?:?'), '');
  final words = bare.toLowerCase().split(RegExp(r'[_:]')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return token;
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}

String humanizeField(String token) => _humanize(token);
