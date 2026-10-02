// Runs against real report fixtures on this machine (not in the repo):
// SPAN_FIXTURES=<dir with template.docx and fill_map.json> flutter test test/span_doc/local_fixture_test.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:field_report_fe/span_doc/docx_model.dart';
import 'package:field_report_fe/span_doc/fill_binding.dart';
import 'package:field_report_fe/span_doc/fill_values.dart';
import 'package:field_report_fe/span_doc/report_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

String _short(String text, [int max = 60]) {
  final flat = text.replaceAll('\n', ' ');
  return flat.length > max ? '${flat.substring(0, max)}…' : flat;
}

void main() {
  final dir = Platform.environment['SPAN_FIXTURES'];
  final skip = dir == null ? 'SPAN_FIXTURES not set' : false;

  test('parses a real template', () {
    final doc = DocxDocument.parse(File('$dir/template.docx').readAsBytesSync());
    print('sections ${doc.sections.length} parts ${doc.parts.keys} blocks ${doc.body.length}');
    print('tokens ${doc.tokens}');
    for (final b in doc.body) {
      if (b is DocxParagraph) {
        print('P ${b.style.styleId} "${_short(b.text)}"${b.hasPicture ? ' [pic]' : ''}${b.sectionIndex != null ? ' <sect>' : ''}');
      } else if (b is DocxTable) {
        print('T ${b.rows.length}x${b.grid.length}');
      }
    }
  }, skip: skip);

  test('binds the report fill map', () {
    final doc = DocxDocument.parse(File('$dir/template.docx').readAsBytesSync());
    final fill = (jsonDecode(File('$dir/fill_map.json').readAsStringSync()) as Map).cast<String, dynamic>();
    final bound = FillBinder(fill).bind(doc);

    void visit(List<DocxBlock> blocks, String indent) {
      for (final b in blocks) {
        if (b is DocxGroup) {
          print('${indent}GROUP ${b.name} #${b.index}');
          visit(b.blocks, '$indent  ');
        } else if (b is DocxTable) {
          for (final r in b.rows) {
            for (final c in r.cells) {
              visit(c.blocks, '$indent  |');
            }
          }
        } else if (b is DocxParagraph) {
          for (final i in b.inlines) {
            if (i is DocxSlot) {
              if (i.isMarker) continue;
              final value = i.path == null ? null : fillGet(fill, i.path!);
              print('$indent${i.token} -> ${i.path}${i.blank ? ' (blank)' : ''} = "${_short(valueText(value), 50)}"');
            } else if (i is DocxImage) {
              if (i.slot == null && i.photo == null) continue;
              final value = i.photo == null ? null : fillGet(fill, i.photo!.imagePath);
              print('${indent}IMG ${i.slot} -> ${i.photo?.imagePath} cap ${i.photo?.captionPath} '
                  'list ${i.photo?.listPath}[${i.photo?.index}] removed=${i.removed} = $value');
            } else if (i is DocxShape) {
              visit(i.blocks, '$indent  [box] ');
            }
          }
        }
      }
    }

    visit(bound.body, '');
  }, skip: skip);

  testWidgets('draws the bound report page', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final doc = DocxDocument.parse(File('$dir/template.docx').readAsBytesSync());
    final fill = (jsonDecode(File('$dir/fill_map.json').readAsStringSync()) as Map).cast<String, dynamic>();
    final bound = FillBinder(fill).bind(doc);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ReportPageView(document: bound, fill: fill, onTapSlot: (_) {}))),
    ));
    await tester.pump();
    final errors = <Object>[];
    Object? e;
    while ((e = tester.takeException()) != null) {
      errors.add(e!);
    }
    for (final err in errors) {
      print('EXCEPTION: $err');
    }
    expect(errors, isEmpty);
  }, skip: dir == null);
}
