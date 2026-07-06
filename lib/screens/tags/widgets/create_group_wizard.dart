import 'package:flutter/material.dart';
import 'package:field_report_fe/services/toast_service.dart';
import '../../../../widgets/form_components/text_field.dart';
import '../../../../widgets/button/button.dart';
import '../../../../widgets/form_components/color_picker_field.dart';
import '../controllers/tag_controller.dart';
import '../../../../models/tag_models.dart';
import 'inline_selection_filter.dart';

class CreateGroupWizard extends StatefulWidget {
  final TagController controller;
  
  const CreateGroupWizard({super.key, required this.controller});

  @override
  State<CreateGroupWizard> createState() => _CreateGroupWizardState();
}

class _CreateGroupWizardState extends State<CreateGroupWizard> {
  int _currentStep = 0;
  bool _isSubmitting = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final _newTagNameController = TextEditingController();
  Color _newTagColor = const Color(0xFFC9D647);
  final List<Map<String, String>> _newlyCreatedTags = [];
  
  String _colorToHex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  Color _hexToColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
  
  final Set<String> _selectedTagIds = {};
  // final Set<String> _selectedTemplateIds = {}; // 🚀 Commented out
  
  // 🚀 NEW: State to hold the footer validation message
  String? _validationError; 

  void _onStepContinue() async {
    // Clear any previous error messages when they try to continue
    setState(() => _validationError = null);

    if (_currentStep == 0 && !(_formKey.currentState?.validate() ?? false)) return;

    if (_currentStep == 1) {
      if (_selectedTagIds.isEmpty && _newlyCreatedTags.isEmpty) {
        // 🚀 NEW: Set the inline validation message instead of just a Toast
        setState(() => _validationError = "Please select or create at least one tag.");
        return; 
      }
    }

    if (_currentStep < 1) {
      setState(() => _currentStep += 1);
    } else {
      setState(() => _isSubmitting = true);
      final newGroupId = await widget.controller.createTagGroup(
        name: _nameController.text.trim(), 
        tagIds: _selectedTagIds.toList(), 
        // templateIds: _selectedTemplateIds.toList(), // 🚀 Commented out payload
        newTags: _newlyCreatedTags,
      );
      if (!mounted) return;

     if (newGroupId != null) {
        Navigator.pop(context, newGroupId);
        ToastService.show(context, message: "Group created successfully", type: ToastType.success);
      } else {
        ToastService.show(context, message: "Failed to create group", type: ToastType.error);
      }
      setState(() => _isSubmitting = false);
    }
  }

  void _onStepCancel() {
    // 🚀 Clear error when navigating back
    setState(() => _validationError = null); 
    if (_currentStep > 0) setState(() => _currentStep -= 1);
    else Navigator.pop(context);
  }

  void _addNewTagToLocalList() {
    if (_newTagNameController.text.trim().isNotEmpty) {
      setState(() {
        _newlyCreatedTags.add({
          "name": _newTagNameController.text.trim(),
          "color": _colorToHex(_newTagColor),
        });
        _newTagNameController.clear();
        // 🚀 Clear error if they fix the issue by adding a tag
        _validationError = null; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // final isDesktop = AppResponsive.isDesktopScreen(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: Stepper(
              type: StepperType.horizontal, 
              currentStep: _currentStep,
              elevation: 0,
              controlsBuilder: (context, details) => const SizedBox.shrink(),
              steps: [
                Step(
                  title: const Text("Details"), 
                  isActive: _currentStep >= 0, 
                  state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Group Name", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      FormControlTextField(controller: _nameController, hintText: "Enter group name...", prefixIcon: Icons.folder_outlined, validator: (val) => (val == null || val.trim().isEmpty) ? "Group name is required" : null),
                    ],
                  ),
                ),
                Step(
                  title: const Text("Tags"), 
                  isActive: _currentStep >= 1, 
                  state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Create & Add New Tags", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 12),
                            
                            FormControlTextField(
                              controller: _newTagNameController,
                              hintText: "New tag name...",
                              prefixIcon: Icons.local_offer_outlined,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ColorPickerField(
                                    label: 'Tag Color',
                                    currentColor: _newTagColor,
                                    onColorChanged: (c) => setState(() => _newTagColor = c),
                                    showOpacity: false,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Button(
                                  label: "Add Tag",
                                  icon: Icons.add,
                                  variant: ButtonVariant.filled,
                                  onPressed: _addNewTagToLocalList,
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
                                    onDeleted: () => setState(() {
                                      _newlyCreatedTags.remove(t);
                                    }),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      const Text("Select Existing Tags", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      
                      SizedBox(
                        height: 350,
                        child: InlineSelectionFilter<AppTag>(
                          allItems: widget.controller.globalTags, 
                          selectedIds: _selectedTagIds, 
                          getName: (t) => t.name, 
                          getId: (t) => t.id,
                          onToggle: (id, isSelected) => setState(() {
                            isSelected ? _selectedTagIds.add(id) : _selectedTagIds.remove(id);
                            // 🚀 Clear error if they fix the issue by selecting a tag
                            _validationError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                /* 🚀 COMMENTED OUT TEMPLATES STEP
                Step(
                  title: const Text("Templates"), isActive: _currentStep >= 2,
                  content: SizedBox(
                    height: 350,
                    child: InlineSelectionFilter<AppTemplate>(
                      allItems: widget.controller.globalTemplates, selectedIds: _selectedTemplateIds, getName: (t) => t.name, getId: (t) => t.id,
                      onToggle: (id, isSelected) => setState(() => isSelected ? _selectedTemplateIds.add(id) : _selectedTemplateIds.remove(id)),
                    ),
                  ),
                ),
                */
              ],
            ),
          ),
          
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  // 🚀 NEW: Inline Validation Error Message
                  Expanded(
                    child: _validationError != null 
                        ? Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _validationError!,
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 16),
                  
                  // Buttons pushed to the right
                  Button(
                    label: _currentStep == 0 ? "Cancel" : "Back", 
                    variant: ButtonVariant.outline, 
                    onPressed: _isSubmitting ? null : _onStepCancel, 
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: _currentStep == 1 
                        ? (_isSubmitting ? "Creating..." : "Create Group") 
                        : "Continue", 
                    isLoading: _currentStep == 1 && _isSubmitting,
                    variant: ButtonVariant.filled,
                    onPressed: _isSubmitting ? null : _onStepContinue, 
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}