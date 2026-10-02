import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Save a report file (Word or PDF) on any platform: a browser download on
/// web; on iPad / Android / desktop a file under Documents/Span Inspect,
/// opened in the default app (Word, a PDF viewer) when [open] is true.
/// Returns where it went ('' on web).
Future<String> saveReportFile(
  Uint8List bytes, {
  required String fileName,
  required String extension,
  bool open = true,
}) async {
  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  final mime = extension == 'pdf' ? MimeType.pdf : MimeType.microsoftWord;
  if (kIsWeb) {
    await FileSaver.instance.saveFile(name: safe, bytes: bytes, fileExtension: extension, mimeType: mime);
    return '';
  }
  io.Directory? base;
  if (io.Platform.isAndroid) {
    base = io.Directory('/storage/emulated/0/Documents');
    if (!await base.exists()) base = await getExternalStorageDirectory();
  }
  base ??= await getApplicationDocumentsDirectory();
  final dir = io.Directory('${base.path}/Span Inspect');
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = io.File('${dir.path}/$safe.$extension');
  await file.writeAsBytes(bytes, flush: true);
  if (open) await OpenFilex.open(file.path);
  return file.path;
}
