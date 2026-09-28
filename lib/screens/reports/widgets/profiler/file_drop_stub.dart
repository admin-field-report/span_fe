import 'dart:typed_data';

/// Non-web stub: there is no browser drag and drop, so this never fires.
/// Returns a no-op unsubscribe callback.
void Function() listenForFileDrops({
  required void Function(bool hovering) onHover,
  required void Function(List<({String name, Uint8List bytes})> files) onDrop,
}) {
  return () {};
}
