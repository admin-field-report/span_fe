import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:field_report_fe/span_doc/docx_model.dart';
import 'package:field_report_fe/span_doc/fill_binding.dart';
import 'package:field_report_fe/span_doc/fill_values.dart';
import 'package:field_report_fe/span_doc/rich_field_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

String _p(String text, {bool bold = false}) =>
    '<w:p><w:r>${bold ? '<w:rPr><w:b/></w:rPr>' : ''}<w:t xml:space="preserve">$text</w:t></w:r></w:p>';

String _frame(String token) => '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="2743200" cy="1828800"/>'
    '<wp:docPr id="1" name="Picture" descr="$token"/>'
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:blipFill><a:blip r:embed="rIdImg"/></pic:blipFill></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';

/// A small Word file like a profiled template: fields, a token Word split
/// across runs, a list row in a table, and a repeating photo block.
Uint8List _template() {
  final body = [
    _p('Report', bold: true),
    // Word often splits a placeholder over several runs.
    '<w:p><w:r><w:t>Contractor: {{CONT</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>RACTOR}}</w:t></w:r></w:p>',
    '<w:tbl><w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="6000"/></w:tblGrid>'
        '<w:tr><w:tc>${_p('{{DATE}}')}</w:tc><w:tc>${_p('{{ACTIVITIES}}')}</w:tc></w:tr></w:tbl>',
    _p('{{BLOCK_START:PHOTOS}}'),
    _frame('{{PHOTO}}'),
    _p('{{CAPTION}}'),
    _p('{{BLOCK_END:PHOTOS}}'),
    _p('{{EMPTY_NOTE}}'),
  ].join();
  final document = '<?xml version="1.0" encoding="UTF-8"?><w:document $_w><w:body>$body'
      '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440" w:header="720" w:footer="720"/></w:sectPr>'
      '</w:body></w:document>';
  const rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdImg" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>';
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(document)))
    ..addFile(ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(rels)))
    ..addFile(ArchiveFile.bytes('word/media/image1.png', [137, 80, 78, 71]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, dynamic> _fill() => {
      '{{CONTRACTOR}}': 'BRONXDALE MASONRY CORP',
      '{{DATE}}': ['5-4-26', '5-6-26'],
      '{{ACTIVITIES}}': ['Removed parapet', 'Laid new brick'],
      '{{BLOCK:PHOTOS}}': [
        {'{{PHOTO}}': {'image': '/workspace/inspection/photos/a.jpg'}, '{{CAPTION}}': 'First'},
        {'{{PHOTO}}': {'image': '/workspace/inspection/photos/b.jpg'}, '{{CAPTION}}': 'Second'},
      ],
      '{{EMPTY_NOTE}}': '',
    };

List<T> _all<T>(List<DocxBlock> blocks) {
  final out = <T>[];
  void visit(List<DocxBlock> bs) {
    for (final b in bs) {
      switch (b) {
        case DocxParagraph p:
          out.addAll(p.inlines.whereType<T>());
          for (final s in p.inlines.whereType<DocxShape>()) {
            visit(s.blocks);
          }
        case DocxTable t:
          for (final r in t.rows) {
            for (final c in r.cells) {
              visit(c.blocks);
            }
          }
        case DocxGroup g:
          visit(g.blocks);
      }
    }
  }

  visit(blocks);
  return out;
}

void main() {
  group('DocxDocument', () {
    test('reads paragraphs, tables, page setup and a split placeholder', () {
      final doc = DocxDocument.parse(_template());
      expect(doc.sections.single.pageWidth, 612);
      expect(doc.sections.single.headerDistance, 36);
      expect(doc.body.whereType<DocxTable>(), hasLength(1));
      expect(doc.tokens, containsAll(['{{CONTRACTOR}}', '{{DATE}}', '{{ACTIVITIES}}', '{{PHOTO}}', '{{CAPTION}}']));
      final contractor = doc.body.whereType<DocxParagraph>().firstWhere((p) => p.text.contains('Contractor'));
      final slot = contractor.inlines.whereType<DocxSlot>().single;
      expect(slot.token, '{{CONTRACTOR}}');
      expect(slot.style.bold, isNot(true), reason: 'styled like the run the token starts in');
    });
  });

  group('FillBinder', () {
    test('binds values, repeats list rows and repeating blocks', () {
      final fill = _fill();
      final bound = FillBinder(fill).bind(DocxDocument.parse(_template()));
      final slots = _all<DocxSlot>(bound.body).where((s) => !s.isMarker).toList();
      expect(slots.firstWhere((s) => s.token == '{{CONTRACTOR}}').path, ['{{CONTRACTOR}}']);
      expect(slots.where((s) => s.token == '{{ACTIVITIES}}').map((s) => s.path), [
        ['{{ACTIVITIES}}', 0],
        ['{{ACTIVITIES}}', 1],
      ]);
      expect(bound.body.whereType<DocxGroup>(), hasLength(2));
      expect(slots.where((s) => s.token == '{{CAPTION}}').map((s) => fillGet(fill, s.path!)), ['First', 'Second']);
      final photos = _all<DocxImage>(bound.body).where((i) => i.photo != null).toList();
      expect(photos.map((p) => fillGet(fill, p.photo!.imagePath)), ['/workspace/inspection/photos/a.jpg', '/workspace/inspection/photos/b.jpg']);
      expect(photos.first.photo!.listPath, ['{{BLOCK:PHOTOS}}']);
      expect(photos.first.photo!.captionPath, ['{{BLOCK:PHOTOS}}', 0, '{{CAPTION}}']);
    });

    test('a removed photo item drops its block copy', () {
      final fill = _fill();
      (fill['{{BLOCK:PHOTOS}}'] as List).removeAt(0);
      final bound = FillBinder(fill).bind(DocxDocument.parse(_template()));
      expect(bound.body.whereType<DocxGroup>(), hasLength(1));
    });
  });

  group('fill values', () {
    test('plain runs stay a string; formatting becomes runs; max_chars is kept', () {
      expect(valueWithRuns('x', const [FillRun('Seal it')]), 'Seal it');
      expect(valueWithRuns({'text': 'a', 'max_chars': 18}, const [FillRun('Sunny')]), {'text': 'Sunny', 'max_chars': 18});
      expect(valueWithRuns('x', const [FillRun('Seal with '), FillRun('epoxy', bold: true)]), {
        'runs': [
          {'text': 'Seal with '},
          {'text': 'epoxy', 'bold': true},
        ],
      });
      expect(valueText({'runs': [{'text': 'a'}, {'text': 'b', 'bold': true}]}), 'ab');
    });

    test('photo paths are found anywhere in a fill map', () {
      expect(photoPathsIn(_fill()), ['/workspace/inspection/photos/a.jpg', '/workspace/inspection/photos/b.jpg']);
    });
  });

  group('RichFieldController', () {
    test('bold on a selection, typing keeps formatting, runs come back out', () {
      final c = RichFieldController(const [FillRun('BRONXDALE MASONRY CORP')]);
      c.selection = const TextSelection(baseOffset: 10, extentOffset: 17);
      c.toggle(RichFormat.bold);
      expect(c.isActive(RichFormat.bold), isTrue);
      expect(c.runs.map((r) => (r.text, r.bold)), [('BRONXDALE ', false), ('MASONRY', true), (' CORP', false)]);
      c.value = const TextEditingValue(text: 'BRONXDALE MASONRYS CORP', selection: TextSelection.collapsed(offset: 18));
      expect(c.runs[1].text, 'MASONRYS', reason: 'typed text takes the formatting before it');
    });

    test('bullets toggle on every selected line and continue on Enter', () {
      final c = RichFieldController(const [FillRun('one\ntwo')]);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      c.toggleBullets();
      expect(c.text, '• one\n• two');
      c.value = TextEditingValue(text: '${c.text}\n', selection: TextSelection.collapsed(offset: c.text.length + 1));
      expect(c.text, '• one\n• two\n• ');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.toggleBullets();
      expect(c.text.startsWith('one'), isTrue);
    });
  });
}
