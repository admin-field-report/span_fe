import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../report_generation_api.dart';

/// Loads a photo the report uses (a path from the fill map).
typedef ReportPhotoLoader = Future<Uint8List> Function(String path);

/// Lets the user pick and upload a photo; returns its fill-map path, or null.
typedef ReportPhotoPicker = Future<String?> Function();

/// A location in the fill map: String keys and int list indexes.
typedef FillPath = List<Object>;

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

void fillSet(dynamic root, FillPath path, dynamic value) {
  final parent = fillGet(root, path.sublist(0, path.length - 1));
  final key = path.last;
  if (key is int && parent is List && key >= 0 && key < parent.length) {
    parent[key] = value;
  } else if (key is String && parent is Map) {
    parent[key] = value;
  }
}

/// Deep copy of a JSON-shaped fill map.
Map<String, dynamic> copyFillMap(Map<String, dynamic> map) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(map)) as Map);

bool fillMapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);

String _bare(String token) => token.replaceAll(RegExp(r'[{}]'), '').replaceFirst(RegExp(r'^BLOCK:'), '');

/// "{{SITE_VISIT_DATE}}" -> "Site visit date".
String humanizeToken(String token) {
  final words = _bare(token)
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => switch (w) {
            'n' => 'no.',
            'no' => 'no.',
            'nos' => 'nos.',
            'addr' => 'address',
            'qty' => 'quantity',
            'temp' => 'temperature',
            _ => w,
          })
      .toList();
  if (words.isEmpty) return _bare(token);
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}

// -----------------------------------------------------------------------------
// Document look: always a white page, whatever the app theme.
// -----------------------------------------------------------------------------

class _Doc {
  static const ink = Color(0xFF1F2328);
  static const muted = Color(0xFF687080);
  static const faint = Color(0xFFA3AAB5);
  static const rule = Color(0xFFE4E7EB);
  static const accent = Color(0xFF2F6FEB);
  static const hover = Color(0x0F2F6FEB);
  static const editFill = Color(0xFFF4F8FF);
  static const editBorder = Color(0xFF9DBBF3);

  static TextStyle body({double size = 13.5, FontWeight weight = FontWeight.w400, Color color = ink, FontStyle? style}) =>
      GoogleFonts.arimo(fontSize: size, height: 1.55, fontWeight: weight, color: color, fontStyle: style);

  static TextStyle label() =>
      GoogleFonts.arimo(fontSize: 11, height: 1.4, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.2);

  static TextStyle heading() =>
      GoogleFonts.arimo(fontSize: 12, height: 1.4, fontWeight: FontWeight.w700, color: ink, letterSpacing: 1.1);
}

final RegExp _hiddenToken = RegExp(r'PAGE_LABEL|KEEP_WITH_NEXT');
final RegExp _narrativeToken = RegExp(
  r'DESCRIPTION|SUMMARY|NARRATIVE|OBSERVATION|CONCLUSION|RECOMMENDATION|TEXT|NOTES|ACTIVIT|PURPOSE|SCOPE|COMMENT|REMARK|FINDING|ACTION|CAPTION|LIST',
);
final RegExp _indexToken = RegExp(r'(INDEX|NUMBER|_NO|^N)$');
final RegExp _nameToken = RegExp(r'(_NAME|_TITLE)$');

String _asText(dynamic value) {
  if (value == null) return '';
  if (value is Map && value.containsKey('text')) return _asText(value['text']);
  return value.toString();
}

bool _isTextValue(dynamic value) =>
    value == null || value is String || value is num || (value is Map && value.containsKey('text'));

bool _isImageValue(dynamic value) => value is Map && value.containsKey('image');

bool _isImagesValue(dynamic value) => value is Map && value['images'] is List;

bool _isRowList(dynamic value) => value is List && value.every((e) => e is String || e is num);

bool _isBlock(String token, dynamic value) =>
    token.startsWith('{{BLOCK:') && value is List && value.every((e) => e is Map);

FillPath _textPath(FillPath base, dynamic value) =>
    value is Map && value.containsKey('text') ? [...base, 'text'] : base;

// -----------------------------------------------------------------------------
// Editor
// -----------------------------------------------------------------------------

/// A generated report shown as a clean, editable document: the report's
/// sections in template order, each value editable in place (text, repeated
/// rows and blocks, photos and captions). Fields the inspection didn't answer
/// read as a faint "Add ..." the user can click to fill.
///
/// Edits change [fillMap] in place (the parent's working copy) and call
/// [onChanged]; saving is the parent's job.
class ReportDocumentEditor extends StatefulWidget {
  final ReportFillDocument document;
  final Map<String, dynamic> fillMap;
  final String title;
  final VoidCallback onChanged;
  final ReportPhotoLoader loadPhoto;
  final ReportPhotoPicker? pickPhoto;

  /// Open this field for editing on load and scroll to it (local preview).
  final FillPath? initialEditing;

  const ReportDocumentEditor({
    super.key,
    required this.document,
    required this.fillMap,
    required this.title,
    required this.onChanged,
    required this.loadPhoto,
    this.pickPhoto,
    this.initialEditing,
  });

  @override
  State<ReportDocumentEditor> createState() => _ReportDocumentEditorState();
}

class _SectionView {
  final String? heading;
  final List<String> tokens;

  _SectionView(this.heading, this.tokens);
}

class _ReportDocumentEditorState extends State<ReportDocumentEditor> {
  final Map<String, Future<Uint8List>> _photos = {};
  final GlobalKey _initialKey = GlobalKey();

  Map<String, dynamic> get _map => widget.fillMap;

  @override
  void initState() {
    super.initState();
    if (widget.initialEditing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _initialKey.currentContext;
        if (context != null) Scrollable.ensureVisible(context, alignment: 0.35);
      });
    }
  }

  Future<Uint8List> _photo(String path) => _photos.putIfAbsent(path, () => widget.loadPhoto(path));

  void _set(FillPath path, dynamic value) {
    setState(() => fillSet(_map, path, value));
    widget.onChanged();
  }

  void _mutate(VoidCallback change) {
    setState(change);
    widget.onChanged();
  }

  String _label(String token) =>
      (widget.document.labels[token] ?? humanizeToken(token)).replaceAll(': (', ' (').trim();

  String? _question(String token) {
    for (final blank in widget.document.blanks) {
      if (blank.token == token) return blank.question;
    }
    return null;
  }

  bool _isInitial(FillPath path) {
    final target = widget.initialEditing;
    if (target == null || target.length != path.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (target[i] != path[i]) return false;
    }
    return true;
  }

  bool _visible(String token) {
    if (_hiddenToken.hasMatch(token)) return false;
    final value = _map[token];
    if (_isBlock(token, value)) {
      final items = (value as List).cast<Map>();
      return items.any((item) => item.keys.any((k) => !_hiddenToken.hasMatch(k.toString())));
    }
    return true;
  }

  String? _sectionHeading(ReportFillSection section) {
    final heading = section.heading?.trim().replaceAll(RegExp(r':$'), '').replaceAll(RegExp(r'\s*\([^)]*\)$'), '');
    if (heading != null && heading.isNotEmpty && !heading.contains(' / ') && !heading.contains('<') && heading.length <= 48) {
      return heading;
    }
    final id = section.id.replaceAll(RegExp(r'_page(_\d+)?$'), '').replaceAll(RegExp(r'_\d+$'), '');
    return id.isEmpty ? null : humanizeToken(id.toUpperCase());
  }

  /// Fill-map keys grouped under the template's sections, in report order.
  List<_SectionView> _sections() {
    final sections = widget.document.sections;
    final sectionOf = <String, int>{};
    for (var i = 0; i < sections.length; i++) {
      for (final token in sections[i].tokens) {
        sectionOf.putIfAbsent(token, () => i);
      }
    }
    final grouped = <int, List<String>>{};
    var current = -1;
    for (final token in _map.keys) {
      if (!_visible(token)) continue;
      final index = sectionOf[token] ?? current;
      current = index;
      grouped.putIfAbsent(index, () => []).add(token);
    }
    final out = <_SectionView>[];
    String? previous;
    for (final index in grouped.keys.toList()..sort()) {
      var heading = index < 0 ? null : _sectionHeading(sections[index]);
      if (heading != null && heading.toLowerCase() == previous?.toLowerCase()) heading = null;
      if (heading != null) previous = heading;
      out.add(_SectionView(heading, grouped[index]!));
    }
    return out;
  }

  String get _cleanTitle {
    final raw = widget.document.title ?? widget.title;
    return raw.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return Container(
      constraints: const BoxConstraints(maxWidth: 860),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(72, 64, 72, 80),
      child: DefaultTextStyle(
        style: _Doc.body(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_cleanTitle, style: _Doc.body(size: 22, weight: FontWeight.w700)),
            const SizedBox(height: 18),
            const Divider(height: 1, thickness: 1.2, color: _Doc.ink),
            for (final section in sections) ..._buildSection(section),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSection(_SectionView section) {
    final children = <Widget>[];
    final tokens = section.tokens;
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      final value = _map[token];
      if (_isRowList(value)) {
        final group = [token];
        while (i + group.length < tokens.length) {
          final next = tokens[i + group.length];
          final nextValue = _map[next];
          if (_isRowList(nextValue) && (nextValue as List).length == (value as List).length) {
            group.add(next);
          } else {
            break;
          }
        }
        children.add(_rowTable(group));
        i += group.length;
      } else if (_isBlock(token, value)) {
        children.add(_block(token));
        i++;
      } else if (_isImagesValue(value)) {
        children.add(_imagesGrid(token));
        i++;
      } else if (_isImageValue(value)) {
        children.add(_imageSlot([token, 'image'], _label(token)));
        i++;
      } else if (_isTextValue(value) && !_isLong(token, value)) {
        final group = [token];
        while (i + group.length < tokens.length) {
          final next = tokens[i + group.length];
          final nextValue = _map[next];
          if (_isTextValue(nextValue) && !_isLong(next, nextValue)) {
            group.add(next);
          } else {
            break;
          }
        }
        children.add(_fieldGrid(group));
        i += group.length;
      } else if (_isTextValue(value)) {
        children.add(_paragraph(token));
        i++;
      } else {
        i++;
      }
    }
    if (children.isEmpty) return const [];
    return [
      const SizedBox(height: 30),
      if (section.heading != null) ...[
        Text(section.heading!.toUpperCase(), style: _Doc.heading()),
        const SizedBox(height: 8),
        const Divider(height: 1, color: _Doc.rule),
        const SizedBox(height: 14),
      ],
      for (var c = 0; c < children.length; c++) ...[
        if (c > 0) const SizedBox(height: 20),
        children[c],
      ],
    ];
  }

  bool _isLong(String token, dynamic value) {
    final text = _asText(value);
    if (text.length > 110) return true;
    return _narrativeToken.hasMatch(_bare(token)) && (text.length > 50 || text.isEmpty);
  }

  // --- Text ------------------------------------------------------------------

  Widget _text(FillPath path, {required String label, String? question, TextStyle? style, bool multiline = true}) {
    final initial = _isInitial(path);
    return InlineEditableText(
      key: initial ? _initialKey : ValueKey(path.join('/')),
      value: _asText(fillGet(_map, path)),
      placeholder: 'Add ${label.toLowerCase()}',
      tooltip: question,
      style: style ?? _Doc.body(),
      multiline: multiline,
      startEditing: initial,
      onChanged: (text) => _set(path, text),
    );
  }

  Widget _fieldGrid(List<String> tokens) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 520 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 28) / columns;
      return Wrap(
        spacing: 28,
        runSpacing: 14,
        children: [
          for (final token in tokens)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label(token), style: _Doc.label()),
                  const SizedBox(height: 2),
                  _text(_textPath([token], _map[token]), label: _label(token), question: _question(token)),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _paragraph(String token) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_label(token), style: _Doc.label()),
        const SizedBox(height: 4),
        _text(_textPath([token], _map[token]), label: _label(token), question: _question(token)),
      ],
    );
  }

  // --- Parallel rows ---------------------------------------------------------

  Widget _rowTable(List<String> tokens) {
    final rows = (_map[tokens.first] as List).length;
    final flexes = [
      for (final token in tokens)
        (((_map[token] as List).fold<int>(0, (sum, v) => sum + v.toString().length) / (rows == 0 ? 1 : rows)) / 12)
            .clamp(2, 8)
            .round(),
    ];
    Widget cell(Widget child, int flex) => Expanded(
          flex: flex,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: child),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _Doc.ink, width: 0.8))),
          child: Row(
            children: [
              for (var c = 0; c < tokens.length; c++) cell(Text(_label(tokens[c]), style: _Doc.label()), flexes[c]),
              const SizedBox(width: 28),
            ],
          ),
        ),
        for (var r = 0; r < rows; r++)
          _HoverRegion(
            builder: (hovering) => Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _Doc.rule))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < tokens.length; c++)
                    cell(
                      _text([tokens[c], r], label: _label(tokens[c]), question: _question(tokens[c]), multiline: true),
                      flexes[c],
                    ),
                  SizedBox(
                    width: 28,
                    child: hovering
                        ? _iconAction(Icons.close_rounded, 'Remove row', () {
                            _mutate(() {
                              for (final token in tokens) {
                                (_map[token] as List).removeAt(r);
                              }
                            });
                          })
                        : null,
                  ),
                ],
              ),
            ),
          ),
        _addAction('Add row', () {
          _mutate(() {
            for (final token in tokens) {
              (_map[token] as List).add('');
            }
          });
        }),
      ],
    );
  }

  // --- Repeated blocks -------------------------------------------------------

  List<String> _itemTokens(Map item) =>
      item.keys.map((k) => k.toString()).where((k) => !_hiddenToken.hasMatch(k)).toList();

  /// Image tokens of a block item paired with their caption token.
  List<(String image, String? caption)> _photoPairs(Map item) {
    final tokens = _itemTokens(item);
    final pairs = <(String, String?)>[];
    for (final token in tokens.where((t) => _isImageValue(item[t]))) {
      final number = RegExp(r'_(\d+)\}\}$').firstMatch(token)?.group(1);
      String? caption;
      for (final t in tokens) {
        if (!_bare(t).contains('CAPTION') || !_isTextValue(item[t])) continue;
        final captionNumber = RegExp(r'_(\d+)\}\}$').firstMatch(t)?.group(1);
        if (captionNumber == number) {
          caption = t;
          break;
        }
      }
      pairs.add((token, caption));
    }
    return pairs;
  }

  bool _isPhotoBlock(List<Map> items) {
    if (items.isEmpty) return false;
    for (final item in items) {
      final pairs = _photoPairs(item);
      if (pairs.isEmpty) return false;
      final used = {for (final p in pairs) p.$1, for (final p in pairs) ?p.$2};
      if (_itemTokens(item).any((t) => !used.contains(t))) return false;
    }
    return true;
  }

  dynamic _emptyLike(dynamic value) {
    if (value is String || value is num || value == null) return '';
    if (value is Map && value.containsKey('image')) return {...value, 'image': null};
    if (value is Map && value.containsKey('images')) return {...value, 'images': []};
    if (value is Map && value.containsKey('text')) return {...value, 'text': ''};
    if (value is List) return value.every((e) => e is String) ? <String>[] : [];
    return value;
  }

  Map<String, dynamic> _emptyItem(Map template, int number) {
    final out = <String, dynamic>{};
    template.forEach((key, value) {
      final token = key.toString();
      out[token] = _indexToken.hasMatch(_bare(token)) && _isTextValue(value) ? '$number' : _emptyLike(value);
    });
    return out;
  }

  Widget _block(String token) {
    final items = (_map[token] as List).cast<Map>();
    final label = humanizeToken(token);
    if (_isPhotoBlock(items)) return _photoBlock(token, items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 22),
          _blockItem(token, i, items[i], label, canRemove: items.length > 1),
        ],
        _addAction('Add ${label.toLowerCase()}', () {
          _mutate(() => (_map[token] as List).add(_emptyItem(items.isEmpty ? {} : items.last, items.length + 1)));
        }),
      ],
    );
  }

  Widget _blockItem(String block, int index, Map item, String label, {required bool canRemove}) {
    final tokens = _itemTokens(item);
    final indexToken = tokens.where((t) => _indexToken.hasMatch(_bare(t)) && _isTextValue(item[t])).firstOrNull;
    final nameToken = tokens
        .where((t) => _nameToken.hasMatch(_bare(t)) && _isTextValue(item[t]) && _asText(item[t]).length < 90)
        .firstOrNull;
    final photoPairs = _photoPairs(item);
    final photoTokens = {for (final p in photoPairs) p.$1, for (final p in photoPairs) ?p.$2};
    final rows = tokens.where((t) => t != indexToken && t != nameToken && !photoTokens.contains(t)).toList();

    return _HoverRegion(
      builder: (hovering) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _Doc.ink, width: 0.8))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('$label ', style: _Doc.body(weight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${indexToken != null && _asText(item[indexToken]).trim().isNotEmpty ? _asText(item[indexToken]).trim() : index + 1}${nameToken != null ? ':' : ''}',
                    style: _Doc.body(weight: FontWeight.w700),
                  ),
                ),
                if (nameToken != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _text(_textPath([block, index, nameToken], item[nameToken]),
                        label: _label(nameToken), style: _Doc.body(weight: FontWeight.w600), multiline: false),
                  ),
                ] else
                  const Spacer(),
                SizedBox(
                  width: 28,
                  child: hovering && canRemove
                      ? _iconAction(Icons.delete_outline_rounded, 'Remove ${label.toLowerCase()}', () {
                          _mutate(() => (_map[block] as List).removeAt(index));
                        })
                      : null,
                ),
              ],
            ),
          ),
          for (final token in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _Doc.rule))),
              child: _isImageValue(item[token])
                  ? _imageSlot([block, index, token, 'image'], _label(token))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, right: 12),
                            child: Text(_label(token), style: _Doc.label()),
                          ),
                        ),
                        Expanded(
                          child: _isTextValue(item[token])
                              ? _text(_textPath([block, index, token], item[token]),
                                  label: _label(token), question: _question(token))
                              : Text(_asText(item[token]), style: _Doc.body(color: _Doc.muted)),
                        ),
                      ],
                    ),
            ),
          if (photoPairs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _photoWrap([
              for (final pair in photoPairs)
                _PhotoSpec(
                  imagePath: [block, index, pair.$1, 'image'],
                  captionPath: pair.$2 == null ? null : _textPath([block, index, pair.$2!], item[pair.$2]),
                  onRemove: () => _mutate(() {
                    fillSet(_map, [block, index, pair.$1, 'image'], null);
                    if (pair.$2 != null) fillSet(_map, _textPath([block, index, pair.$2!], item[pair.$2]), '');
                  }),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  /// A block whose items are only photos + captions: one continuous photo grid.
  Widget _photoBlock(String block, List<Map> items) {
    final specs = <_PhotoSpec>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final pairs = _photoPairs(item);
      for (final pair in pairs) {
        if (fillGet(item, [pair.$1, 'image']) == null) continue;
        specs.add(_PhotoSpec(
          imagePath: [block, i, pair.$1, 'image'],
          captionPath: pair.$2 == null ? null : _textPath([block, i, pair.$2!], item[pair.$2]),
          onRemove: () => _mutate(() {
            if (pairs.length == 1) {
              (_map[block] as List).removeAt(i);
            } else {
              fillSet(_map, [block, i, pair.$1, 'image'], null);
              if (pair.$2 != null) fillSet(_map, _textPath([block, i, pair.$2!], item[pair.$2]), '');
            }
          }),
        ));
      }
    }
    return _photoWrap(
      specs,
      onAdd: widget.pickPhoto == null
          ? null
          : () async {
              final path = await widget.pickPhoto!();
              if (path == null || !mounted) return;
              _mutate(() {
                final list = _map[block] as List;
                // First empty slot in the last item, else a new item.
                if (list.isNotEmpty) {
                  final last = list.last as Map;
                  for (final pair in _photoPairs(last)) {
                    if (fillGet(last, [pair.$1, 'image']) == null) {
                      fillSet(last, [pair.$1, 'image'], path);
                      return;
                    }
                  }
                }
                final item = _emptyItem(list.isEmpty ? {} : list.last as Map, list.length + 1);
                final first = _photoPairs(item).firstOrNull;
                if (first != null) fillSet(item, [first.$1, 'image'], path);
                list.add(item);
              });
            },
    );
  }

  // --- Photos ----------------------------------------------------------------

  Widget _imagesGrid(String token) {
    final images = (_map[token]['images'] as List);
    return _photoWrap(
      [
        for (var i = 0; i < images.length; i++)
          _PhotoSpec(
            imagePath: [token, 'images', i, 'path'],
            captionPath: [token, 'images', i, 'caption'],
            onRemove: () => _mutate(() => (_map[token]['images'] as List).removeAt(i)),
          ),
      ],
      onAdd: widget.pickPhoto == null
          ? null
          : () async {
              final path = await widget.pickPhoto!();
              if (path == null || !mounted) return;
              _mutate(() {
                final list = _map[token]['images'] as List;
                final width = list.isEmpty ? 3.0 : (list.last as Map)['width_in'] ?? 3.0;
                list.add({'path': path, 'caption': '', 'width_in': width});
              });
            },
    );
  }

  Widget _photoWrap(List<_PhotoSpec> photos, {Future<void> Function()? onAdd}) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 24) / 2;
      return Wrap(
        spacing: 24,
        runSpacing: 22,
        children: [
          for (final photo in photos) SizedBox(width: width, child: _photoCard(photo)),
          if (onAdd != null)
            SizedBox(width: width, height: 56, child: _EmptyPhoto(label: 'Add photo', onTap: onAdd)),
        ],
      );
    });
  }

  Widget _photoCard(_PhotoSpec spec) {
    final path = fillGet(_map, spec.imagePath)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HoverRegion(
          builder: (hovering) => AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (path == null || path.isEmpty)
                  _EmptyPhoto(label: 'Add photo', onTap: _replaceHandler(spec.imagePath))
                else
                  _PhotoImage(future: _photo(path)),
                if (hovering && path != null && path.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      children: [
                        if (widget.pickPhoto != null) _photoChip(Icons.swap_horiz_rounded, 'Replace', _replaceHandler(spec.imagePath)),
                        const SizedBox(width: 6),
                        _photoChip(Icons.delete_outline_rounded, 'Remove', spec.onRemove),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (spec.captionPath != null) ...[
          const SizedBox(height: 6),
          _text(spec.captionPath!, label: 'caption', style: _Doc.body(size: 12.5, color: const Color(0xFF3A404A))),
        ],
      ],
    );
  }

  VoidCallback? _replaceHandler(FillPath imagePath) {
    if (widget.pickPhoto == null) return null;
    return () async {
      final path = await widget.pickPhoto!();
      if (path != null && mounted) _set(imagePath, path);
    };
  }

  /// A single picture slot ({"image": ...}), e.g. a signature.
  Widget _imageSlot(FillPath path, String label) {
    final value = fillGet(_map, path)?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Doc.label()),
        const SizedBox(height: 6),
        SizedBox(
          width: 240,
          height: 90,
          child: value == null || value.isEmpty
              ? _EmptyPhoto(label: 'Add ${label.toLowerCase()}', onTap: _replaceHandler(path), compact: true)
              : _HoverRegion(
                  builder: (hovering) => Stack(
                    fit: StackFit.expand,
                    children: [
                      _PhotoImage(future: _photo(value), fit: BoxFit.contain),
                      if (hovering)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: _photoChip(Icons.delete_outline_rounded, 'Remove', () => _set(path, null)),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _photoChip(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(6),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: _Doc.ink),
              const SizedBox(width: 4),
              Text(label, style: _Doc.body(size: 12, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // --- Small actions ---------------------------------------------------------

  Widget _iconAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 16, color: _Doc.muted)),
      ),
    );
  }

  Widget _addAction(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _HoverRegion(
          builder: (hovering) => InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 15, color: hovering ? _Doc.accent : _Doc.faint),
                  const SizedBox(width: 4),
                  Text(label, style: _Doc.body(size: 12.5, color: hovering ? _Doc.accent : _Doc.faint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSpec {
  final FillPath imagePath;
  final FillPath? captionPath;
  final VoidCallback onRemove;

  _PhotoSpec({required this.imagePath, required this.captionPath, required this.onRemove});
}

class _PhotoImage extends StatelessWidget {
  final Future<Uint8List> future;
  final BoxFit fit;

  const _PhotoImage({required this.future, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: ColoredBox(
        color: const Color(0xFFF1F3F5),
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasData) return Image.memory(snapshot.data!, fit: fit, gaplessPlayback: true);
            if (snapshot.hasError) {
              return Center(child: Text('Photo unavailable', style: _Doc.body(size: 12, color: _Doc.muted)));
            }
            return const Center(
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _Doc.faint)),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyPhoto extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  const _EmptyPhoto({required this.label, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return _HoverRegion(
      builder: (hovering) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          decoration: BoxDecoration(
            color: hovering ? _Doc.hover : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: hovering ? _Doc.editBorder : _Doc.rule),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(compact ? Icons.add_rounded : Icons.add_photo_alternate_outlined,
                    size: compact ? 15 : 20, color: hovering ? _Doc.accent : _Doc.faint),
                const SizedBox(width: 6),
                Text(label, style: _Doc.body(size: 12.5, color: hovering ? _Doc.accent : _Doc.faint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverRegion extends StatefulWidget {
  final Widget Function(bool hovering) builder;

  const _HoverRegion({required this.builder});

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: widget.builder(_hovering),
    );
  }
}

// -----------------------------------------------------------------------------
// Inline editable text
// -----------------------------------------------------------------------------

/// Text that reads as part of the document and turns into an editor on
/// click. Hover shows a faint tint; empty values show a quiet "Add ..." hint.
/// Esc restores the value from before editing; clicking away keeps the edit.
class InlineEditableText extends StatefulWidget {
  final String value;
  final String placeholder;
  final String? tooltip;
  final TextStyle style;
  final bool multiline;
  final bool startEditing;
  final ValueChanged<String> onChanged;

  const InlineEditableText({
    super.key,
    required this.value,
    required this.placeholder,
    required this.style,
    required this.onChanged,
    this.tooltip,
    this.multiline = true,
    this.startEditing = false,
  });

  @override
  State<InlineEditableText> createState() => _InlineEditableTextState();
}

class _InlineEditableTextState extends State<InlineEditableText> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  bool _hovering = false;
  String _before = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing && mounted) setState(() => _editing = false);
    });
    if (widget.startEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startEditing(cursorAtEnd: true));
    }
  }

  @override
  void didUpdateWidget(covariant InlineEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing({bool cursorAtEnd = false}) {
    if (!mounted) return;
    _before = widget.value;
    _controller.text = widget.value;
    _controller.selection = TextSelection.collapsed(offset: cursorAtEnd ? widget.value.length : widget.value.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _cancel() {
    _controller.text = _before;
    widget.onChanged(_before);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
          if (!widget.multiline) const SingleActivator(LogicalKeyboardKey.enter): () => _focus.unfocus(),
        },
        child: _Bleed(
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: _Doc.editFill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _Doc.editBorder),
            boxShadow: const [BoxShadow(color: Color(0x1A2F6FEB), blurRadius: 0, spreadRadius: 3)],
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            style: widget.style,
            cursorColor: _Doc.accent,
            cursorWidth: 1.5,
            maxLines: widget.multiline ? null : 1,
            keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
            decoration: InputDecoration.collapsed(
              hintText: widget.tooltip ?? widget.placeholder,
              hintStyle: widget.style.copyWith(color: _Doc.faint),
            ),
            onChanged: widget.onChanged,
          ),
        ),
        ),
      );
    }

    final empty = widget.value.trim().isEmpty;
    final Widget content = empty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 14, color: _hovering ? _Doc.accent : _Doc.faint),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  widget.placeholder,
                  style: widget.style.copyWith(
                    color: _hovering ? _Doc.accent : _Doc.faint,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          )
        : Text(widget.value, style: widget.style);

    final body = MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startEditing,
        child: _Bleed(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _hovering ? _Doc.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: content),
          ),
        ),
      ),
    );
    if (empty && widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 400), child: body);
    }
    return body;
  }
}

/// Shifts the edit/hover box 5px left so its text lines up with the
/// document's labels while the tint bleeds into the margin.
class _Bleed extends StatelessWidget {
  final Widget child;

  const _Bleed({required this.child});

  @override
  Widget build(BuildContext context) => Transform.translate(offset: const Offset(-5, 0), child: child);
}
