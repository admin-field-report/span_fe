import 'package:flutter/material.dart';
import 'models/report_element.dart';

// Converts between the report template API's `header_html`/`footer_html`
// fields and this editor's [ReportElement] model. These two functions are
// inverses of each other: [parseRegionHtml] loads a fetched region into
// editable elements, [buildRegionHtml] turns the edited elements back into
// markup for saving.
//
// Saved markup is a responsive flexbox fragment (full-width root, one
// left/center/right zone row, info bar docked at the bottom; no class
// attributes — every visual property is inline style). The editor's exact
// pixel geometry travels alongside in `data-left`/`data-top` attributes for
// the round-trip. [parseRegionHtml] also still understands the legacy
// pixel-absolute format (`position:absolute` spans, empty background rects)
// that older saved templates contain.
//
// Field id `reportDate`/`inspectorName` is a codec-owned convention (not
// something the backend assigns): the editor's info bar renders as one docked
// bottom strip with two texts, so it's serialized as two spans and merged
// back into a single `ReportElementType.infoBar` on parse by recognizing that
// exact pair of field ids.

/// Parses a single header/footer region fragment into a container
/// [ReportElement] with children — or `null` if the fragment is empty/missing,
/// so the caller can leave that region blank instead of inventing content.
///
/// Only `data-field` spans (text) and `data-field` images (treated as Logo)
/// become editable elements; purely decorative background rectangles are
/// collapsed into the region's own [ReportElement.backgroundColor] (the
/// largest one, by area) rather than being modeled individually. The one
/// exception is the info bar's own colored strip, which is recognized by its
/// bottom-flush position and re-attached to the merged info bar element.
ReportElement? parseRegionHtml({
  required String? regionHtml,
  required ReportElementType regionType,
  required String Function() nextId,
}) {
  if (regionHtml == null || regionHtml.trim().isEmpty) return null;

  final rootMatch = RegExp(r'^\s*<div ([^>]*)>').firstMatch(regionHtml);
  final rootAttrs = rootMatch?.group(1) ?? '';
  final rootStyle = _parseStyleMap(_attr(rootAttrs, 'style') ?? '');
  // New-format roots are `width:100%` (no usable pixel value) but carry the
  // editor page width they were authored against in `data-width`; legacy
  // roots have a pixel width in the style itself.
  final regionWidth = _attrPx(rootAttrs, 'data-width') ??
      ((rootStyle['width']?.contains('%') ?? false) ? 816.0 : _px(rootStyle, 'width', 595.28));
  final regionHeight = _px(rootStyle, 'height', 117.86);

  // New-format regions carry their background directly on the root; the
  // empty-rect scan below only applies to legacy absolute-position markup.
  Color backgroundColor = _parseColor(rootStyle['background-color'], Colors.white);
  double bestArea = 0;
  Color? infoBarBackground;
  double? infoBarHeight;

  // New-format info bar: one flex wrapper carrying the strip's own
  // background and height.
  final infoBarWrapper = RegExp(r'<div data-region="infobar" style="([^"]*)"').firstMatch(regionHtml);
  if (infoBarWrapper != null) {
    final style = _parseStyleMap(infoBarWrapper.group(1)!);
    infoBarBackground = _parseColor(style['background-color'], Colors.black);
    infoBarHeight = _px(style, 'height', 40);
  }

  for (final m in RegExp(r'<div style="([^"]*)"></div>').allMatches(regionHtml)) {
    final style = _parseStyleMap(m.group(1)!);
    final top = _px(style, 'top');
    final h = _px(style, 'height');
    // Full-width rects are saved as `width:100%`; treat that as the region's
    // own width so the "largest rect wins" comparison stays meaningful.
    final w = (style['width']?.contains('%') ?? false) ? regionWidth : _px(style, 'width');
    final area = w * h;
    final bg = style['background-color'];
    if (bg == null) continue;
    if (area > bestArea) {
      bestArea = area;
      backgroundColor = _parseColor(bg, Colors.white);
    }
    // The info bar's own strip is bottom-flush but shorter than the full
    // region (the full-region background always starts at top:0).
    if (top > 1 && (top + h - regionHeight).abs() < 2) {
      infoBarBackground = _parseColor(bg, Colors.black);
      infoBarHeight = h;
    }
  }

  final children = <ReportElement>[];
  ReportElement? infoBarDate;
  ReportElement? infoBarInspector;

  // Attribute order varies between formats (new spans carry
  // `data-left`/`data-top` between data-field and style), so capture the
  // whole attribute list and pick fields out of it.
  for (final m in RegExp(r'<span ([^>]*?)>(.*?)</span>', dotAll: true).allMatches(regionHtml)) {
    final attrs = m.group(1)!;
    final fieldId = _attr(attrs, 'data-field');
    if (fieldId == null) continue;
    final style = _parseStyleMap(_attr(attrs, 'style') ?? '');
    final rawText = (m.group(2) ?? '').trim();
    final displayText = (rawText.isEmpty || rawText == '{{placeholder}}') ? _friendlyLabel(fieldId) : rawText;

    final align = _parseAlign(style['text-align']);

    // Left-aligned text elements are never given an explicit size anywhere
    // in this editor (they always auto-size to their content — see
    // ReportElement's Size.zero default), so importing one here would force
    // a fixed-size Container on reload instead of letting the text size
    // itself, clipping/wrapping content that fit fine before saving. Center/
    // right-aligned text is the one exception: those rely on a sized box for
    // the alignment to have anything to align within — and that box must be
    // the width it was authored with (`data-width` in the new format, the
    // style's own pixel width in the legacy one), not the whole region's:
    // e.g. the "Split Banner" header centers its texts in a 250px box at
    // mid-page, and importing that as a region-wide box starting at the same
    // x pushed it out past the header's right edge.
    final authoredWidth = _attrPx(attrs, 'data-width');
    final Size? size;
    if (authoredWidth != null && authoredWidth > 0) {
      size = Size(authoredWidth, 0);
    } else if (align == TextAlign.left) {
      size = null;
    } else {
      size = Size(_px(style, 'width', regionWidth), 0);
    }

    final element = ReportElement(
      id: nextId(),
      type: ReportElementType.text,
      toolType: fieldId,
      text: displayText,
      position: Offset(
        _attrPx(attrs, 'data-left') ?? _px(style, 'left'),
        _attrPx(attrs, 'data-top') ?? _px(style, 'top'),
      ),
      size: size,
      fontSize: _px(style, 'font-size', 12),
      isBold: style['font-weight']?.trim() == 'bold',
      isItalic: style['font-style']?.trim() == 'italic',
      color: _parseColor(style['color'], Colors.black),
      align: align,
    );

    // The info bar is split into two spans on save; recognize that exact
    // pair here and merge them back into one docked element below instead
    // of importing them as two independent free-floating texts.
    if (fieldId == 'reportDate') {
      infoBarDate = element;
      continue;
    }
    if (fieldId == 'inspectorName') {
      infoBarInspector = element;
      continue;
    }

    children.add(element);
  }

  if (infoBarDate != null && infoBarInspector != null) {
    children.add(
      ReportElement(
        id: nextId(),
        type: ReportElementType.infoBar,
        toolType: 'infoBar',
        text: infoBarDate.text,
        secondaryText: infoBarInspector.text,
        backgroundColor: infoBarBackground ?? Colors.black,
        color: infoBarDate.color,
        fontSize: infoBarDate.fontSize,
        size: Size(regionWidth, infoBarHeight ?? 40),
      ),
    );
  }

  // Degenerate placeholder images (e.g. 1x1px) are backend artifacts with no
  // visual purpose — skip them rather than cluttering the editor.
  for (final m in RegExp(r'<img ([^>]*?)/>').allMatches(regionHtml)) {
    final attrs = m.group(1)!;
    final fieldId = _attr(attrs, 'data-field');
    if (fieldId == null) continue;
    final style = _parseStyleMap(_attr(attrs, 'style') ?? '');
    final w = _px(style, 'width');
    final h = _px(style, 'height');
    if (w < 4 || h < 4) continue;

    children.add(
      ReportElement(
        id: nextId(),
        type: ReportElementType.logo,
        toolType: fieldId,
        text: '',
        position: Offset(
          _attrPx(attrs, 'data-left') ?? _px(style, 'left'),
          _attrPx(attrs, 'data-top') ?? _px(style, 'top'),
        ),
        size: Size(w, h),
      ),
    );
  }

  return ReportElement(
    id: nextId(),
    type: regionType,
    text: '',
    backgroundColor: backgroundColor,
    size: Size(regionWidth, regionHeight),
    children: children,
  );
}

/// Serializes a header/footer container into a responsive flexbox fragment —
/// or an empty string if there's no region at all (nothing to save for that
/// side).
///
/// Instead of pixel-absolute positions, the region root is a full-width flex
/// column: one row split into left / center / right zones (each stacking its
/// own elements top-to-bottom), plus the info bar docked at the bottom via
/// `margin-top:auto`. Elements are assigned to a zone from where they sit in
/// the editor ([pageWidth] thirds, or their text alignment), so long dynamic
/// values can use the whole zone's share of the real rendered width, wrap
/// only when genuinely out of room, and can never overlap a neighbor.
///
/// The editor's exact pixel geometry is preserved in `data-left`/`data-top`
/// attributes so [parseRegionHtml] can restore the free-form layout when the
/// template is reopened.
String buildRegionHtml(ReportElement? region, {required double pageWidth}) {
  if (region == null) return '';

  ReportElement? infoBar;
  final leftZone = <ReportElement>[];
  final centerZone = <ReportElement>[];
  final rightZone = <ReportElement>[];

  for (final child in region.children) {
    if (child.type == ReportElementType.infoBar) {
      infoBar = child;
      continue;
    }
    if (child.type == ReportElementType.text && child.align == TextAlign.center) {
      centerZone.add(child);
    } else if (child.type == ReportElementType.text && child.align == TextAlign.right) {
      rightZone.add(child);
    } else {
      final cx = child.position.dx + (child.size.width > 0 ? child.size.width / 2 : 0);
      (cx < pageWidth / 3
              ? leftZone
              : cx > pageWidth * 2 / 3
                  ? rightZone
                  : centerZone)
          .add(child);
    }
  }
  for (final zone in [leftZone, centerZone, rightZone]) {
    zone.sort((a, b) => a.position.dy.compareTo(b.position.dy));
  }

  final bg = region.backgroundColor != Colors.transparent ? 'background-color:${_colorToHex(region.backgroundColor)};' : '';
  final buffer = StringBuffer()
    ..write('<div data-width="${_fmt(pageWidth)}" '
        'style="position:relative;display:flex;flex-direction:column;'
        'width:100%;max-width:100%;height:${_fmt(region.size.height)}px;'
        '${bg}overflow:hidden;box-sizing:border-box">');

  int autoFieldCounter = 1;
  String fieldIdOf(ReportElement child) => child.toolType ?? 'field-${autoFieldCounter++}';

  String itemTag(ReportElement child) {
    if (child.type == ReportElementType.logo) {
      return '<img data-field="${fieldIdOf(child)}" '
          'data-left="${_fmt(child.position.dx)}" data-top="${_fmt(child.position.dy)}" alt="" '
          'style="width:${_fmt(child.size.width)}px;height:${_fmt(child.size.height)}px;'
          'max-width:100%;object-fit:contain" />';
    }
    return _spanTag(
      fieldIdOf(child),
      child,
      child.text,
      align: child.align,
      position: child.position,
      authoredWidth: child.size.width > 0 ? child.size.width : null,
    );
  }

  String zoneTag(List<ReportElement> zone, String alignItems, String textAlign) {
    final items = zone.map(itemTag).join();
    return '<div style="display:flex;flex-direction:column;flex:1 1 0;min-width:0;'
        'gap:4px;align-items:$alignItems;text-align:$textAlign">$items</div>';
  }

  buffer
    ..write('<div style="display:flex;justify-content:space-between;align-items:flex-start;'
        'flex:1;min-width:0;gap:16px;padding:8px 16px;box-sizing:border-box">')
    ..write(zoneTag(leftZone, 'flex-start', 'left'))
    ..write(zoneTag(centerZone, 'center', 'center'))
    ..write(zoneTag(rightZone, 'flex-end', 'right'))
    ..write('</div>');

  if (infoBar != null) {
    final barHeight = infoBar.size.height > 0 ? infoBar.size.height : 40.0;
    final barBg = infoBar.backgroundColor != Colors.transparent ? 'background-color:${_colorToHex(infoBar.backgroundColor)};' : '';
    buffer
      ..write('<div data-region="infobar" style="display:flex;justify-content:space-between;'
          'align-items:center;gap:16px;margin-top:auto;width:100%;'
          'height:${_fmt(barHeight)}px;padding:0 16px;box-sizing:border-box;$barBg">')
      ..write(_spanTag('reportDate', infoBar, infoBar.text, align: TextAlign.left))
      ..write(_spanTag('inspectorName', infoBar, infoBar.secondaryText, align: TextAlign.right))
      ..write('</div>');
  }

  buffer.write('</div>');
  return buffer.toString();
}

/// Emits one flow-layout (not absolutely positioned) text span. The span
/// wraps (`pre-wrap` + `break-word`) and is capped at its zone's width via
/// `max-width:100%`, so a long dynamic value first uses all the room its
/// flex zone has, then grows downward — it can't run over a neighbor.
/// [position] and [authoredWidth], when given, are stored as
/// `data-left`/`data-top`/`data-width` purely for the editor round-trip;
/// they have no effect on the rendered layout.
String _spanTag(String fieldId, ReportElement style, String text, {required TextAlign align, Offset? position, double? authoredWidth}) {
  final fontSize = style.fontSize;
  final posAttrs = (position != null ? ' data-left="${_fmt(position.dx)}" data-top="${_fmt(position.dy)}"' : '') +
      (authoredWidth != null ? ' data-width="${_fmt(authoredWidth)}"' : '');
  return '<span data-field="$fieldId"$posAttrs style="'
      'font-family:Arial, Helvetica, sans-serif;font-size:${_fmt(fontSize)}px;'
      'font-weight:${style.isBold ? 'bold' : 'normal'};font-style:${style.isItalic ? 'italic' : 'normal'};'
      'color:${_colorToHex(style.color)};letter-spacing:0.00px;text-align:${_alignToCss(align)};'
      'line-height:${_fmt(fontSize * 1.2)}px;white-space:pre-wrap;overflow-wrap:break-word;'
      'word-break:break-word;max-width:100%;box-sizing:border-box">${_escapeHtml(text)}</span>';
}

String _alignToCss(TextAlign align) {
  switch (align) {
    case TextAlign.center:
      return 'center';
    case TextAlign.right:
      return 'right';
    case TextAlign.justify:
      return 'justify';
    default:
      return 'left';
  }
}

TextAlign _parseAlign(String? css) {
  switch (css?.trim()) {
    case 'center':
      return TextAlign.center;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    default:
      return TextAlign.left;
  }
}

String _friendlyLabel(String fieldId) {
  final withSpaces = fieldId.replaceAll('-', ' ').replaceAll('_', ' ').trim();
  if (withSpaces.isEmpty) return 'Text';
  return withSpaces.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// Reads one `name="value"` attribute out of a raw attribute string, or
/// `null` if absent.
String? _attr(String attrs, String name) => RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);

/// Reads a numeric `data-*` attribute (the codec's round-trip geometry), or
/// `null` if absent/unparseable so callers can fall back to inline style.
double? _attrPx(String attrs, String name) {
  final raw = _attr(attrs, name);
  return raw == null ? null : double.tryParse(raw);
}

Map<String, String> _parseStyleMap(String style) {
  final map = <String, String>{};
  for (final part in style.split(';')) {
    final idx = part.indexOf(':');
    if (idx == -1) continue;
    final key = part.substring(0, idx).trim();
    final value = part.substring(idx + 1).trim();
    if (key.isNotEmpty) map[key] = value;
  }
  return map;
}

double _px(Map<String, String> style, String key, [double fallback = 0]) {
  final raw = style[key];
  if (raw == null) return fallback;
  final match = RegExp(r'([\d.]+)').firstMatch(raw);
  return match != null ? double.tryParse(match.group(1)!) ?? fallback : fallback;
}

Color _parseColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  final cleaned = hex.trim().replaceAll('#', '');
  if (cleaned.length != 6) return fallback;
  final value = int.tryParse('FF$cleaned', radix: 16);
  return value != null ? Color(value) : fallback;
}

String _fmt(double value) => value.toStringAsFixed(2);

String _colorToHex(Color color) {
  final r = (color.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (color.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (color.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

String _escapeHtml(String text) {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}
