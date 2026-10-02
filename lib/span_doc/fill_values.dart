import 'dart:convert';

import 'docx_model.dart' show FillPath;

/// Reading and writing a report's fill map (the `{{TOKEN}}` -> value JSON the
/// agent writes and fill_template.py fills the Word template from).
///
/// Text values come in three shapes, all understood by fill_template.py:
/// - `"text"` (a plain string; `\n` is a line break)
/// - `{"text": "...", "max_chars": 18}` (a fixed-width box)
/// - `{"runs": [{"text": "...", "bold": true}, ...]}` (formatted in the app;
///   may also carry `max_chars`)

dynamic fillGet(dynamic root, FillPath path) {
  dynamic node = root;
  for (final key in path) {
    if (key is int && node is List && key >= 0 && key < node.length) {
      node = node[key];
    } else if (key is String && node is Map) {
      node = node[key];
    } else {
      return null;
    }
  }
  return node;
}

/// Set the value at [path], creating maps along the way when a key is missing.
void fillSet(dynamic root, FillPath path, dynamic value) {
  if (path.isEmpty) return;
  dynamic node = root;
  for (var i = 0; i < path.length - 1; i++) {
    final key = path[i];
    dynamic next;
    if (key is int && node is List && key >= 0 && key < node.length) {
      next = node[key];
    } else if (key is String && node is Map) {
      next = node[key];
      if (next == null) {
        next = <String, dynamic>{};
        node[key] = next;
      }
    } else {
      return;
    }
    node = next;
  }
  final last = path.last;
  if (last is int && node is List && last >= 0 && last < node.length) {
    node[last] = value;
  } else if (last is String && node is Map) {
    node[last] = value;
  }
}

Map<String, dynamic> copyFillMap(Map<String, dynamic> map) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(map)) as Map);

bool fillMapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);

/// One stretch of text with the formatting the app can set.
class FillRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  const FillRun(this.text, {this.bold = false, this.italic = false, this.underline = false, this.strike = false});

  bool get plain => !bold && !italic && !underline && !strike;

  bool sameFormat(FillRun other) =>
      bold == other.bold && italic == other.italic && underline == other.underline && strike == other.strike;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (strike) 'strike': true,
      };
}

bool isRichValue(dynamic value) => value is Map && value['runs'] is List;

/// The value's text, whatever its shape.
String valueText(dynamic value) {
  if (value == null) return '';
  if (isRichValue(value)) {
    return (value['runs'] as List).map((r) => r is Map ? (r['text'] ?? '').toString() : '').join();
  }
  if (value is Map) return value.containsKey('text') ? (value['text'] ?? '').toString() : '';
  if (value is List) return value.map(valueText).join('\n');
  return value.toString();
}

/// The value as formatted runs (a plain value is one unformatted run).
List<FillRun> valueRuns(dynamic value) {
  if (isRichValue(value)) {
    return [
      for (final r in value['runs'] as List)
        if (r is Map && (r['text'] ?? '').toString().isNotEmpty)
          FillRun(
            r['text'].toString(),
            bold: r['bold'] == true,
            italic: r['italic'] == true,
            underline: r['underline'] == true,
            strike: r['strike'] == true,
          ),
    ];
  }
  final text = valueText(value);
  return text.isEmpty ? const [] : [FillRun(text)];
}

int? maxChars(dynamic value) => value is Map && value['max_chars'] is num ? (value['max_chars'] as num).toInt() : null;

/// A new value with [runs] in place of [old]'s text: a plain string when
/// nothing is formatted, else `{"runs": [...]}`; a fixed-width box keeps its
/// `max_chars`.
dynamic valueWithRuns(dynamic old, List<FillRun> runs) {
  final merged = <FillRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    if (merged.isNotEmpty && merged.last.sameFormat(run)) {
      final last = merged.removeLast();
      merged.add(FillRun(last.text + run.text, bold: last.bold, italic: last.italic, underline: last.underline, strike: last.strike));
    } else {
      merged.add(run);
    }
  }
  final width = maxChars(old);
  final text = merged.map((r) => r.text).join();
  if (merged.every((r) => r.plain)) {
    return width != null ? {'text': text, 'max_chars': width} : text;
  }
  return {
    'runs': [for (final r in merged) r.toJson()],
    'max_chars': ?width,
  };
}

/// Every photo path a fill map uses (image slots, photo blocks, image lists).
List<String> photoPathsIn(dynamic value) {
  final out = <String>[];
  void visit(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if ((entry.key == 'image' || entry.key == 'path') && entry.value is String && (entry.value as String).isNotEmpty) {
          out.add(entry.value as String);
        } else {
          visit(entry.value);
        }
      }
    } else if (node is List) {
      node.forEach(visit);
    }
  }

  visit(value);
  return out;
}
