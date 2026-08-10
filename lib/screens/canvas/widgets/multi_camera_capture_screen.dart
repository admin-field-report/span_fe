import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../widgets/button/button.dart';

class _CapturedPhoto {
  final String id;
  final String fileName;
  final Uint8List bytes;

  _CapturedPhoto({required this.id, required this.fileName, required this.bytes});
}

/// Full-screen camera capture flow (mobile only).
/// Lets the user take multiple photos in a row, review and remove any
/// before committing, then upload them all together.
class MultiCameraCaptureScreen extends StatefulWidget {
  final Future<void> Function(List<Map<String, dynamic>> photos, void Function(int uploaded, int total) onProgress)
      onBulkUpload;

  const MultiCameraCaptureScreen({super.key, required this.onBulkUpload});

  @override
  State<MultiCameraCaptureScreen> createState() => _MultiCameraCaptureScreenState();
}

class _MultiCameraCaptureScreenState extends State<MultiCameraCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<_CapturedPhoto> _photos = [];

  bool _isCapturing = false;
  bool _isUploading = false;
  int _photoCounter = 0;
  int _uploadedCount = 0;
  int _uploadTotal = 0;

  Future<void> _capturePhoto() async {
    setState(() => _isCapturing = true);
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        _photoCounter++;
        setState(() {
          _photos.add(_CapturedPhoto(id: 'photo_$_photoCounter', fileName: photo.name, bytes: bytes));
        });
      }
    } catch (e) {
      debugPrint("Error capturing photo: $e");
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _removePhoto(String id) {
    setState(() => _photos.removeWhere((p) => p.id == id));
  }

  Future<void> _uploadAll() async {
    if (_photos.isEmpty || _isUploading) return;

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _uploadTotal = _photos.length;
    });

    try {
      final photosPayload = _photos
          .map((p) => {"fileName": p.fileName, "bytes": p.bytes})
          .toList();

      await widget.onBulkUpload(photosPayload, (uploaded, total) {
        if (mounted) {
          setState(() {
            _uploadedCount = uploaded;
            _uploadTotal = total;
          });
        }
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Error uploading photos: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload some photos. Please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_photos.isEmpty || _isUploading) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Discard photos?"),
        content: Text("You have ${_photos.length} photo${_photos.length == 1 ? '' : 's'} that ${_photos.length == 1 ? 'hasn\'t' : 'haven\'t'} been uploaded yet."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Keep Editing")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("Discard", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(_photos.isEmpty ? "Capture Photos" : "Capture Photos (${_photos.length})"),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Button(
                label: "Upload",
                icon: Icons.cloud_upload_outlined,
                isLoading: _isUploading,
                onPressed: (_photos.isEmpty || _isUploading) ? null : _uploadAll,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              _photos.isEmpty ? _buildEmptyState(theme) : _buildPhotoGrid(theme),
              if (_isUploading) _buildUploadProgressOverlay(theme),
            ],
          ),
        ),
        floatingActionButton: Button(
          label: _photos.isEmpty ? "Take Photo" : "Take Another",
          icon: Icons.camera_alt,
          isLoading: _isCapturing,
          onPressed: _isCapturing || _isUploading ? null : _capturePhoto,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildUploadProgressOverlay(ThemeData theme) {
    final double progress = _uploadTotal == 0 ? 0 : _uploadedCount / _uploadTotal;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Uploading photos",
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "$_uploadedCount of $_uploadTotal uploaded",
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: 64, color: theme.colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              "No photos yet",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap the camera button below to start capturing. You can take as many photos as you need and upload them all together.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGrid(ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: _photos.length,
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.memory(photo.bytes, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _isUploading ? null : () => _removePhoto(photo.id),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
