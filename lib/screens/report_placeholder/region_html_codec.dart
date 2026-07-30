import 'package:flutter/material.dart';
import 'models/report_element.dart';

// Converts between the report template API's `header_html`/`footer_html`
// fields (pixel-precise `position: absolute` fragments, e.g.
// `<div style="..."><span data-field="...">...</span></div>`, no class
// attributes — every visual property is inline style) and this editor's
// [ReportElement] model. These two functions are inverses of each other:
// [parseRegionHtml] loads a fetched region into editable elements,
// [buildRegionHtml] turns the edited elements back into the same markup
// shape for saving.
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

  final rootMatch = RegExp(r'^\s*<div style="([^"]*)"').firstMatch(regionHtml);
  final rootStyle = rootMatch != null ? _parseStyleMap(rootMatch.group(1)!) : <String, String>{};
  final regionWidth = _px(rootStyle, 'width', 595.28);
  final regionHeight = _px(rootStyle, 'height', 117.86);

  Color backgroundColor = Colors.white;
  double bestArea = 0;
  Color? infoBarBackground;
  double? infoBarHeight;
  for (final m in RegExp(r'<div style="([^"]*)"></div>').allMatches(regionHtml)) {
    final style = _parseStyleMap(m.group(1)!);
    final top = _px(style, 'top');
    final h = _px(style, 'height');
    final area = _px(style, 'width') * h;
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

  for (final m in RegExp(r'<span data-field="([^"]*)" style="([^"]*)">(.*?)</span>', dotAll: true).allMatches(regionHtml)) {
    final fieldId = m.group(1)!;
    final style = _parseStyleMap(m.group(2)!);
    final rawText = (m.group(3) ?? '').trim();
    final displayText = (rawText.isEmpty || rawText == '{{placeholder}}') ? _friendlyLabel(fieldId) : rawText;

    final align = _parseAlign(style['text-align']);

    // Left-aligned text elements are never given an explicit size anywhere
    // in this editor (they always auto-size to their content — see
    // ReportElement's Size.zero default), so importing one here would force
    // a fixed-size Container on reload instead of letting the text size
    // itself, clipping/wrapping content that fit fine before saving. Center/
    // right-aligned text is the one exception: those rely on a full-width
    // box for the alignment to have anything to align within (see e.g. the
    // header "Centered" style's companyName/address, created with
    // `size: Size(_pageWidth, 0)`) — dropping that box on reload collapses
    // them back to left-aligned at x:0.
    final element = ReportElement(
      id: nextId(),
      type: ReportElementType.text,
      toolType: fieldId,
      text: displayText,
      position: Offset(_px(style, 'left'), _px(style, 'top')),
      size: align == TextAlign.left ? null : Size(regionWidth, 0),
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
  for (final m in RegExp(r'<img data-field="([^"]*)"[^>]*style="([^"]*)"[^>]*/>').allMatches(regionHtml)) {
    final fieldId = m.group(1)!;
    final style = _parseStyleMap(m.group(2)!);
    final w = _px(style, 'width');
    final h = _px(style, 'height');
    if (w < 4 || h < 4) continue;

    children.add(
      ReportElement(
        id: nextId(),
        type: ReportElementType.logo,
        toolType: fieldId,
        text: '',
        position: Offset(_px(style, 'left'), _px(style, 'top')),
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

/// Serializes a header/footer container back into the same `pdf-*-region`
/// markup shape the API returned — or an empty string if there's no region at
/// all (nothing to save for that side).
///
/// [pageWidth] must be the editor's real page width (e.g. 816), not
/// `region.size.width` — the header/footer widgets always render at the
/// page's full width and never actually populate that field (it stays 0),
/// so reading it here would silently export a zero-width, invisible region.
String buildRegionHtml(ReportElement? region, {required double pageWidth}) {
  if (region == null) return '';

  final buffer = StringBuffer()
    ..write('<div style="position:relative;width:${_fmt(pageWidth)}px;'
        'height:${_fmt(region.size.height)}px;overflow:hidden;box-sizing:border-box">');

  if (region.backgroundColor != Colors.transparent) {
    buffer.write(
      '<div style="position:absolute;left:0.00px;top:0.00px;'
      'width:${_fmt(pageWidth)}px;height:${_fmt(region.size.height)}px;'
      'background-color:${_colorToHex(region.backgroundColor)};z-index:0"></div>',
    );
  }

  int autoFieldCounter = 1;
  for (final child in region.children) {
    if (child.type == ReportElementType.infoBar) {
      final barHeight = child.size.height > 0 ? child.size.height : 40.0;
      final barTop = region.size.height - barHeight;
      final half = ((pageWidth - 32) / 2).clamp(60.0, 400.0);
      final textTop = barTop + ((barHeight - child.fontSize * 1.2) / 2).clamp(0.0, barHeight);

      if (child.backgroundColor != Colors.transparent) {
        buffer.write(
          '<div style="position:absolute;left:0.00px;top:${_fmt(barTop)}px;'
          'width:${_fmt(pageWidth)}px;height:${_fmt(barHeight)}px;'
          'background-color:${_colorToHex(child.backgroundColor)};z-index:1"></div>',
        );
      }
      buffer.write(
        _spanTag(
          'reportDate',
          Offset(16, textTop),
          Size(half, child.fontSize + 4),
          child,
          child.text,
          align: TextAlign.left,
        ),
      );
      buffer.write(
        _spanTag(
          'inspectorName',
          Offset(pageWidth - half - 16, textTop),
          Size(half, child.fontSize + 4),
          child,
          child.secondaryText,
          align: TextAlign.right,
        ),
      );
      continue;
    }

    final fieldId = child.toolType ?? 'field-${autoFieldCounter++}';
    if (child.type == ReportElementType.logo) {
      buffer.write(
        '<img data-field="$fieldId" alt="" style="position:absolute;'
        'left:${_fmt(child.position.dx)}px;top:${_fmt(child.position.dy)}px;'
        'width:${_fmt(child.size.width)}px;height:${_fmt(child.size.height)}px;'
        'object-fit:contain;z-index:1" />',
      );
    } else {
      buffer.write(_spanTag(fieldId, child.position, child.size, child, child.text, align: child.align));
    }
  }

  buffer.write('</div>');
  return buffer.toString();
}

String _spanTag(String fieldId, Offset position, Size size, ReportElement style, String text, {required TextAlign align}) {
  final width = size.width > 0 ? size.width : 200.0;
  final fontSize = style.fontSize;
  return '<span data-field="$fieldId" style="position:absolute;'
      'left:${_fmt(position.dx)}px;top:${_fmt(position.dy)}px;'
      'width:${_fmt(width)}px;min-height:${_fmt(fontSize)}px;'
      'font-family:Arial, Helvetica, sans-serif;font-size:${_fmt(fontSize)}px;'
      'font-weight:${style.isBold ? 'bold' : 'normal'};font-style:${style.isItalic ? 'italic' : 'normal'};'
      'color:${_colorToHex(style.color)};letter-spacing:0.00px;text-align:${_alignToCss(align)};'
      'line-height:${_fmt(fontSize * 1.2)}px;white-space:pre;z-index:2">${_escapeHtml(text)}</span>';
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
