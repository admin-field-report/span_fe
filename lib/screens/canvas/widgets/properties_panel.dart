import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data'; 
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/form_components/text_area_field.dart';

class PropertiesPanel extends StatefulWidget {
  final DrawingObject? activeObject;
  final List<ProjectTag> availableTags;
  
  // 🔽 NEW: Inspection Level Data
  final String? inspectionDescription;
  final List<String>? inspectionTagIds;
  final List<String>? inspectionImageUrls;
  
  // 🔽 NEW: Inspection Level Callbacks
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
    
    // Inspection props
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

  // 🚀 DYNAMIC GETTERS: These decide which data pool to read from automatically
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
        widget.onUpdate(); // Trigger canvas update
      }
    } else {
      // 🚀 Inspection Level Update
      if (widget.inspectionDescription != _descController.text) {
        widget.onInspectionDescriptionChanged?.call(_descController.text);
      }
    }
  }

  @override
  void didUpdateWidget(covariant PropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Re-bind the controller text if the active object changes OR if the inspection data changes while no object is selected
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
      // 🚀 Inspection Level Update
      List<String> updatedTags = List.from(_currentTagIds);
      if (updatedTags.contains(tagId)) {
        updatedTags.remove(tagId);
      } else {
        updatedTags.add(tagId);
      }
      widget.onInspectionTagsChanged?.call(updatedTags);
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, 
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() => _isUploading = true);
        await widget.onImageUpload(result.files.single.name, result.files.single.bytes!);
        // The parent handles where the image URL gets saved based on its own state!
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
    final imageUrls = _currentImageUrls; // Read from dynamic getter
    final tagIds = _currentTagIds;       // Read from dynamic getter

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
                  
                  // 🌟 DYNAMIC CONTEXT HEADER 🌟
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
                        onPressed: _isUploading ? null : _pickAndUploadImage,
                        icon: _isUploading 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: Text(_isUploading ? "Uploading..." : "Upload Image"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // 🌟 DYNAMIC GALLERY GRID VIEW 🌟
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
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () => widget.onImageTap(s3Key, imageUrl), 
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_not_supported_outlined, color: theme.colorScheme.onSurfaceVariant),
                                        const SizedBox(height: 4),
                                        Text("Preview\nUnavailable", textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
                                      ],
                                    ),
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
                                  child: GestureDetector(
                                    onTap: () => _handleDeleteImage(s3Key),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 14),
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