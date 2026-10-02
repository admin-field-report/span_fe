import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../span_doc/docx_model.dart';
import '../../../../../span_doc/fill_values.dart';
import '../../../../../span_doc/report_page_view.dart' show reportSelectionBlue;
import '../report_generation_api.dart';

const Color _ink = Color(0xFF212529);
const Color _muted = Color(0xFF868E96);
const Color _line = Color(0xFFDEE2E6);

/// The report editor's right sidebar. With no photo selected it shows the
/// inspection's photos (the ones in the report marked); with a photo selected
/// it shows that photo: caption, move, remove, and the album to swap from.
class ReportPhotoSidebar extends StatelessWidget {
  final List<AlbumPhoto> album;
  final Map<String, dynamic> fill;
  final PhotoRef? selected;

  /// 1-based position of the selected photo among the report's photos.
  final int? selectedNumber;
  final Future<Uint8List> Function(String path) loadPhoto;
  final ValueChanged<String> onSwap;
  final ValueChanged<String> onCaptionChanged;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback onRemove;
  final VoidCallback onClose;
  final VoidCallback? onUpload;
  final bool uploading;

  const ReportPhotoSidebar({
    super.key,
    required this.album,
    required this.fill,
    required this.selected,
    required this.loadPhoto,
    required this.onSwap,
    required this.onCaptionChanged,
    required this.onRemove,
    required this.onClose,
    this.selectedNumber,
    this.onMoveLeft,
    this.onMoveRight,
    this.onUpload,
    this.uploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final used = photoPathsIn(fill).toSet();
    final photos = <AlbumPhoto>[...album];
    // Photos in the report that aren't in the album (uploaded) still show.
    for (final p in used) {
      if (!photos.any((a) => a.path == p)) photos.add(AlbumPhoto(path: p));
    }
    final current = selected == null ? null : fillGet(fill, selected!.imagePath)?.toString();

    return Container(
      width: 340,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: selected == null ? _album(photos, used) : _photo(context, photos, used, current),
      ),
    );
  }

  Widget _upload() => OutlinedButton.icon(
        key: const ValueKey('sidebar-upload'),
        onPressed: uploading ? null : onUpload,
        icon: uploading
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
            : const Icon(Icons.upload_rounded, size: 16),
        label: const Text('Upload'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: _line),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  List<Widget> _album(List<AlbumPhoto> photos, Set<String> used) => [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
                  const SizedBox(height: 2),
                  Text('${photos.length} from this inspection', style: const TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ),
            if (onUpload != null) _upload(),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Select a photo in the report to swap, move or remove it.', style: TextStyle(fontSize: 13, color: Color(0xFF495057), height: 1.4)),
        const SizedBox(height: 14),
        _grid(photos, used, null, null),
      ];

  List<Widget> _photo(BuildContext context, List<AlbumPhoto> photos, Set<String> used, String? current) {
    final captionPath = selected!.captionPath;
    final caption = captionPath == null ? null : valueText(fillGet(fill, captionPath));
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('sidebar-all-photos'),
          onPressed: onClose,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('All photos'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF495057), padding: EdgeInsets.zero),
        ),
      ),
      const SizedBox(height: 4),
      Text(selectedNumber == null ? 'Photo' : 'Photo $selectedNumber', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
      if (captionPath != null) ...[
        const SizedBox(height: 14),
        const Text('Caption', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF495057))),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('caption-${selected!.id}'),
          initialValue: caption,
          minLines: 1,
          maxLines: 4,
          onChanged: onCaptionChanged,
          style: const TextStyle(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF1F3F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: reportSelectionBlue)),
          ),
        ),
      ],
      const SizedBox(height: 14),
      Row(
        children: [
          if (selected!.listPath != null) ...[
            Expanded(child: _action('Move left', onMoveLeft)),
            const SizedBox(width: 8),
            Expanded(child: _action('Move right', onMoveRight)),
            const SizedBox(width: 8),
          ],
          Expanded(child: _action('Remove', onRemove, danger: true)),
        ],
      ),
      const SizedBox(height: 16),
      const Divider(height: 1, color: Color(0xFFE9ECEF)),
      const SizedBox(height: 14),
      Row(
        children: [
          const Expanded(child: Text('Swap with', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink))),
          if (onUpload != null) _upload(),
        ],
      ),
      const SizedBox(height: 10),
      _grid(photos, used, current, onSwap),
      const SizedBox(height: 10),
      const Text('Click a photo to put it in this spot. The caption stays.', style: TextStyle(fontSize: 12, color: _muted)),
    ];
  }

  Widget _action(String label, VoidCallback? onTap, {bool danger = false}) => OutlinedButton(
        key: ValueKey('photo-$label'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? const Color(0xFFE03131) : _ink,
          side: BorderSide(color: danger ? const Color(0xFFFFC9C9) : _line),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      );

  Widget _grid(List<AlbumPhoto> photos, Set<String> used, String? current, ValueChanged<String>? onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < photos.length; i++)
          _AlbumTile(
            key: ValueKey('album-$i'),
            label: 'Album photo ${i + 1}',
            photo: photos[i],
            load: loadPhoto,
            badge: photos[i].path == current ? 'Current' : (used.contains(photos[i].path) ? 'In report' : null),
            current: photos[i].path == current,
            onTap: onTap == null || photos[i].path == current ? null : () => onTap(photos[i].path),
          ),
      ],
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final AlbumPhoto photo;
  final String label;
  final Future<Uint8List> Function(String path) load;
  final String? badge;
  final bool current;
  final VoidCallback? onTap;

  const _AlbumTile({super.key, required this.photo, required this.label, required this.load, this.badge, this.current = false, this.onTap});

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  late Future<Uint8List> _bytes = widget.load(widget.photo.path);
  bool _hover = false;

  @override
  void didUpdateWidget(_AlbumTile old) {
    super.didUpdateWidget(old);
    if (old.photo.path != widget.photo.path) _bytes = widget.load(widget.photo.path);
  }

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 94,
      height: 72,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: widget.current
            ? Border.all(color: reportSelectionBlue, width: 3)
            : (_hover && widget.onTap != null ? Border.all(color: _ink, width: 2) : null),
      ),
      decoration: BoxDecoration(color: const Color(0xFFE9ECEF), borderRadius: BorderRadius.circular(6)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snap) => snap.hasData
                ? Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true)
                : const Center(child: Icon(Icons.image_outlined, size: 20, color: Color(0xFFADB5BD))),
          ),
          if (widget.badge != null)
            Positioned(
              left: 5,
              top: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: widget.current ? reportSelectionBlue : _ink, borderRadius: BorderRadius.circular(4)),
                child: Text(widget.badge!, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ),
          if (_hover && widget.onTap != null)
            Positioned(
              bottom: 5,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4)),
                  child: const Text('Swap in', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      label: '${widget.label}${widget.badge == null ? '' : ' (${widget.badge})'}',
      button: widget.onTap != null,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.photo.caption ?? '',
        child: MouseRegion(
        cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(onTap: widget.onTap, child: tile),
        ),
      ),
    );
  }
}
