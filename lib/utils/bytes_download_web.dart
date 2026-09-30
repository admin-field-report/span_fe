// Web-specific binary download helper (used for the Eve Word report's
// filled .docx and generation-notes.md downloads).
//
// We use `package:universal_html` instead of `dart:html` directly because
// it's already a dependency of this app (see `pubspec.yaml`, used by
// `widgets/canvas/canvas.dart`) and works without the
// `avoid_web_libraries_in_flutter` lint suppression that raw `dart:html`
// imports need. This file is only ever compiled in when running on the web
// (see the conditional import in the calling screens), so the underlying
// browser APIs are always available at runtime.
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';

/// Trigger a browser download for [bytes] with the given [fileName] / MIME type.
///
/// Implementation: wrap the bytes in a `Blob`, turn that into a temporary
/// object URL, "click" a hidden anchor tag pointing at it (this is what
/// actually starts the browser's download), then revoke the URL so we don't
/// leak memory.
Future<void> downloadBytesWeb(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
