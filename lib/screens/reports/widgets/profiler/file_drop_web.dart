// Browser drag-and-drop of files onto the page (Flutter web).
//
// Flutter has no built-in file-drop target on web, and adding a plugin would
// touch pubspec.lock, so this listens to the document's native drag events
// through `universal_html` (already a dependency; same approach as
// utils/bytes_download_web.dart).
import 'dart:async';
import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

bool _hasFiles(html.MouseEvent event) {
  final types = event.dataTransfer.types;
  return types != null && types.contains('Files');
}

Future<Uint8List?> _readFile(html.File file) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;
  final result = reader.result;
  if (result is Uint8List) return result;
  if (result is ByteBuffer) return result.asUint8List();
  return null;
}

/// Listen for files dragged over / dropped anywhere on the page. [onHover]
/// reports whether files are currently being dragged over the window.
/// Returns an unsubscribe callback; call it from `dispose`.
void Function() listenForFileDrops({
  required void Function(bool hovering) onHover,
  required void Function(List<({String name, Uint8List bytes})> files) onDrop,
}) {
  final subscriptions = <StreamSubscription<html.MouseEvent>>[];
  var depth = 0;

  subscriptions.add(html.document.onDragEnter.listen((event) {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    depth += 1;
    onHover(true);
  }));
  subscriptions.add(html.document.onDragOver.listen((event) {
    if (!_hasFiles(event)) return;
    // Required, or the browser opens the file instead of dropping it here.
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
  }));
  subscriptions.add(html.document.onDragLeave.listen((event) {
    if (!_hasFiles(event)) return;
    depth -= 1;
    if (depth <= 0) {
      depth = 0;
      onHover(false);
    }
  }));
  subscriptions.add(html.document.onDrop.listen((event) async {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    depth = 0;
    onHover(false);
    final files = event.dataTransfer.files ?? const <html.File>[];
    final dropped = <({String name, Uint8List bytes})>[];
    for (final file in files) {
      final bytes = await _readFile(file);
      if (bytes != null) dropped.add((name: file.name, bytes: bytes));
    }
    if (dropped.isNotEmpty) onDrop(dropped);
  }));

  return () {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
  };
}
