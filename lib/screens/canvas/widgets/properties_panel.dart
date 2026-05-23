import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data'; 
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/form_components/text_area_field.dart';

class PropertiesPanel extends StatefulWidget {
  final DrawingObject? activeObject;
  final List<ProjectTag> availableTags;
  
  final String? inspectionDescription;
  final List<String>? inspectionTagIds;
  final List<String>? inspectionImageUrls;
  
  final ValueChanged<String>? onInspectionDescriptionChanged;
  final ValueChanged<List<String>>? onInspectionTagsChanged;

  final VoidCallback onUpdate;
  final VoidCallback onClose;
  final Future<void> Function(String fileName, Uint8List bytes) onImageUpload; 
  final Future<void> Function(String s3Key) onImageDelete;
  final Function(String s3Key, String imageUrl) onImageTap;

  final bool allowImageUpload;
   
  const PropertiesPanel({
    super.key,
    required this.activeObject,
    required this.availableTags,
    
    this.inspectionDescription,
    this.inspectionTagIds,
    this.inspectionImageUrls,
    this.onInspectionDescriptionChanged,
    this.onInspectionTagsChanged,

    required this.onUpdate,
    required this.onClose,
    required this.onImageUpload,
    required this.onImageDelete,
    required this.onImageTap,
    this.allowImageUpload = true,
  });

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  late TextEditingController _descController;
  DrawingObject? _trackedObject;
  
  bool _isUploading = false; 
  final Set<String> _deletingKeys = {};

  String get _currentDescription => widget.activeObject != null 
      ? (widget.activeObject!.description ?? "") 
      : (widget.inspectionDescription ?? "");

  List<String> get _currentTagIds => widget.activeObject != null 
      ? (widget.activeObject!.tagIds ?? []) 
      : (widget.inspectionTagIds ?? []);

  List<String> get _currentImageUrls => widget.activeObject != null 
      ? (widget.activeObject!.imageUrls ?? []) 
      : (widget.inspectionImageUrls ?? []);

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: _currentDescription);
    _descController.addListener(_onTextChanged);
    _trackedObject = widget.activeObject;
  }

  void _onTextChanged() {
    if (widget.activeObject != null) {
      if (widget.activeObject!.description != _descController.text) {
        widget.activeObject!.description = _descController.text;
        widget.onUpdate(); 
      }
    } else {
      if (widget.inspectionDescription != _descController.text) {
        widget.onInspectionDescriptionChanged?.call(_descController.text);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeObject != oldWidget.activeObject || 
       (widget.activeObject == null && widget.inspectionDescription != oldWidget.inspectionDescription)) {
      
      _trackedObject = widget.activeObject;
      _descController.removeListener(_onTextChanged);
      _descController.text = _currentDescription;
      _descController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _descController.removeListener(_onTextChanged);
    _descController.dispose();
    super.dispose();
  }

  void _toggleTag(String tagId) {
    if (widget.activeObject != null) {
      widget.activeObject!.tagIds ??= [];
      setState(() {
        if (widget.activeObject!.tagIds!.contains(tagId)) {
          widget.activeObject!.tagIds!.remove(tagId);
        } else {
          widget.activeObject!.tagIds!.add(tagId);
        }
      });
      widget.onUpdate();
    } else {
      List<String> updatedTags = List.from(_currentTagIds);
      if (updatedTags.contains(tagId)) {
        updatedTags.remove(tagId);
      } else {
        updatedTags.add(tagId);
      }
      widget.onInspectionTagsChanged?.call(updatedTags);
    }
  }

  // 🚀 NEW: Shows the bottom sheet to pick between Camera and Gallery
  void _showImageOptions() {
    if (kIsWeb) {
      // Skip the bottom sheet on web and just open the file explorer
      _pickAndUploadImage(useCamera: false);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  "Add Photo",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(useCamera: true);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Upload from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(useCamera: false);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // 🚀 REVISED: Routes intelligently between ImagePicker and FilePicker
  Future<void> _pickAndUploadImage({required bool useCamera}) async {
    try {
      Uint8List? fileBytes;
      String fileName = "";

      if (useCamera) {
        // Trigger the native mobile camera
        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
        
        if (photo != null) {
          fileBytes = await photo.readAsBytes();
          fileName = photo.name;
        }
      } else {
        // Trigger the standard gallery/file explorer
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true, 
        );

        if (result != null && result.files.single.bytes != null) {
          fileBytes = result.files.single.bytes;
          fileName = result.files.single.name;
        }
      }

      // If a file was successfully captured/selected, upload it!
      if (fileBytes != null) {
        setState(() => _isUploading = true);
        await widget.onImageUpload(fileName, fileBytes);
        widget.onUpdate();
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleDeleteImage(String s3Key) async {
    setState(() => _deletingKeys.add(s3Key));
    await widget.onImageDelete(s3Key);
    if (mounted) setState(() => _deletingKeys.remove(s3Key));
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (widget.activeObject == null && !widget.allowImageUpload) {
      return Container(
        width: 300,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface, 
          border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant))
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Select an object to edit properties", 
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        )
      );
    }

    final imageUrls = _currentImageUrls; 
    final tagIds = _currentTagIds;       

    return Container(
      width: 300,
      decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  Text(
                    widget.activeObject != null ? "Object Details" : "Inspection Details",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, 
                      color: widget.activeObject != null ? theme.colorScheme.primary : theme.colorScheme.secondary
                    ),
                  ),
                  const Divider(height: 24),

                  Text("Description", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FormControlTextArea(controller: _descController, hintText: "Enter description here...", minLines: 4),
                  
                  const SizedBox(height: 24),

                  Text("Tags", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (widget.availableTags.isEmpty) Text("No tags available.", style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: widget.availableTags.map((tag) {
                      final isSelected = tagIds.contains(tag.id);
                      return FilterChip(
                        label: Text(tag.name, style: TextStyle(fontSize: 12, color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)), 
                        selected: isSelected, 
                        selectedColor: tag.color, 
                        checkmarkColor: theme.colorScheme.onPrimary, 
                        backgroundColor: tag.color.withOpacity(0.1), 
                        side: BorderSide(color: tag.color.withOpacity(isSelected ? 0.0 : 0.5)), 
                        onSelected: (_) => _toggleTag(tag.id)
                      );
                    }).toList(),
                  ),

                  if (widget.allowImageUpload) ...[
                    const SizedBox(height: 32),
                    Text("Attached Images", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        // 🚀 REVISED: This now opens the Bottom Sheet!
                        onPressed: _isUploading ? null : _showImageOptions,
                        icon: _isUploading 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_a_photo_outlined, size: 18), // Switched to a camera/add icon
                        label: Text(_isUploading ? "Uploading..." : "Upload Image"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  if (imageUrls.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, 
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.0, 
                      ),
                      itemCount: imageUrls.length,
                      itemBuilder: (context, index) {
                        final String s3Key = imageUrls[index];
                        final bool isDeleting = _deletingKeys.contains(s3Key);
                        
                        final String imageUrl = "https://dev-field-report-canvas-tool-image.s3.us-east-1.amazonaws.com/$s3Key";

                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3), 
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque, 
                                  onTap: () => widget.onImageTap(s3Key, imageUrl), 
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.image, color: theme.colorScheme.primary.withOpacity(0.5), size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Image\nAttached", 
                                        textAlign: TextAlign.center, 
                                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              if (isDeleting)
                                Container(
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
                                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary))),
                                )
                              else
                                Positioned(
                                  top: 4, right: 4,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _handleDeleteImage(s3Key),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                        child: const Icon(Icons.delete_outline, color: Colors.white, size: 14),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}