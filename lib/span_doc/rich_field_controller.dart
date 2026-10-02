import 'package:flutter/material.dart';

import 'fill_values.dart';

/// Formats the report editor can set on a stretch of text.
enum RichFormat { bold, italic, underline, strike }

/// List prefixes the editor writes at the start of lines. They are plain
/// characters in the Word file too (fill_template.py keeps text as is).
const String bulletPrefix = '• ';
final RegExp _numberPrefix = RegExp(r'^(\d+)\.\s');

class _Fmt {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  const _Fmt({this.bold = false, this.italic = false, this.underline = false, this.strike = false});

  static const plain = _Fmt();

  bool get(RichFormat f) => switch (f) {
        RichFormat.bold => bold,
        RichFormat.italic => italic,
        RichFormat.underline => underline,
        RichFormat.strike => strike,
      };

  _Fmt with_(RichFormat f, bool on) => _Fmt(
        bold: f == RichFormat.bold ? on : bold,
        italic: f == RichFormat.italic ? on : italic,
        underline: f == RichFormat.underline ? on : underline,
        strike: f == RichFormat.strike ? on : strike,
      );

  bool same(_Fmt o) => bold == o.bold && italic == o.italic && underline == o.underline && strike == o.strike;
}

/// A text field controller that keeps bold / italic / underline / strike per
/// character, so a report field can be formatted in place and saved as
/// formatted runs (see [valueWithRuns]).
class RichFieldController extends TextEditingController {
  List<_Fmt> _formats;

  /// Format for the next typed character when nothing is selected.
  _Fmt? _pending;

  RichFieldController(List<FillRun> runs)
      : _formats = [
          for (final run in runs)
            for (var i = 0; i < run.text.length; i++)
              _Fmt(bold: run.bold, italic: run.italic, underline: run.underline, strike: run.strike),
        ],
        super(text: runs.map((r) => r.text).join());

  /// The text as runs of equal formatting.
  List<FillRun> get runs {
    final out = <FillRun>[];
    final t = text;
    var start = 0;
    for (var i = 1; i <= t.length; i++) {
      if (i == t.length || !_formats[i].same(_formats[start])) {
        final f = _formats[start];
        out.add(FillRun(t.substring(start, i), bold: f.bold, italic: f.italic, underline: f.underline, strike: f.strike));
        start = i;
      }
    }
    return out;
  }

  @override
  set value(TextEditingValue newValue) {
    final old = text;
    final next = newValue.text;
    if (old != next) {
      var prefix = 0;
      while (prefix < old.length && prefix < next.length && old[prefix] == next[prefix]) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < old.length - prefix && suffix < next.length - prefix && old[old.length - 1 - suffix] == next[next.length - 1 - suffix]) {
        suffix++;
      }
      final inserted = next.length - prefix - suffix;
      final typing = _pending ?? (prefix > 0 && prefix - 1 < _formats.length ? _formats[prefix - 1] : (_formats.isNotEmpty ? _formats.first : _Fmt.plain));
      _formats = [
        ..._formats.sublist(0, prefix.clamp(0, _formats.length)),
        for (var i = 0; i < inserted; i++) typing,
        ..._formats.sublist((old.length - suffix).clamp(0, _formats.length)),
      ];
      _pending = null;

      // Enter on a list line continues the list.
      if (inserted == 1 && next[prefix] == '\n') {
        final lineStart = old.lastIndexOf('\n', prefix - 1) + 1;
        final line = old.substring(lineStart, prefix);
        String? carry;
        if (line.startsWith(bulletPrefix) && line.trim() != bulletPrefix.trim()) {
          carry = bulletPrefix;
        } else {
          final m = _numberPrefix.firstMatch(line);
          if (m != null) carry = '${int.parse(m.group(1)!) + 1}. ';
        }
        if (carry != null) {
          final at = prefix + 1;
          final withCarry = next.substring(0, at) + carry + next.substring(at);
          _formats.insertAll(at, List.filled(carry.length, typing));
          super.value = TextEditingValue(text: withCarry, selection: TextSelection.collapsed(offset: at + carry.length));
          return;
        }
      }
    } else if (newValue.selection != selection) {
      _pending = null;
    }
    super.value = newValue;
  }

  /// Whether the selection (or the typing position) has [format].
  bool isActive(RichFormat format) {
    final sel = selection;
    if (!sel.isValid) return false;
    if (sel.isCollapsed) {
      if (_pending != null) return _pending!.get(format);
      final at = sel.start - 1;
      return at >= 0 && at < _formats.length && _formats[at].get(format);
    }
    for (var i = sel.start; i < sel.end && i < _formats.length; i++) {
      if (!_formats[i].get(format)) return false;
    }
    return true;
  }

  /// Turn [format] on for the selection (off when all of it has it already);
  /// with no selection, for the next typed text.
  void toggle(RichFormat format) {
    final sel = selection;
    if (!sel.isValid) return;
    final on = !isActive(format);
    if (sel.isCollapsed) {
      final at = sel.start - 1;
      final base = _pending ?? (at >= 0 && at < _formats.length ? _formats[at] : _Fmt.plain);
      _pending = base.with_(format, on);
    } else {
      for (var i = sel.start; i < sel.end && i < _formats.length; i++) {
        _formats[i] = _formats[i].with_(format, on);
      }
    }
    notifyListeners();
  }

  /// Remove every format from the selection.
  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid) return;
    if (sel.isCollapsed) {
      _pending = _Fmt.plain;
    } else {
      for (var i = sel.start; i < sel.end && i < _formats.length; i++) {
        _formats[i] = _Fmt.plain;
      }
    }
    notifyListeners();
  }

  bool get isBulleted => _selectedLines().every((l) => text.startsWith(bulletPrefix, l));

  bool get isNumbered => _selectedLines().every((l) => _numberPrefix.hasMatch(text.substring(l)));

  /// Bullet the selected lines (or take the bullets off).
  void toggleBullets() => _setList(isBulleted ? null : 'bullet');

  /// Number the selected lines (or take the numbers off).
  void toggleNumbers() => _setList(isNumbered ? null : 'number');

  List<int> _selectedLines() {
    final t = text;
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: t.length);
    final before = sel.start - 1;
    final starts = <int>[before < 0 ? 0 : t.lastIndexOf('\n', before.clamp(0, t.length)) + 1];
    for (var i = sel.start; i < sel.end && i < t.length; i++) {
      if (t[i] == '\n' && i + 1 <= t.length) starts.add(i + 1);
    }
    return starts;
  }

  void _setList(String? kind) {
    final lines = _selectedLines();
    var t = text;
    var formats = [..._formats];
    var shift = 0;
    var n = 1;
    for (final rawStart in lines) {
      final start = rawStart + shift;
      // Remove an existing prefix.
      var existing = 0;
      if (t.startsWith(bulletPrefix, start)) {
        existing = bulletPrefix.length;
      } else {
        final m = _numberPrefix.firstMatch(t.substring(start));
        if (m != null) existing = m.group(0)!.length;
      }
      final prefix = switch (kind) {
        'bullet' => bulletPrefix,
        'number' => '${n++}. ',
        _ => '',
      };
      final fmt = start < formats.length ? formats[start] : _Fmt.plain;
      t = t.substring(0, start) + prefix + t.substring(start + existing);
      formats = [...formats.sublist(0, start), for (var i = 0; i < prefix.length; i++) fmt, ...formats.sublist(start + existing)];
      shift += prefix.length - existing;
    }
    _formats = formats;
    super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: (selection.end + shift).clamp(0, t.length)));
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final t = text;
    if (t.isEmpty || _formats.length != t.length) return TextSpan(text: t, style: style);
    final children = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= t.length; i++) {
      if (i == t.length || !_formats[i].same(_formats[start])) {
        final f = _formats[start];
        children.add(TextSpan(
          text: t.substring(start, i),
          style: TextStyle(
            fontWeight: f.bold ? FontWeight.w700 : null,
            fontStyle: f.italic ? FontStyle.italic : null,
            decoration: f.underline || f.strike
                ? TextDecoration.combine([
                    if (f.underline) TextDecoration.underline,
                    if (f.strike) TextDecoration.lineThrough,
                  ])
                : null,
          ),
        ));
        start = i;
      }
    }
    return TextSpan(style: style, children: children);
  }
}
