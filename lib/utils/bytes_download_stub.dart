import 'dart:typed_data';

/// Non-web stub for [downloadBytesWeb].
///
/// Mobile/desktop builds don't have a browser to trigger a download in, so
/// this stub simply throws. If we ever ship Eve Word reports to
/// mobile/desktop, replace this with a temp-file + share-sheet flow (see
/// `fe_flutter`'s `path_provider` + `share_plus` based implementation for
/// reference) — that would require adding those packages to `pubspec.yaml`.
Future<void> downloadBytesWeb(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError(
    'Browser download is not available on this platform. '
    'Use a temp file + share sheet instead.',
  );
}
