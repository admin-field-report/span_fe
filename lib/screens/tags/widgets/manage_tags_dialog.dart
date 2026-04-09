import 'package:flutter/material.dart';
import '../../../../widgets/form_components/text_field.dart';
import '../../../../widgets/button/button.dart';
import '../../../../widgets/form_components/color_picker_field.dart';
import '../controllers/tag_controller.dart';
import '../../../../models/tag_models.dart';
import 'inline_selection_filter.dart';

class ManageTagsDialog extends StatefulWidget {
  final TagController controller;
  final Set<String> initialSelectedIds;

  final Future<bool> Function(List<String> selectedIds, List<Map<String, String>> newTags) onSave;

  const ManageTagsDialog({
    Key? key,
    required this.controller,
    required this.initialSelectedIds,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends State<ManageTagsDialog> {
  late Set<String> _selectedTagIds;
  
  final _formKey = GlobalKey<FormState>();
  final _newTagNameController = TextEditingController();
  Color _newTagColor = const Color(0xFFC9D647);
  final List<Map<String, String>> _newlyCreatedTags = [];
  
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedTagIds = Set.from(widget.initialSelectedIds);
  }

  String _colorToHex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  Color _hexToColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));

  void _addNewTagToLocalList() {
    if (_newTagNameController.text.trim().isNotEmpty) {
      setState(() {
        _newlyCreatedTags.add({
          "name": _newTagNameController.text.trim(),
          "color": _colorToHex(_newTagColor),
        });
        _newTagNameController.clear();
      });
    }
  }

  Future<void> _onSave() async {
    setState(() => _isSubmitting = true);

    final success = await widget.onSave(
      _selectedTagIds.toList(),
      _newlyCreatedTags,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context); 
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: theme.colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Manage Tags", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close), 
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // --- BODY ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Create & Add New Tags", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 12),
                            
                            AbsorbPointer(
                              absorbing: _isSubmitting,
                              child: FormControlTextField(
                                controller: _newTagNameController,
                                hintText: "New tag name...",
                                prefixIcon: Icons.local_offer_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: AbsorbPointer(
                                    absorbing: _isSubmitting,
                                    child: ColorPickerField(
                                      currentColor: _newTagColor,
                                      onColorChanged: (c) => setState(() => _newTagColor = c),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Button(
                                  label: "Add Tag",
                                  icon: Icons.add,
                                  variant: ButtonVariant.filled,
                                  onPressed: _isSubmitting ? null : _addNewTagToLocalList,
                                ),
                              ],
                            ),
                            
                            if (_newlyCreatedTags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _newlyCreatedTags.map((t) {
                                  final tagColor = _hexToColor(t["color"]!);
                                  return Chip(
                                    label: Text(t["name"]!, style: TextStyle(color: tagColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                    backgroundColor: tagColor.withOpacity(0.1),
                                    side: BorderSide(color: tagColor.withOpacity(0.5)),
                                    deleteIconColor: tagColor,
                                    onDeleted: _isSubmitting ? null : () => setState(() => _newlyCreatedTags.remove(t)),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    const Text("Select Existing Tags", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    
                    // 🚀 2. EXISTING TAG SELECTION
                    AbsorbPointer(
                      absorbing: _isSubmitting,
                      child: SizedBox(
                        height: 300, 
                        child: InlineSelectionFilter<AppTag>(
                          allItems: widget.controller.globalTags, 
                          selectedIds: _selectedTagIds, 
                          getName: (t) => t.name, 
                          getId: (t) => t.id,
                          onToggle: (id, isSelected) => setState(() => isSelected ? _selectedTagIds.add(id) : _selectedTagIds.remove(id)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            
            // --- FOOTER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    label: "Cancel", 
                    variant: ButtonVariant.outline, 
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: _isSubmitting ? "Saving..." : "Save Changes",
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _onSave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
