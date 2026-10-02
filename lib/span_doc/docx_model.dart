import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

/// A Word document read into what the report page needs to draw it: body
/// blocks (paragraphs and tables), page sections, headers and footers, with
/// styles, numbering and pictures resolved. Placeholders (`{{TOKEN}}`) are
/// kept as [DocxSlot]s so the page can show a report's values (editable) or a
/// template's fields (chips).
///
/// Units are points. This is a reader for drawing, not a round trip: the Word
/// file itself is always rebuilt on the server (fill_template.py).
class DocxDocument {
  final List<DocxBlock> body;
  final List<DocxSection> sections;

  /// Header/footer content by relationship id (sections refer to them).
  final Map<String, List<DocxBlock>> parts;

  const DocxDocument({required this.body, required this.sections, required this.parts});

  static DocxDocument parse(Uint8List bytes) => _DocxReader(bytes).read();

  /// Every placeholder token in the body, headers and footers, in order.
  List<String> get tokens {
    final out = <String>{};
    void visit(List<DocxBlock> blocks) {
      for (final block in blocks) {
        if (block is DocxParagraph) {
          for (final inline in block.inlines) {
            if (inline is DocxSlot) out.add(inline.token);
            if (inline is DocxImage && inline.slot != null) out.add(inline.slot!);
            if (inline is DocxShape) visit(inline.blocks);
          }
        } else if (block is DocxTable) {
          for (final row in block.rows) {
            for (final cell in row.cells) {
              visit(cell.blocks);
            }
          }
        } else if (block is DocxGroup) {
          visit(block.blocks);
        }
      }
    }

    visit(body);
    parts.values.forEach(visit);
    return out.toList();
  }
}

/// Page setup. A section's blocks end at the paragraph that carries its
/// sectPr ([DocxParagraph.sectionIndex]).
class DocxSection {
  final double pageWidth;
  final double pageHeight;
  final EdgeInsets margins;
  final String? headerId;
  final String? footerId;
  final String? firstHeaderId;
  final String? firstFooterId;
  final bool titlePage;

  /// Distance of the header from the top edge / footer from the bottom edge.
  final double headerDistance;
  final double footerDistance;

  const DocxSection({
    this.headerDistance = 36,
    this.footerDistance = 36,
    this.pageWidth = 612,
    this.pageHeight = 792,
    this.margins = const EdgeInsets.all(72),
    this.headerId,
    this.footerId,
    this.firstHeaderId,
    this.firstFooterId,
    this.titlePage = false,
  });
}

/// A location in a report's fill map: String keys and int list indexes.
typedef FillPath = List<Object>;

sealed class DocxBlock {
  const DocxBlock();
}

/// Bound content of a repeating block ({{BLOCK_START:NAME}}...END): one per
/// item of a report, or the block itself in a template.
class DocxGroup extends DocxBlock {
  final String name;

  /// Item number in a report; null in a template.
  final int? index;
  final List<DocxBlock> blocks;

  const DocxGroup({required this.name, this.index, required this.blocks});
}

class DocxParagraph extends DocxBlock {
  final DocxParaStyle style;

  /// Formatting of the paragraph mark: used for empty paragraphs' height and
  /// as the base for numbering text.
  final DocxRunStyle markStyle;
  final List<DocxInline> inlines;

  /// List label ("1.", "•") computed from numbering, or null.
  final String? listLabel;

  /// Set when this paragraph ends a section (its pPr holds a sectPr).
  final int? sectionIndex;

  /// A page break comes before this paragraph (pageBreakBefore).
  final bool pageBreakBefore;

  const DocxParagraph({
    required this.style,
    required this.markStyle,
    required this.inlines,
    this.listLabel,
    this.sectionIndex,
    this.pageBreakBefore = false,
  });

  DocxParagraph copyWith({List<DocxInline>? inlines, int? sectionIndex, bool keepSection = true}) => DocxParagraph(
        style: style,
        markStyle: markStyle,
        inlines: inlines ?? this.inlines,
        listLabel: listLabel,
        sectionIndex: keepSection ? (sectionIndex ?? this.sectionIndex) : sectionIndex,
        pageBreakBefore: pageBreakBefore,
      );

  /// Plain text of the paragraph (slots as their tokens).
  String get text => inlines.map((i) => switch (i) {
        DocxText t => t.text,
        DocxSlot s => s.token,
        DocxTab _ => '\t',
        DocxBreak b => b.page ? '' : '\n',
        _ => '',
      }).join();

  bool get hasPicture => inlines.any((i) => i is DocxImage);
}

class DocxTable extends DocxBlock {
  final List<double> grid;
  final List<DocxRow> rows;
  final DocxBorders borders;
  final EdgeInsets cellMargin;
  final String? align;
  final double? indent;

  const DocxTable({
    required this.grid,
    required this.rows,
    required this.borders,
    required this.cellMargin,
    this.align,
    this.indent,
  });

  DocxTable copyWith({List<DocxRow>? rows}) =>
      DocxTable(grid: grid, rows: rows ?? this.rows, borders: borders, cellMargin: cellMargin, align: align, indent: indent);
}

class DocxRow {
  final List<DocxCell> cells;
  final double? height;
  final bool exactHeight;

  /// Grid columns skipped before the first cell (w:gridBefore).
  final int gridBefore;

  const DocxRow({required this.cells, this.height, this.exactHeight = false, this.gridBefore = 0});

  DocxRow copyWith({List<DocxCell>? cells}) =>
      DocxRow(cells: cells ?? this.cells, height: height, exactHeight: exactHeight, gridBefore: gridBefore);
}

class DocxCell {
  final List<DocxBlock> blocks;
  final int gridSpan;

  /// 'restart', 'continue' or null.
  final String? vMerge;
  final Color? shading;
  final DocxBorders? borders;
  final String? vAlign;
  final EdgeInsets? margin;

  const DocxCell({
    required this.blocks,
    this.gridSpan = 1,
    this.vMerge,
    this.shading,
    this.borders,
    this.vAlign,
    this.margin,
  });

  DocxCell copyWith({List<DocxBlock>? blocks}) => DocxCell(
        blocks: blocks ?? this.blocks,
        gridSpan: gridSpan,
        vMerge: vMerge,
        shading: shading,
        borders: borders,
        vAlign: vAlign,
        margin: margin,
      );
}

class DocxBorder {
  final double width;
  final Color color;

  const DocxBorder(this.width, this.color);
}

class DocxBorders {
  final DocxBorder? top;
  final DocxBorder? bottom;
  final DocxBorder? left;
  final DocxBorder? right;
  final DocxBorder? insideH;
  final DocxBorder? insideV;

  const DocxBorders({this.top, this.bottom, this.left, this.right, this.insideH, this.insideV});

  static const none = DocxBorders();

  DocxBorders over(DocxBorders? other) => other == null
      ? this
      : DocxBorders(
          top: other.top ?? top,
          bottom: other.bottom ?? bottom,
          left: other.left ?? left,
          right: other.right ?? right,
          insideH: other.insideH ?? insideH,
          insideV: other.insideV ?? insideV,
        );
}

sealed class DocxInline {
  const DocxInline();
}

class DocxText extends DocxInline {
  final String text;
  final DocxRunStyle style;

  const DocxText(this.text, this.style);
}

/// A `{{TOKEN}}` placeholder, styled like the run it started in. Once bound
/// to a report, [path] says where its value lives in the fill map ([blank]
/// when the fill leaves it empty, e.g. an unused photo's caption).
class DocxSlot extends DocxInline {
  final String token;
  final DocxRunStyle style;
  final FillPath? path;
  final bool blank;

  const DocxSlot(this.token, this.style, {this.path, this.blank = false});

  /// Block markers and layout hints: never drawn.
  bool get isMarker => token.startsWith('{{BLOCK_') || token == '{{KEEP_WITH_NEXT}}';

  DocxSlot bound(FillPath? to, {bool blank = false}) => DocxSlot(token, style, path: to, blank: blank);
}

class DocxTab extends DocxInline {
  const DocxTab();
}

class DocxBreak extends DocxInline {
  final bool page;

  const DocxBreak({this.page = false});
}

class DocxImage extends DocxInline {
  final Uint8List? bytes;
  final double width;
  final double height;

  /// Placeholder token in the picture's alt text (a photo frame), if any.
  final String? slot;

  /// Position of a floating picture; null when inline with the text.
  final DocxAnchor? anchor;

  /// In a report: the photo filling this frame, if any.
  final PhotoRef? photo;

  /// In a report: a frame left empty (removed from the Word file).
  final bool removed;

  /// Cropping (fractions of the picture cut from each side), as Word stores it.
  final EdgeInsets? crop;

  const DocxImage({this.bytes, required this.width, required this.height, this.slot, this.anchor, this.photo, this.removed = false, this.crop});

  DocxImage bound({PhotoRef? photo, bool removed = false}) =>
      DocxImage(bytes: bytes, width: width, height: height, slot: slot, anchor: anchor, photo: photo, removed: removed, crop: crop);
}

/// Where a report photo lives in the fill map: [imagePath] holds the photo's
/// path string; [listPath] + [index] locate it in a list (photo blocks,
/// repeated items) so it can be moved or removed; [captionPath] is its
/// caption text, when it has one.
class PhotoRef {
  final FillPath imagePath;
  final FillPath? captionPath;
  final FillPath? listPath;
  final int? index;

  const PhotoRef({required this.imagePath, this.captionPath, this.listPath, this.index});

  String get id => imagePath.join('/');
}

/// A drawn shape: a text box (cover page panels, photo callouts) or a filled
/// rectangle (color bands).
class DocxShape extends DocxInline {
  final double width;
  final double height;
  final Color? fill;
  final DocxBorder? line;
  final List<DocxBlock> blocks;
  final DocxAnchor? anchor;

  /// A group's filled rectangles, in points inside the shape's frame.
  final List<(Rect, Color)> parts;

  /// The text box grows to fit its text (Word's "resize shape to fit text").
  final bool autoFit;

  const DocxShape({
    this.autoFit = false,
    required this.width,
    required this.height,
    this.fill,
    this.line,
    this.blocks = const [],
    this.anchor,
    this.parts = const [],
  });

  DocxShape withBlocks(List<DocxBlock> value) =>
      DocxShape(width: width, height: height, fill: fill, line: line, blocks: value, anchor: anchor, parts: parts, autoFit: autoFit);
}

/// Where a floating picture or shape sits. Offsets are points from the
/// [hFrom] / [vFrom] reference ('page', 'margin', 'column', 'paragraph', ...).
class DocxAnchor {
  final String hFrom;
  final String vFrom;
  final double? x;
  final double? y;
  final String? hAlign;
  final String? vAlign;
  final bool behind;

  const DocxAnchor({this.hFrom = 'column', this.vFrom = 'paragraph', this.x, this.y, this.hAlign, this.vAlign, this.behind = false});

  /// Placed on the page itself (cover panels, bands), not in the text flow.
  bool get onPage => (hFrom == 'page' || hFrom == 'margin') && (vFrom == 'page' || vFrom == 'margin' || vFrom == 'topMargin');
}

class DocxRunStyle {
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final bool? caps;
  final bool? hidden;
  final double? size;
  final Color? color;
  final Color? highlight;
  final String? font;
  final String? vertAlign;

  const DocxRunStyle({
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.caps,
    this.hidden,
    this.size,
    this.color,
    this.highlight,
    this.font,
    this.vertAlign,
  });

  static const empty = DocxRunStyle();

  DocxRunStyle over(DocxRunStyle? o) => o == null
      ? this
      : DocxRunStyle(
          bold: o.bold ?? bold,
          italic: o.italic ?? italic,
          underline: o.underline ?? underline,
          strike: o.strike ?? strike,
          caps: o.caps ?? caps,
          hidden: o.hidden ?? hidden,
          size: o.size ?? size,
          color: o.color ?? color,
          highlight: o.highlight ?? highlight,
          font: o.font ?? font,
          vertAlign: o.vertAlign ?? vertAlign,
        );
}

class DocxParaStyle {
  final String? align;
  final double? before;
  final double? after;

  /// Line spacing: a multiple of single when [lineExact] is null, else points.
  final double? line;
  final bool? lineExact;
  final double? indentLeft;
  final double? indentRight;
  final double? firstLine;
  final double? hanging;
  final Color? shading;
  final DocxBorders? borders;
  final int? numId;
  final int? ilvl;
  final bool? contextualSpacing;
  final String? styleId;

  const DocxParaStyle({
    this.align,
    this.before,
    this.after,
    this.line,
    this.lineExact,
    this.indentLeft,
    this.indentRight,
    this.firstLine,
    this.hanging,
    this.shading,
    this.borders,
    this.numId,
    this.ilvl,
    this.contextualSpacing,
    this.styleId,
  });

  DocxParaStyle over(DocxParaStyle? o) => o == null
      ? this
      : DocxParaStyle(
          align: o.align ?? align,
          before: o.before ?? before,
          after: o.after ?? after,
          line: o.line ?? line,
          lineExact: o.line != null ? o.lineExact : lineExact,
          indentLeft: o.indentLeft ?? indentLeft,
          indentRight: o.indentRight ?? indentRight,
          firstLine: o.firstLine ?? (o.hanging != null ? null : firstLine),
          hanging: o.hanging ?? (o.firstLine != null ? null : hanging),
          shading: o.shading ?? shading,
          borders: borders == null ? o.borders : borders!.over(o.borders),
          numId: o.numId ?? numId,
          ilvl: o.ilvl ?? ilvl,
          contextualSpacing: o.contextualSpacing ?? contextualSpacing,
          styleId: o.styleId ?? styleId,
        );
}

// -----------------------------------------------------------------------------
// Reader
// -----------------------------------------------------------------------------

final RegExp placeholderPattern = RegExp(r'\{\{[^{}]{1,80}\}\}');

String? _attr(XmlElement? e, String local) {
  if (e == null) return null;
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

XmlElement? _child(XmlElement? e, String local) {
  if (e == null) return null;
  for (final c in e.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement e, String local) => e.childElements.where((c) => c.name.local == local);

Iterable<XmlElement> _descendants(XmlElement e, String local) =>
    e.descendants.whereType<XmlElement>().where((c) => c.name.local == local);

double? _num(String? v) => v == null ? null : double.tryParse(v);

double? _twips(String? v) {
  final n = _num(v);
  return n == null ? null : n / 20;
}

bool? _onOff(XmlElement? e) {
  if (e == null) return null;
  final v = _attr(e, 'val');
  return v == null || !(v == '0' || v == 'false' || v == 'off' || v == 'none');
}

Color? _color(String? hex) {
  if (hex == null || hex == 'auto' || hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

const Map<String, Color> _highlights = {
  'yellow': Color(0xFFFFFF00),
  'green': Color(0xFF00FF00),
  'cyan': Color(0xFF00FFFF),
  'magenta': Color(0xFFFF00FF),
  'blue': Color(0xFF0000FF),
  'red': Color(0xFFFF0000),
  'darkBlue': Color(0xFF000080),
  'darkCyan': Color(0xFF008080),
  'darkGreen': Color(0xFF008000),
  'darkMagenta': Color(0xFF800080),
  'darkRed': Color(0xFF800000),
  'darkYellow': Color(0xFF808000),
  'darkGray': Color(0xFF808080),
  'lightGray': Color(0xFFC0C0C0),
  'black': Color(0xFF000000),
};

class _Style {
  final String type;
  final String? basedOn;
  final DocxRunStyle? run;
  final DocxParaStyle? para;
  final DocxBorders? tableBorders;

  const _Style(this.type, this.basedOn, this.run, this.para, this.tableBorders);
}

class _Level {
  final String format;
  final String text;
  final int start;
  final double? indentLeft;
  final double? hanging;

  const _Level(this.format, this.text, this.start, this.indentLeft, this.hanging);
}

class _Part {
  final String path;
  final Map<String, String> rels;

  const _Part(this.path, this.rels);
}

class _DocxReader {
  final Map<String, Uint8List> _files = {};
  final Map<String, _Style> _styles = {};
  DocxRunStyle _defaultRun = DocxRunStyle.empty;
  DocxParaStyle _defaultPara = const DocxParaStyle();
  String? _defaultParaStyle;
  final Map<int, Map<int, _Level>> _numbering = {};
  final Map<String, int> _counters = {};
  final List<DocxSection> _sections = [];

  _DocxReader(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (file.isFile) _files[file.name] = Uint8List.fromList(file.content as List<int>);
    }
  }

  XmlDocument? _xml(String path) {
    final data = _files[path];
    if (data == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(data, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _rels(String partPath) {
    final slash = partPath.lastIndexOf('/');
    final dir = slash < 0 ? '' : partPath.substring(0, slash);
    final name = partPath.substring(slash + 1);
    final xml = _xml('${dir.isEmpty ? '' : '$dir/'}_rels/$name.rels');
    final out = <String, String>{};
    if (xml == null) return out;
    for (final rel in _descendants(xml.rootElement, 'Relationship')) {
      final id = _attr(rel, 'Id');
      final target = _attr(rel, 'Target');
      if (id == null || target == null || _attr(rel, 'TargetMode') == 'External') continue;
      out[id] = _resolve(dir, target);
    }
    return out;
  }

  String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = [...dir.split('/').where((p) => p.isNotEmpty), ...target.split('/')];
    final out = <String>[];
    for (final p in parts) {
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (p != '.') {
        out.add(p);
      }
    }
    return out.join('/');
  }

  DocxDocument read() {
    _readStyles();
    _readNumbering();
    final docPath = 'word/document.xml';
    final xml = _xml(docPath);
    if (xml == null) throw const FormatException('Not a Word document (no word/document.xml)');
    final part = _Part(docPath, _rels(docPath));
    final body = _child(xml.rootElement, 'body');
    final blocks = body == null ? <DocxBlock>[] : _blocks(body, part);
    final finalSect = body == null ? null : _child(body, 'sectPr');
    _sections.add(_section(finalSect));

    final parts = <String, List<DocxBlock>>{};
    for (final entry in part.rels.entries) {
      final target = entry.value;
      if (!(target.contains('header') || target.contains('footer'))) continue;
      final px = _xml(target);
      if (px == null) continue;
      parts[entry.key] = _blocks(px.rootElement, _Part(target, _rels(target)));
    }
    return DocxDocument(body: blocks, sections: _sections, parts: parts);
  }

  // --- styles ---------------------------------------------------------------

  void _readStyles() {
    final xml = _xml('word/styles.xml');
    if (xml == null) return;
    final root = xml.rootElement;
    final defaults = _child(root, 'docDefaults');
    _defaultRun = _runProps(_child(_child(defaults, 'rPrDefault'), 'rPr')) ?? DocxRunStyle.empty;
    _defaultPara = _paraProps(_child(_child(defaults, 'pPrDefault'), 'pPr')) ?? const DocxParaStyle();
    for (final s in _children(root, 'style')) {
      final id = _attr(s, 'styleId');
      if (id == null) continue;
      final type = _attr(s, 'type') ?? 'paragraph';
      if (type == 'paragraph' && _attr(s, 'default') == '1') {
        _defaultParaStyle = id;
      }
      final tblPr = _child(s, 'tblPr');
      _styles[id] = _Style(
        type,
        _attr(_child(s, 'basedOn'), 'val'),
        _runProps(_child(s, 'rPr')),
        _paraProps(_child(s, 'pPr')),
        _borders(_child(tblPr, 'tblBorders')),
      );
    }
  }

  List<_Style> _chain(String? id) {
    final out = <_Style>[];
    var current = id;
    var guard = 0;
    while (current != null && guard++ < 20) {
      final style = _styles[current];
      if (style == null) break;
      out.insert(0, style);
      current = style.basedOn;
    }
    return out;
  }

  DocxRunStyle _styleRun(String? id) {
    var out = DocxRunStyle.empty;
    for (final s in _chain(id)) {
      out = out.over(s.run);
    }
    return out;
  }

  DocxParaStyle _stylePara(String? id) {
    var out = const DocxParaStyle();
    for (final s in _chain(id)) {
      out = out.over(s.para);
    }
    return out;
  }

  DocxBorders? _styleTableBorders(String? id) {
    DocxBorders? out;
    for (final s in _chain(id)) {
      if (s.tableBorders != null) out = (out ?? DocxBorders.none).over(s.tableBorders);
    }
    return out;
  }

  // --- numbering --------------------------------------------------------------

  void _readNumbering() {
    final xml = _xml('word/numbering.xml');
    if (xml == null) return;
    final abstracts = <String, Map<int, _Level>>{};
    for (final a in _children(xml.rootElement, 'abstractNum')) {
      final levels = <int, _Level>{};
      for (final lvl in _children(a, 'lvl')) {
        final ilvl = int.tryParse(_attr(lvl, 'ilvl') ?? '') ?? 0;
        final ind = _child(_child(lvl, 'pPr'), 'ind');
        levels[ilvl] = _Level(
          _attr(_child(lvl, 'numFmt'), 'val') ?? 'decimal',
          _attr(_child(lvl, 'lvlText'), 'val') ?? '',
          int.tryParse(_attr(_child(lvl, 'start'), 'val') ?? '') ?? 1,
          _twips(_attr(ind, 'left') ?? _attr(ind, 'start')),
          _twips(_attr(ind, 'hanging')),
        );
      }
      final id = _attr(a, 'abstractNumId');
      if (id != null) abstracts[id] = levels;
    }
    for (final n in _children(xml.rootElement, 'num')) {
      final id = int.tryParse(_attr(n, 'numId') ?? '');
      final abs = _attr(_child(n, 'abstractNumId'), 'val');
      if (id != null && abs != null && abstracts[abs] != null) _numbering[id] = abstracts[abs]!;
    }
  }

  String? _listLabel(int? numId, int? ilvl) {
    if (numId == null || numId == 0) return null;
    final levels = _numbering[numId];
    final level = levels?[ilvl ?? 0];
    if (level == null) return null;
    final lvl = ilvl ?? 0;
    final key = '$numId:$lvl';
    _counters[key] = (_counters[key] ?? (level.start - 1)) + 1;
    // A higher level restarts the deeper ones.
    for (var deeper = lvl + 1; deeper < 9; deeper++) {
      _counters.remove('$numId:$deeper');
    }
    if (level.format == 'bullet') return '•';
    if (level.format == 'none') return '';
    return level.text.replaceAllMapped(RegExp(r'%(\d)'), (m) {
      final which = int.parse(m.group(1)!) - 1;
      final value = _counters['$numId:$which'] ?? (levels?[which]?.start ?? 1);
      return _formatNumber(value, levels?[which]?.format ?? 'decimal');
    });
  }

  String _formatNumber(int n, String format) {
    switch (format) {
      case 'lowerLetter':
        return String.fromCharCode(96 + ((n - 1) % 26) + 1);
      case 'upperLetter':
        return String.fromCharCode(64 + ((n - 1) % 26) + 1);
      case 'lowerRoman':
        return _roman(n).toLowerCase();
      case 'upperRoman':
        return _roman(n);
      default:
        return '$n';
    }
  }

  String _roman(int n) {
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    final out = StringBuffer();
    var rest = n;
    for (var i = 0; i < values.length; i++) {
      while (rest >= values[i]) {
        out.write(symbols[i]);
        rest -= values[i];
      }
    }
    return out.toString();
  }

  // --- properties -------------------------------------------------------------

  DocxRunStyle? _runProps(XmlElement? rPr) {
    if (rPr == null) return null;
    final u = _child(rPr, 'u');
    final fonts = _child(rPr, 'rFonts');
    final sz = _num(_attr(_child(rPr, 'sz'), 'val'));
    final hl = _attr(_child(rPr, 'highlight'), 'val');
    final shd = _attr(_child(rPr, 'shd'), 'fill');
    return DocxRunStyle(
      bold: _onOff(_child(rPr, 'b')),
      italic: _onOff(_child(rPr, 'i')),
      underline: u == null ? null : _attr(u, 'val') != 'none',
      strike: _onOff(_child(rPr, 'strike')) ?? _onOff(_child(rPr, 'dstrike')),
      caps: _onOff(_child(rPr, 'caps')),
      hidden: _onOff(_child(rPr, 'vanish')),
      size: sz == null ? null : sz / 2,
      color: _color(_attr(_child(rPr, 'color'), 'val')),
      highlight: hl != null ? _highlights[hl] : _color(shd),
      font: _attr(fonts, 'ascii') ?? _attr(fonts, 'hAnsi'),
      vertAlign: _attr(_child(rPr, 'vertAlign'), 'val'),
    );
  }

  DocxParaStyle? _paraProps(XmlElement? pPr) {
    if (pPr == null) return null;
    final spacing = _child(pPr, 'spacing');
    final ind = _child(pPr, 'ind');
    final numPr = _child(pPr, 'numPr');
    final lineRule = _attr(spacing, 'lineRule');
    final lineRaw = _num(_attr(spacing, 'line'));
    double? line;
    bool? exact;
    if (lineRaw != null) {
      if (lineRule == 'exact' || lineRule == 'atLeast') {
        line = lineRaw / 20;
        exact = true;
      } else {
        line = lineRaw / 240;
        exact = false;
      }
    }
    final beforeAuto = _attr(spacing, 'beforeAutospacing') == '1';
    final afterAuto = _attr(spacing, 'afterAutospacing') == '1';
    return DocxParaStyle(
      align: _attr(_child(pPr, 'jc'), 'val'),
      before: beforeAuto ? 14 : _twips(_attr(spacing, 'before')),
      after: afterAuto ? 14 : _twips(_attr(spacing, 'after')),
      line: line,
      lineExact: exact,
      indentLeft: _twips(_attr(ind, 'left') ?? _attr(ind, 'start')),
      indentRight: _twips(_attr(ind, 'right') ?? _attr(ind, 'end')),
      firstLine: _twips(_attr(ind, 'firstLine')),
      hanging: _twips(_attr(ind, 'hanging')),
      shading: _color(_attr(_child(pPr, 'shd'), 'fill')),
      borders: _borders(_child(pPr, 'pBdr')),
      numId: int.tryParse(_attr(_child(numPr, 'numId'), 'val') ?? ''),
      ilvl: int.tryParse(_attr(_child(numPr, 'ilvl'), 'val') ?? ''),
      contextualSpacing: _onOff(_child(pPr, 'contextualSpacing')),
      styleId: _attr(_child(pPr, 'pStyle'), 'val'),
    );
  }

  DocxBorder? _border(XmlElement? e) {
    if (e == null) return null;
    final val = _attr(e, 'val');
    if (val == null || val == 'nil' || val == 'none') return const DocxBorder(0, Color(0x00000000));
    final sz = _num(_attr(e, 'sz')) ?? 4;
    return DocxBorder((sz / 8).clamp(0.25, 6).toDouble(), _color(_attr(e, 'color')) ?? const Color(0xFF000000));
  }

  DocxBorders? _borders(XmlElement? e) {
    if (e == null) return null;
    return DocxBorders(
      top: _border(_child(e, 'top')),
      bottom: _border(_child(e, 'bottom')),
      left: _border(_child(e, 'left') ?? _child(e, 'start')),
      right: _border(_child(e, 'right') ?? _child(e, 'end')),
      insideH: _border(_child(e, 'insideH')),
      insideV: _border(_child(e, 'insideV')),
    );
  }

  DocxSection _section(XmlElement? sectPr) {
    if (sectPr == null) return const DocxSection();
    final pgSz = _child(sectPr, 'pgSz');
    final pgMar = _child(sectPr, 'pgMar');
    String? ref(String kind, String type) {
      for (final r in _children(sectPr, kind)) {
        if ((_attr(r, 'type') ?? 'default') == type) return _attr(r, 'id');
      }
      return null;
    }

    return DocxSection(
      pageWidth: _twips(_attr(pgSz, 'w')) ?? 612,
      pageHeight: _twips(_attr(pgSz, 'h')) ?? 792,
      margins: EdgeInsets.fromLTRB(
        _twips(_attr(pgMar, 'left')) ?? 72,
        (_twips(_attr(pgMar, 'top')) ?? 72).abs(),
        _twips(_attr(pgMar, 'right')) ?? 72,
        (_twips(_attr(pgMar, 'bottom')) ?? 72).abs(),
      ),
      headerId: ref('headerReference', 'default'),
      footerId: ref('footerReference', 'default'),
      firstHeaderId: ref('headerReference', 'first'),
      firstFooterId: ref('footerReference', 'first'),
      titlePage: _onOff(_child(sectPr, 'titlePg')) ?? false,
      headerDistance: _twips(_attr(pgMar, 'header')) ?? 36,
      footerDistance: _twips(_attr(pgMar, 'footer')) ?? 36,
    );
  }

  // --- content ---------------------------------------------------------------

  List<DocxBlock> _blocks(XmlElement container, _Part part) {
    final out = <DocxBlock>[];
    for (final e in container.childElements) {
      switch (e.name.local) {
        case 'p':
          out.add(_paragraph(e, part));
        case 'tbl':
          out.add(_table(e, part));
        case 'sdt':
          final content = _child(e, 'sdtContent');
          if (content != null) out.addAll(_blocks(content, part));
        case 'customXml':
        case 'ins':
          out.addAll(_blocks(e, part));
        default:
          break;
      }
    }
    return out;
  }

  DocxParagraph _paragraph(XmlElement p, _Part part) {
    final pPr = _child(p, 'pPr');
    final own = _paraProps(pPr);
    final styleId = own?.styleId ?? _defaultParaStyle;
    var style = _defaultPara.over(_stylePara(styleId)).over(own);
    final baseRun = _defaultRun.over(_styleRun(styleId));
    final mark = baseRun.over(_runProps(_child(pPr, 'rPr')));

    String? label;
    if (style.numId != null) {
      label = _listLabel(style.numId, style.ilvl);
      final level = _numbering[style.numId]?[style.ilvl ?? 0];
      if (level != null && own?.indentLeft == null) {
        style = style.over(DocxParaStyle(indentLeft: level.indentLeft, hanging: level.hanging));
      }
    }

    final inlines = <DocxInline>[];
    _inlines(p, part, baseRun, inlines);

    int? sectionIndex;
    final sectPr = _child(pPr, 'sectPr');
    if (sectPr != null) {
      _sections.add(_section(sectPr));
      sectionIndex = _sections.length - 1;
    }

    return DocxParagraph(
      style: style,
      markStyle: mark,
      inlines: tokenize(inlines),
      listLabel: label,
      sectionIndex: sectionIndex,
      pageBreakBefore: _onOff(_child(pPr, 'pageBreakBefore')) ?? false,
    );
  }

  void _inlines(XmlElement container, _Part part, DocxRunStyle base, List<DocxInline> out) {
    for (final e in container.childElements) {
      switch (e.name.local) {
        case 'r':
          _run(e, part, base, out);
        case 'hyperlink':
        case 'smartTag':
        case 'ins':
        case 'customXml':
        case 'fldSimple':
          _inlines(e, part, base, out);
        case 'sdt':
          final content = _child(e, 'sdtContent');
          if (content != null) _inlines(content, part, base, out);
        default:
          break;
      }
    }
  }

  void _run(XmlElement r, _Part part, DocxRunStyle base, List<DocxInline> out) {
    final rPr = _child(r, 'rPr');
    final own = _runProps(rPr);
    final charStyle = _attr(_child(rPr, 'rStyle'), 'val');
    // Hidden runs stay (block markers are often hidden text); the page skips
    // drawing them.
    final style = base.over(charStyle == null ? null : _styleRun(charStyle)).over(own);
    for (final e in r.childElements) {
      switch (e.name.local) {
        case 't':
          out.add(DocxText(e.innerText, style));
        case 'tab':
          out.add(const DocxTab());
        case 'br':
          out.add(DocxBreak(page: _attr(e, 'type') == 'page'));
        case 'cr':
          out.add(const DocxBreak());
        case 'noBreakHyphen':
          out.add(DocxText('-', style));
        case 'sym':
          out.add(DocxText('•', style));
        case 'drawing':
          final drawn = _drawing(e, part);
          if (drawn != null) out.add(drawn);
        case 'AlternateContent':
          // Modern shapes (wps) in mc:Choice; the VML fallback is skipped.
          final choice = _child(e, 'Choice');
          final drawing = choice == null ? null : _descendants(choice, 'drawing').firstOrNull;
          final drawn = drawing == null ? null : _drawing(drawing, part);
          if (drawn != null) out.add(drawn);
        default:
          break;
      }
    }
  }

  DocxInline? _drawing(XmlElement drawing, _Part part) {
    final holder = _child(drawing, 'inline') ?? _child(drawing, 'anchor');
    if (holder == null) return null;
    final extent = _child(holder, 'extent');
    final width = (_num(_attr(extent, 'cx')) ?? 0) / 12700;
    final height = (_num(_attr(extent, 'cy')) ?? 0) / 12700;
    final docPr = _child(holder, 'docPr');
    final alt = '${_attr(docPr, 'descr') ?? ''} ${_attr(docPr, 'title') ?? ''}';
    final token = placeholderPattern.firstMatch(alt)?.group(0);
    final anchor = holder.name.local == 'anchor' ? _anchor(holder) : null;

    // What the drawing is: a shape / text box (wps), a picture, or a group.
    final graphicData = _descendants(holder, 'graphicData').firstOrNull;
    final uri = _attr(graphicData, 'uri') ?? '';
    final shape = uri.endsWith('wordprocessingShape') ? _descendants(holder, 'wsp').firstOrNull : null;
    if (uri.endsWith('wordprocessingGroup')) return _group(holder, width, height, anchor);
    if (shape != null) {
      final spPr = _child(shape, 'spPr');
      final content = _descendants(shape, 'txbxContent').firstOrNull;
      final fill = _solidFill(_child(spPr, 'solidFill'));
      final ln = _child(spPr, 'ln');
      final lineFill = _solidFill(_child(ln, 'solidFill'));
      final blocks = content == null ? <DocxBlock>[] : _blocks(content, part);
      if (blocks.isEmpty && fill == null) return null;
      final bodyPr = _descendants(shape, 'bodyPr').firstOrNull;
      return DocxShape(
        autoFit: bodyPr != null && _child(bodyPr, 'spAutoFit') != null,
        width: width,
        height: height,
        fill: fill,
        line: lineFill == null || _child(ln, 'noFill') != null ? null : DocxBorder(((_num(_attr(ln, 'w')) ?? 9525) / 12700).clamp(0.25, 6).toDouble(), lineFill),
        blocks: blocks,
        anchor: anchor,
      );
    }

    final blip = _descendants(holder, 'blip').firstOrNull;
    if (blip == null && token == null) return null;
    final crop = _descendants(holder, 'srcRect').firstOrNull;
    final rid = _attr(blip, 'embed');
    final target = rid == null ? null : part.rels[rid];
    return DocxImage(
      bytes: target == null ? null : _files[target],
      width: width,
      height: height,
      slot: token,
      anchor: anchor,
      crop: crop == null
          ? null
          : EdgeInsets.fromLTRB(
              (_num(_attr(crop, 'l')) ?? 0) / 100000,
              (_num(_attr(crop, 't')) ?? 0) / 100000,
              (_num(_attr(crop, 'r')) ?? 0) / 100000,
              (_num(_attr(crop, 'b')) ?? 0) / 100000,
            ),
    );
  }

  /// A group of shapes (decorative bars and boxes): its filled rectangles,
  /// placed in the group's frame. Text and pictures inside groups are skipped.
  DocxShape? _group(XmlElement holder, double width, double height, DocxAnchor? anchor) {
    final group = _descendants(holder, 'wgp').firstOrNull;
    if (group == null) return null;
    final xfrm = _child(_child(group, 'grpSpPr'), 'xfrm');
    final chOff = _child(xfrm, 'chOff');
    final chExt = _child(xfrm, 'chExt');
    final ox = _num(_attr(chOff, 'x')) ?? 0;
    final oy = _num(_attr(chOff, 'y')) ?? 0;
    final ew = _num(_attr(chExt, 'cx')) ?? 0;
    final eh = _num(_attr(chExt, 'cy')) ?? 0;
    if (ew <= 0 || eh <= 0) return null;
    final parts = <(Rect, Color)>[];
    for (final wsp in _descendants(group, 'wsp')) {
      final spPr = _child(wsp, 'spPr');
      final fill = _solidFill(_child(spPr, 'solidFill'));
      final x = _child(spPr, 'xfrm');
      final off = _child(x, 'off');
      final ext = _child(x, 'ext');
      if (fill == null || off == null || ext == null) continue;
      parts.add((
        Rect.fromLTWH(
          ((_num(_attr(off, 'x')) ?? 0) - ox) / ew * width,
          ((_num(_attr(off, 'y')) ?? 0) - oy) / eh * height,
          (_num(_attr(ext, 'cx')) ?? 0) / ew * width,
          (_num(_attr(ext, 'cy')) ?? 0) / eh * height,
        ),
        fill,
      ));
    }
    if (parts.isEmpty) return null;
    return DocxShape(width: width, height: height, parts: parts, anchor: anchor);
  }

  Color? _solidFill(XmlElement? solid) {
    if (solid == null) return null;
    final srgb = _child(solid, 'srgbClr');
    return _color(_attr(srgb, 'val'));
  }

  DocxAnchor _anchor(XmlElement anchor) {
    // Positions may sit inside mc:AlternateContent (wp14 percentages in the
    // Choice, absolute offsets in the Fallback): take one with an offset or
    // an alignment.
    XmlElement? position(String local) {
      final all = _descendants(anchor, local).toList();
      return all.where((p) => _child(p, 'posOffset') != null || _child(p, 'align') != null).firstOrNull ?? all.firstOrNull;
    }

    final h = position('positionH');
    final v = position('positionV');
    final hOff = _num(_child(h, 'posOffset')?.innerText);
    final vOff = _num(_child(v, 'posOffset')?.innerText);
    return DocxAnchor(
      hFrom: _attr(h, 'relativeFrom') ?? 'column',
      vFrom: _attr(v, 'relativeFrom') ?? 'paragraph',
      x: hOff == null ? null : hOff / 12700,
      y: vOff == null ? null : vOff / 12700,
      hAlign: _child(h, 'align')?.innerText,
      vAlign: _child(v, 'align')?.innerText,
      behind: _attr(anchor, 'behindDoc') == '1',
    );
  }

  DocxTable _table(XmlElement tbl, _Part part) {
    final tblPr = _child(tbl, 'tblPr');
    final styleId = _attr(_child(tblPr, 'tblStyle'), 'val');
    final borders = (_styleTableBorders(styleId) ?? DocxBorders.none).over(_borders(_child(tblPr, 'tblBorders')));
    final grid = [
      for (final col in _children(_child(tbl, 'tblGrid') ?? XmlElement(XmlName('tblGrid')), 'gridCol')) _twips(_attr(col, 'w')) ?? 0,
    ];
    final mar = _child(tblPr, 'tblCellMar');
    final margin = EdgeInsets.fromLTRB(
      _twips(_attr(_child(mar, 'left') ?? _child(mar, 'start'), 'w')) ?? 5.4,
      _twips(_attr(_child(mar, 'top'), 'w')) ?? 0,
      _twips(_attr(_child(mar, 'right') ?? _child(mar, 'end'), 'w')) ?? 5.4,
      _twips(_attr(_child(mar, 'bottom'), 'w')) ?? 0,
    );
    final rows = <DocxRow>[];
    void addRows(XmlElement container) {
      for (final e in container.childElements) {
        if (e.name.local == 'tr') {
          rows.add(_row(e, part));
        } else if (e.name.local == 'sdt') {
          final content = _child(e, 'sdtContent');
          if (content != null) addRows(content);
        }
      }
    }

    addRows(tbl);
    return DocxTable(
      grid: grid,
      rows: rows,
      borders: borders,
      cellMargin: margin,
      align: _attr(_child(tblPr, 'jc'), 'val'),
      indent: _twips(_attr(_child(tblPr, 'tblInd'), 'w')),
    );
  }

  DocxRow _row(XmlElement tr, _Part part) {
    final trPr = _child(tr, 'trPr');
    final h = _child(trPr, 'trHeight');
    final cells = <DocxCell>[];
    void addCells(XmlElement container) {
      for (final e in container.childElements) {
        if (e.name.local == 'tc') {
          cells.add(_cell(e, part));
        } else if (e.name.local == 'sdt') {
          final content = _child(e, 'sdtContent');
          if (content != null) addCells(content);
        }
      }
    }

    addCells(tr);
    return DocxRow(
      cells: cells,
      height: _twips(_attr(h, 'val')),
      exactHeight: _attr(h, 'hRule') == 'exact',
      gridBefore: int.tryParse(_attr(_child(trPr, 'gridBefore'), 'val') ?? '') ?? 0,
    );
  }

  DocxCell _cell(XmlElement tc, _Part part) {
    final tcPr = _child(tc, 'tcPr');
    final vMerge = _child(tcPr, 'vMerge');
    final mar = _child(tcPr, 'tcMar');
    return DocxCell(
      blocks: _blocks(tc, part),
      gridSpan: int.tryParse(_attr(_child(tcPr, 'gridSpan'), 'val') ?? '') ?? 1,
      vMerge: vMerge == null ? null : (_attr(vMerge, 'val') ?? 'continue'),
      shading: _color(_attr(_child(tcPr, 'shd'), 'fill')),
      borders: _borders(_child(tcPr, 'tcBorders')),
      vAlign: _attr(_child(tcPr, 'vAlign'), 'val'),
      margin: mar == null
          ? null
          : EdgeInsets.fromLTRB(
              _twips(_attr(_child(mar, 'left') ?? _child(mar, 'start'), 'w')) ?? 5.4,
              _twips(_attr(_child(mar, 'top'), 'w')) ?? 0,
              _twips(_attr(_child(mar, 'right') ?? _child(mar, 'end'), 'w')) ?? 5.4,
              _twips(_attr(_child(mar, 'bottom'), 'w')) ?? 0,
            ),
    );
  }
}

/// Split text runs so every `{{TOKEN}}` is one [DocxSlot] (styled like the run
/// it starts in, as fill_template.py's run-aware replace does), even when Word
/// split the token across runs.
List<DocxInline> tokenize(List<DocxInline> inlines) {
  final text = StringBuffer();
  for (final i in inlines) {
    if (i is DocxText) text.write(i.text);
  }
  final full = text.toString();
  final matches = placeholderPattern.allMatches(full).toList();
  if (matches.isEmpty) return inlines;

  final out = <DocxInline>[];
  var offset = 0;
  var m = 0;
  for (final inline in inlines) {
    if (inline is! DocxText) {
      out.add(inline);
      continue;
    }
    final start = offset;
    final end = offset + inline.text.length;
    var cursor = start;
    while (cursor < end) {
      while (m < matches.length && matches[m].end <= cursor) {
        m++;
      }
      final match = m < matches.length ? matches[m] : null;
      if (match == null || match.start >= end) {
        out.add(DocxText(full.substring(cursor, end), inline.style));
        cursor = end;
      } else if (match.start > cursor) {
        out.add(DocxText(full.substring(cursor, match.start), inline.style));
        cursor = match.start;
      } else {
        // Inside a token: emit the slot once, where the token starts.
        if (match.start >= start && cursor == match.start) out.add(DocxSlot(match.group(0)!, inline.style));
        cursor = match.end < end ? match.end : end;
      }
    }
    offset = end;
  }
  return out;
}
