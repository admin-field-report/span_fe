import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data'; 
import 'dart:convert';
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/form_components/text_area_field.dart';

class PropertiesPanel extends StatefulWidget {
  final DrawingObject? activeObject;
  final List<ProjectTag> availableTags;
  final bool isLoadingTags;
  
  final String? inspectionDescription;
  final List<String>? inspectionTagIds;
  final List<dynamic>? inspectionImageUrls;
  
  final ValueChanged<String>? onInspectionDescriptionChanged;
  final ValueChanged<List<String>>? onInspectionTagsChanged;

  final VoidCallback onUpdate;
  final VoidCallback onClose;
  final Future<void> Function(String fileName, Uint8List bytes) onImageUpload; 
  final Future<void> Function(String s3Key) onImageDelete;
  final Function(String s3Key) onImageTap;

  final bool allowImageUpload;
  final bool showImageSection; 
  final bool isInspectionLevel; // 🚀 NEW: Controls if "Inspection Details" should render when no object is selected
   
  const PropertiesPanel({
    super.key,
    required this.activeObject,
    required this.availableTags,
    required this.isLoadingTags,
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
    this.showImageSection = true, 
    this.isInspectionLevel = true, // 🚀 Default is true
  });

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  late TextEditingController _descController;
  DrawingObject? _trackedObject;
  
  bool _isUploading = false; 
  final Set<String> _deletingKeys = {};

  final Map<String, Uint8List> _imageCache = {};

  String get _currentDescription => widget.activeObject != null 
      ? (widget.activeObject!.description ?? "") 
      : (widget.inspectionDescription ?? "");

  List<String> get _currentTagIds => widget.activeObject != null 
      ? (widget.activeObject!.tagIds ?? []) 
      : (widget.inspectionTagIds ?? []);

  List<dynamic> get _currentImageUrls => widget.activeObject != null 
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

      _imageCache.clear();
    }
  }

  @override
  void dispose() {
    _descController.removeListener(_onTextChanged);
    _descController.dispose();
    _imageCache.clear();
    super.dispose();
  }

  Uint8List _getDecodedBytes(String key, String base64Str) {
    if (_imageCache.containsKey(key)) return _imageCache[key]!;
    
    String cleanBase64 = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
    Uint8List bytes = base64Decode(cleanBase64);
    _imageCache[key] = bytes;
    return bytes;
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

  void _showImageOptions() {
    if (kIsWeb) {
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

  Future<void> _pickAndUploadImage({required bool useCamera}) async {
    try {
      Uint8List? fileBytes;
      String fileName = "";

      if (useCamera) {
        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
        
        if (photo != null) {
          fileBytes = await photo.readAsBytes();
          fileName = photo.name;
        }
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true, 
        );

        if (result != null && result.files.single.bytes != null) {
          fileBytes = result.files.single.bytes;
          fileName = result.files.single.name;
        }
      }

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
    try {
      await widget.onImageDelete(s3Key);
      
      if (widget.activeObject != null && widget.activeObject!.imageUrls != null) {
        widget.activeObject!.imageUrls!.removeWhere((item) {
          if (item is String) return item == s3Key;
          if (item is Map) return item['image_url'] == s3Key || item['key'] == s3Key;
          return false;
        });
      }
      
      _imageCache.remove(s3Key);
      widget.onUpdate();
    } catch (e) {
      debugPrint("Error deleting image: $e");
    } finally {
      if (mounted) setState(() => _deletingKeys.remove(s3Key));
    }
  }

  Widget _buildFallbackIcon(ThemeData theme) {
    return Column(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 🚀 THE FIX: If no object is selected AND we are not at the inspection level, show the placeholder!
    if (widget.activeObject == null && !widget.isInspectionLevel) {
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
                  
                  if (widget.availableTags.isEmpty && !widget.isLoadingTags) 
                    Text("No tags available.", style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),

                  if (widget.isLoadingTags) 
                    const Center(child: CircularProgressIndicator()),
                  
                  Wrap(
                    spacing: 8, 
                    runSpacing: 8,
                    children: widget.availableTags.map((tag) {
                      final isSelected = tagIds.contains(tag.id);
                      final Color foregroundColor = isSelected ? Colors.white : tag.color;

                      return InkWell(
                        onTap: () => _toggleTag(tag.id), 
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? tag.color : Colors.transparent,
                            border: Border.all(
                              color: tag.color,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              isSelected
                                  ? Icon(Icons.check, size: 14, color: foregroundColor)
                                  : Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: tag.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                              const SizedBox(width: 6),
                              Text(
                                tag.name,
                                style: TextStyle(
                                  color: foregroundColor,
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  if (widget.showImageSection) ...[
                    if (widget.allowImageUpload || imageUrls.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Text("Attached Images", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                    ],

                    if (widget.allowImageUpload) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isUploading ? null : _showImageOptions,
                          icon: _isUploading 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.add_a_photo_outlined, size: 18), 
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
                          final dynamic imgData = imageUrls[index];
                          String s3Key = '';
                          String? base64Preview;

                          if (imgData is String) {
                            s3Key = imgData;
                          } else if (imgData is Map) {
                            s3Key = imgData['image_url'] ?? imgData['key'] ?? '';
                            base64Preview = imgData['preview_image'];
                          }

                          final bool isDeleting = _deletingKeys.contains(s3Key);

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
                                    onTap: () => widget.onImageTap(s3Key), 
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: (base64Preview != null && base64Preview.isNotEmpty)
                                        ? Image.memory(
                                            _getDecodedBytes(s3Key, base64Preview),
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(theme),
                                          )
                                        : _buildFallbackIcon(theme),
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
                  ],

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