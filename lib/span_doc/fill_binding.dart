import 'docx_model.dart';
import 'fill_values.dart';

/// Lays a report's fill map over its template the way fill_template.py fills
/// the Word file, without changing any text: repeating blocks and list rows
/// are expanded, and every placeholder and photo frame is bound to the place
/// in the fill map its value comes from ([DocxSlot.path], [DocxImage.photo]).
/// The page then reads values live from the map, so typing into a field never
/// needs a re-bind; only structural edits (moving or removing a photo) do.
///
/// Order follows fill_template.py: blocks, then photo frames, image lists,
/// list rows, and finally plain text (which also applies inside blocks).
class FillBinder {
  final Map<String, dynamic> fill;

  FillBinder(this.fill);

  static final RegExp _sign = RegExp(r'SIGN|SEAL|STAMP|INITIAL', caseSensitive: false);
  static final RegExp _index = RegExp(r'_(\d+)(?=_|\}\})');

  DocxDocument bind(DocxDocument doc) {
    final top = _Scope.top(fill);
    return DocxDocument(
      body: _bindBlocks(_expandBlocks(doc.body), top),
      sections: doc.sections,
      parts: {for (final e in doc.parts.entries) e.key: _bindBlocks(e.value, top)},
    );
  }

  // --- repeating blocks -------------------------------------------------------

  List<DocxBlock> _expandBlocks(List<DocxBlock> body) {
    var out = body;
    for (final entry in fill.entries) {
      final key = entry.key;
      if (!key.startsWith('{{BLOCK:')) continue;
      final name = key.substring(8, key.length - 2);
      final items = _blockItems(key, name, entry.value, out);
      if (items == null) continue;
      out = _replaceRanges(out, name, (range) {
        return [
          for (var i = 0; i < items.length; i++)
            DocxGroup(name: name, index: i, blocks: _bindBlocks(range, items[i])),
        ];
      });
    }
    return out;
  }

  /// Item scopes for a block value: a list of mini fill maps, or a photo block
  /// ({"photos": [...]} / {"groups": [...]}) cut into rows by the template's
  /// photo frames. Null when the value is not a block shape.
  List<_Scope>? _blockItems(String key, String name, dynamic value, List<DocxBlock> body) {
    if (value is List) {
      return [
        for (var i = 0; i < value.length; i++)
          if (value[i] is Map) _Scope.item(fill, key, i, (value[i] as Map).cast<String, dynamic>()),
      ];
    }
    if (value is Map && (value['photos'] is List || value['groups'] is List)) {
      final range = _ranges(body, name).firstOrNull;
      if (range == null) return null;
      return _photoRows(key, value.cast<String, dynamic>(), range);
    }
    return null;
  }

  List<DocxBlock> _replaceRanges(List<DocxBlock> body, String name, List<DocxBlock> Function(List<DocxBlock>) expand) {
    final start = '{{BLOCK_START:$name}}';
    final end = '{{BLOCK_END:$name}}';
    final out = <DocxBlock>[];
    List<DocxBlock>? current;
    for (final block in body) {
      final text = blockText(block);
      if (current == null && text.contains(start)) current = [];
      if (current != null) {
        current.add(block);
        if (text.contains(end)) {
          out.addAll(expand(current));
          current = null;
        }
      } else {
        out.add(block);
      }
    }
    if (current != null) out.addAll(current); // no END marker: leave as is
    return out;
  }

  List<List<DocxBlock>> _ranges(List<DocxBlock> body, String name) {
    final ranges = <List<DocxBlock>>[];
    _replaceRanges(body, name, (range) {
      ranges.add(range);
      return range;
    });
    return ranges;
  }

  // --- photo blocks (photo_slots.py) -----------------------------------------------

  List<_Scope> _photoRows(String key, Map<String, dynamic> value, List<DocxBlock> range) {
    final frames = <(String, double, double)>[];
    final texts = <String>[];
    void visit(List<DocxBlock> blocks) {
      for (final b in blocks) {
        if (b is DocxParagraph) {
          for (final i in b.inlines) {
            if (i is DocxImage && i.slot != null && !_sign.hasMatch(i.slot!)) {
              if (!(i.width < 43.2 && i.height < 43.2)) frames.add((i.slot!, i.width, i.height));
            } else if (i is DocxSlot && !i.isMarker) {
              texts.add(i.token);
            } else if (i is DocxShape) {
              visit(i.blocks);
            }
          }
        } else if (b is DocxTable) {
          for (final r in b.rows) {
            for (final c in r.cells) {
              visit(c.blocks);
            }
          }
        } else if (b is DocxGroup) {
          visit(b.blocks);
        }
      }
    }

    visit(range);
    final uniqueFrames = <String>[];
    for (final f in frames) {
      if (!uniqueFrames.contains(f.$1)) uniqueFrames.add(f.$1);
    }
    final textTokens = texts.toSet().toList();
    int? indexOf(String token) => int.tryParse(_index.firstMatch(token)?.group(1) ?? '');
    uniqueFrames.sort((a, b) {
      final c = (indexOf(a) ?? 0).compareTo(indexOf(b) ?? 0);
      return c != 0 ? c : a.compareTo(b);
    });
    final single = uniqueFrames.length == 1;
    final slots = <_PhotoSlot>[];
    for (var pos = 0; pos < uniqueFrames.length; pos++) {
      final token = uniqueFrames[pos];
      final idx = indexOf(token) ?? (single ? 1 : pos + 1);
      final slot = _PhotoSlot(token);
      for (final t in textTokens) {
        final ti = indexOf(t);
        final related = ti == idx || (single && ti == null && RegExp(r'CAPTION|PHOTO|IMAGE|PICTURE', caseSensitive: false).hasMatch(t));
        if (!related) continue;
        var kind = _kindOf(t);
        if (kind == 'caption' && slot.fields['caption'] != null) kind = 'description';
        if (const ['caption', 'description', 'time', 'number'].contains(kind) && slot.fields[kind] == null) {
          slot.fields[kind] = t;
        }
      }
      slots.add(slot);
    }
    final used = {for (final s in slots) ...s.fields.values};
    final rowTokens = textTokens.where((t) => !used.contains(t)).toList();
    final per = slots.isEmpty ? 1 : slots.length;

    final scopes = <_Scope>[];
    final groups = value['groups'] is List ? value['groups'] as List : [value];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g] is Map ? (groups[g] as Map).cast<String, dynamic>() : <String, dynamic>{};
      final base = <Object>[key, if (value['groups'] is List) ...['groups', g]];
      final photos = group['photos'] is List ? group['photos'] as List : const [];
      var rows = (photos.length / per).ceil();
      if (rows == 0 && group['first_row'] != null) rows = 1;
      for (var r = 0; r < rows; r++) {
        final scope = _Scope.top(fill);
        for (final tok in rowTokens) {
          final first = group['first_row'] is Map && (group['first_row'] as Map).containsKey(tok);
          final each = group['each_row'] is Map && (group['each_row'] as Map).containsKey(tok);
          if (r == 0 && first) {
            scope.paths[tok] = [...base, 'first_row', tok];
          } else if (each) {
            scope.paths[tok] = [...base, 'each_row', tok];
          } else if (r > 0) {
            scope.blanks.add(tok);
          }
        }
        for (var k = 0; k < slots.length; k++) {
          final i = r * per + k;
          final slot = slots[k];
          if (i >= photos.length) {
            scope.removedFrames.add(slot.frame);
            scope.blanks.addAll(slot.fields.values);
            continue;
          }
          final photoPath = <Object>[...base, 'photos', i];
          final isMap = photos[i] is Map;
          scope.photos[slot.frame] = PhotoRef(
            imagePath: isMap ? [...photoPath, 'image'] : photoPath,
            captionPath: isMap ? [...photoPath, 'caption'] : null,
            listPath: [...base, 'photos'],
            index: i,
          );
          slot.fields.forEach((field, tok) {
            if (isMap) {
              scope.paths[tok] = [...photoPath, field];
            } else {
              scope.blanks.add(tok);
            }
          });
        }
        scopes.add(scope);
      }
    }
    return scopes;
  }

  static String _kindOf(String token) {
    final parts = token.replaceAll(RegExp(r'[{}]'), '').toUpperCase().split('_').where((p) => p.isNotEmpty && int.tryParse(p) == null).toList();
    for (final part in parts.reversed) {
      if (const ['TIME', 'TIMESTAMP', 'STAMP', 'DATE', 'DATETIME', 'TAKEN'].contains(part)) return 'time';
      if (const ['CAPTION', 'TITLE', 'LABEL'].contains(part)) return 'caption';
      if (const ['TEXT', 'DESC', 'DESCRIPTION', 'NOTE', 'NOTES', 'COMMENT'].contains(part)) return 'description';
      if (const ['NO', 'NUM', 'NUMBER', 'SEQ'].contains(part)) return 'number';
      if (const ['PHOTO', 'IMAGE', 'PICTURE'].contains(part)) break;
    }
    return 'extra';
  }

  // --- binding ----------------------------------------------------------------

  List<DocxBlock> _bindBlocks(List<DocxBlock> blocks, _Scope scope) {
    final out = <DocxBlock>[];
    for (final block in blocks) {
      switch (block) {
        case DocxParagraph p:
          out.addAll(_bindParagraph(p, scope));
        case DocxTable t:
          out.add(_bindTable(t, scope));
        case DocxGroup g:
          out.add(g); // already bound with its item scope
      }
    }
    return out;
  }

  /// List tokens in a paragraph clone it once per item (fill_template.py's
  /// expand_lists); a token holding {"images": [...]} turns into one picture
  /// and one caption paragraph per image.
  List<DocxParagraph> _bindParagraph(DocxParagraph p, _Scope scope, {Map<String, int>? listIndex}) {
    final tokens = p.inlines.whereType<DocxSlot>().map((s) => s.token).toList();

    for (final token in tokens) {
      final value = scope.paths.containsKey(token) ? null : fill[token];
      if (value is Map && value['images'] is List && listIndex == null) {
        return _imageList(p, token, value['images'] as List);
      }
    }

    if (listIndex == null) {
      final lists = tokens.where((t) => scope.isTop && fill[t] is List && !t.startsWith('{{BLOCK:')).toList();
      if (lists.isNotEmpty) {
        final n = lists.map((t) => (fill[t] as List).length).fold<int>(0, (a, b) => a > b ? a : b);
        return [
          for (var i = 0; i < n; i++) ..._bindParagraph(p, scope, listIndex: {for (final t in lists) t: i}),
        ];
      }
    }

    final inlines = <DocxInline>[];
    var hasContent = false;
    var onlyMarkers = true;
    for (final inline in p.inlines) {
      switch (inline) {
        case DocxSlot s:
          if (s.isMarker) {
            inlines.add(s);
            continue;
          }
          onlyMarkers = false;
          final listAt = listIndex?[s.token];
          if (listAt != null) {
            final items = fill[s.token] as List;
            inlines.add(listAt < items.length ? s.bound([s.token, listAt]) : s.bound(null, blank: true));
          } else {
            inlines.add(_bindSlot(s, scope));
          }
          hasContent = true;
        case DocxImage i:
          onlyMarkers = false;
          hasContent = true;
          inlines.add(_bindImage(i, scope));
        case DocxShape shape:
          onlyMarkers = false;
          hasContent = true;
          inlines.add(shape.withBlocks(_bindBlocks(shape.blocks, scope)));
        case DocxText t:
          if (t.text.trim().isNotEmpty && t.style.hidden != true) {
            onlyMarkers = false;
            hasContent = true;
          }
          inlines.add(t);
        default:
          inlines.add(inline);
      }
    }
    // A marker paragraph left empty is removed (strip_markers), unless it
    // ends a section.
    final markerOnly = onlyMarkers && !hasContent && p.inlines.any((i) => i is DocxSlot && i.isMarker);
    if (markerOnly && p.sectionIndex == null) return const [];
    return [p.copyWith(inlines: inlines)];
  }

  DocxSlot _bindSlot(DocxSlot s, _Scope scope) {
    if (scope.blanks.contains(s.token)) return s.bound(null, blank: true);
    final scoped = scope.paths[s.token];
    if (scoped != null) return s.bound(scoped);
    if (fill.containsKey(s.token)) {
      final value = fill[s.token];
      if (value is Map && (value.containsKey('image') || value['images'] is List)) return s.bound(null, blank: true);
      return s.bound([s.token]);
    }
    return s; // not in the fill map: left as the placeholder text
  }

  DocxImage _bindImage(DocxImage image, _Scope scope) {
    final token = image.slot;
    if (token == null) return image;
    if (scope.removedFrames.contains(token)) return image.bound(removed: true);
    final scoped = scope.photos[token];
    if (scoped != null) return image.bound(photo: scoped);
    final itemPath = scope.paths[token];
    final path = itemPath ?? (fill.containsKey(token) ? <Object>[token] : null);
    if (path == null) return image;
    final value = fillGet(fill, path);
    if (value is Map && value.containsKey('image')) {
      if (value['image'] == null) return image.bound(removed: true);
      return image.bound(
        photo: PhotoRef(
          imagePath: [...path, 'image'],
          captionPath: scope.captionFor(token),
          listPath: scope.listPath,
          index: scope.listIndex,
        ),
      );
    }
    return image;
  }

  List<DocxParagraph> _imageList(DocxParagraph p, String token, List images) {
    final out = <DocxParagraph>[];
    for (var j = 0; j < images.length; j++) {
      final image = images[j];
      if (image is! Map) continue;
      final width = ((image['width_in'] as num?)?.toDouble() ?? 3.0) * 72;
      out.add(p.copyWith(inlines: [
        DocxImage(
          width: width,
          height: width * 0.75,
          photo: PhotoRef(
            imagePath: [token, 'images', j, 'path'],
            captionPath: [token, 'images', j, 'caption'],
            listPath: [token, 'images'],
            index: j,
          ),
        ),
      ]));
      out.add(p.copyWith(inlines: [
        DocxSlot(token, p.markStyle, path: [token, 'images', j, 'caption']),
      ]));
    }
    return out;
  }

  DocxTable _bindTable(DocxTable t, _Scope scope) {
    final rows = <DocxRow>[];
    for (final row in t.rows) {
      final tokens = <String>{};
      for (final cell in row.cells) {
        for (final b in cell.blocks) {
          tokens.addAll(placeholderPattern.allMatches(blockText(b)).map((m) => m.group(0)!));
        }
      }
      final lists = tokens.where((tok) => scope.isTop && fill[tok] is List && !tok.startsWith('{{BLOCK:')).toList();
      if (lists.isEmpty) {
        rows.add(row.copyWith(cells: [for (final c in row.cells) c.copyWith(blocks: _bindBlocks(c.blocks, scope))]));
        continue;
      }
      final n = lists.map((tok) => (fill[tok] as List).length).fold<int>(0, (a, b) => a > b ? a : b);
      for (var i = 0; i < n; i++) {
        final index = {for (final tok in lists) tok: i};
        rows.add(row.copyWith(cells: [
          for (final c in row.cells)
            c.copyWith(blocks: [
              for (final b in c.blocks)
                if (b is DocxParagraph) ..._bindParagraph(b, scope, listIndex: index) else ..._bindBlocks([b], scope),
            ]),
        ]));
      }
    }
    return t.copyWith(rows: rows);
  }
}

class _PhotoSlot {
  final String frame;
  final Map<String, String> fields = {};

  _PhotoSlot(this.frame);
}

/// What tokens mean inside one repeated item (or at the top level).
class _Scope {
  final Map<String, FillPath> paths = {};
  final Map<String, PhotoRef> photos = {};
  final Set<String> blanks = {};
  final Set<String> removedFrames = {};
  final FillPath? listPath;
  final int? listIndex;
  final bool isTop;

  _Scope._({this.listPath, this.listIndex, this.isTop = false});

  factory _Scope.top(Map<String, dynamic> fill) => _Scope._(isTop: true);

  /// One item of a {{BLOCK:NAME}} list: its own keys bind to the item.
  factory _Scope.item(Map<String, dynamic> fill, String key, int index, Map<String, dynamic> item) {
    final scope = _Scope._(listPath: [key], listIndex: index);
    for (final k in item.keys) {
      scope.paths[k] = [key, index, k];
    }
    return scope;
  }

  /// The caption that goes with a photo frame in this item: a text field
  /// named like a caption.
  FillPath? captionFor(String frame) {
    if (listPath == null) return null;
    for (final entry in paths.entries) {
      if (entry.key != frame && RegExp(r'CAPTION|DESC', caseSensitive: false).hasMatch(entry.key)) return entry.value;
    }
    return null;
  }
}

/// Every token and text of a block, deep (paragraphs, tables, text boxes).
String blockText(DocxBlock block) {
  final out = StringBuffer();
  void visit(DocxBlock b) {
    switch (b) {
      case DocxParagraph p:
        for (final i in p.inlines) {
          if (i is DocxText) out.write(i.text);
          if (i is DocxSlot) out.write(i.token);
          if (i is DocxShape) i.blocks.forEach(visit);
        }
      case DocxTable t:
        for (final r in t.rows) {
          for (final c in r.cells) {
            c.blocks.forEach(visit);
          }
        }
      case DocxGroup g:
        g.blocks.forEach(visit);
    }
  }

  visit(block);
  return out.toString();
}
