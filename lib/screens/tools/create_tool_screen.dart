import 'package:field_report_fe/services/toast_service.dart';
import 'package:field_report_fe/utils/utils.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../widgets/button/button.dart';
import '../../../widgets/canvas/canvas.dart';
import '../../../widgets/form_components/text_field.dart';
import '../../../widgets/form_components/select_field.dart';
import '../../../widgets/search_field/search_field.dart';
import './models/tool_group.dart';
import '../../../models/tag_models.dart';
import './controllers/tool_controller.dart';

// Wrapper for your custom Select field
class GroupSelectableItem implements SelectableItem<String> {
  final ToolGroup group;
  GroupSelectableItem(this.group);
  @override
  String get id => group.id;
  @override
  String get name => group.name;
}

class CreateToolScreen extends StatefulWidget {
  final List<ToolGroup> availableGroups;
  final List<AppTagGroup> availableTagGroups;
  final bool isTagGroupsLoading;
  final bool isToolGroupsLoading; // 🚀 ADDED: Loading state for tool groups
  final String? initialGroupId;

  const CreateToolScreen({
    super.key, 
    required this.availableGroups,
    required this.availableTagGroups,
    this.isTagGroupsLoading = false,
    this.isToolGroupsLoading = false, // Default to false
    this.initialGroupId,
  });

  @override
  State<CreateToolScreen> createState() => _CreateToolScreenState();
}

class _CreateToolScreenState extends State<CreateToolScreen> {
  final GlobalKey<CanvasState> _canvasKey = GlobalKey<CanvasState>();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final ToolController _toolController = ToolController();
  bool _isLoading = false;
  
  String? _selectedGroupId;
  final Set<String> _selectedTagIds = {};

  @override
  void initState() {
    super.initState();
    _checkAndSetInitialGroup();
  }

  // 🚀 FIX: This acts as the "Listener". It fires whenever the parent passes new data.
  @override
  void didUpdateWidget(CreateToolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the available groups list changed (e.g., API finished loading), check again
    if (widget.availableGroups != oldWidget.availableGroups && _selectedGroupId == null) {
      _checkAndSetInitialGroup();
    }
  }

  // Helper method to set the group safely
  void _checkAndSetInitialGroup() {
    if (widget.initialGroupId != null && widget.availableGroups.any((g) => g.id == widget.initialGroupId)) {
      setState(() {
        _selectedGroupId = widget.initialGroupId;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveTool() async {
    if (!_formKey.currentState!.validate()) return;

    final canvasState = _canvasKey.currentState;
    if (canvasState == null || canvasState.objects.isEmpty) {
      ToastService.show(context, message: "Please draw a tool on the canvas before saving.", type: ToastType.error);
      return;
    }

    setState(() => _isLoading = true);

    String toolName = _nameController.text.trim();
    String canvasJson = jsonEncode(canvasState.objects.map((e) => e.toJson()).toList());

    bool success = await _toolController.createTool(
      name: toolName,
      groupId: _selectedGroupId!,
      canvasJson: canvasJson,
      tagIds: _selectedTagIds.toList(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ToastService.show(context, message: "Tool '$toolName' created successfully!", type: ToastType.success);
      Navigator.pop(context, true); 
    } else {
      ToastService.show(context, message: "Failed to create tool. Please try again.", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool isMobile = AppResponsive.isMobileScreen(context);
            Widget formFields = _buildFormFields(theme);
            Widget stickyFooter = _buildStickyFooter(theme);

            if (isMobile) {
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCanvasSection(theme, isExpanded: false),
                          const SizedBox(height: 32),
                          formFields,
                        ],
                      ),
                    ),
                  ),
                  stickyFooter,
                ],
              );
            } else {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 15.0, 0, 0),
                      child: _buildCanvasSection(theme, isExpanded: true),
                    ),
                  ),
                  Container(width: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(15.0),
                            child: formFields,
                          ),
                        ),
                        stickyFooter,
                      ],
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildCanvasSection(ThemeData theme, {required bool isExpanded}) {
    Widget canvasContainer = Container(
      width: double.infinity, 
      height: isExpanded ? null : 500, 
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Canvas(
        key: _canvasKey,
        leftActions: const [], rightActions: const [],
      ),
    );

    if (isExpanded) {
      canvasContainer = Expanded(child: canvasContainer);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 10),
            const Text("1. Draw Tool", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text("Required", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 12),
        canvasContainer, 
      ],
    );
  }

  Widget _buildFormFields(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("2. Tool Details", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          const Text("Tool Name *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FormControlTextField(
            controller: _nameController,
            hintText: "Enter tool name",
            prefixIcon: Icons.edit_outlined,
            validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter a name' : null,
          ),
          const SizedBox(height: 20),

          const Text("Tool Group *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          
          // 🚀 SHOW LOADER OR SELECT DROPDOWN FOR TOOL GROUPS
          if (widget.isToolGroupsLoading)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18, 
                    height: 18, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)
                  ),
                  const SizedBox(width: 12),
                  Text("Loading groups...", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
                ],
              ),
            )
          else
            FormControlSelect<String>(
              value: _selectedGroupId,
              hintText: widget.availableGroups.isEmpty ? "No groups found" : "Select a group",
              prefixIcon: Icons.folder_outlined,
              items: widget.availableGroups.map((g) => GroupSelectableItem(g)).toList(),
              onChanged: (val) => setState(() => _selectedGroupId = val),
              validator: (value) => (value == null || value.isEmpty) ? 'Please select a group' : null,
            ),
            
          const SizedBox(height: 32),

          const Text("3. Tags (Optional)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (widget.isTagGroupsLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else if (widget.availableTagGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  "No tag groups available.",
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          else
            ...widget.availableTagGroups.map((tagGroup) {
              return Container(
                width: double.infinity, 
                margin: const EdgeInsets.only(bottom: 16.0), 
                padding: const EdgeInsets.all(16.0), 
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5), 
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(12), 
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tagGroup.name, 
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant, 
                        fontSize: 13, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    tagGroup.tags.isEmpty
                        ? Text(
                            "No tags available",
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Wrap(
                            spacing: 8, 
                            runSpacing: 8,
                            children: tagGroup.tags.map((tag) => _buildColoredTagChip(tag, theme)).toList(),
                          )
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildColoredTagChip(AppTag tag, ThemeData theme) {
    bool isSelected = _selectedTagIds.contains(tag.id);
    final Color foregroundColor = isSelected ? Colors.white : tag.color;

    return InkWell(
      onTap: () {
        setState(() {
          isSelected ? _selectedTagIds.remove(tag.id) : _selectedTagIds.add(tag.id);
        });
      },
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
  }

  Widget _buildStickyFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, -4))
        ]
      ),
      child: SafeArea(
        top: false, 
        child: Row(
          children: [
            Button(
              label: "Cancel",
              variant: ButtonVariant.outline,
              onPressed: _isLoading ? null : () => Navigator.pop(context), 
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Button(
                label: _isLoading ? "Saving..." : "Save Tool", 
                variant: ButtonVariant.filled,
                icon: Icons.check,
                isLoading: _isLoading, 
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
                onPressed: _isLoading ? null : _saveTool, 
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class CreateToolGroupPanel extends StatefulWidget {
  final List<ToolGroup> existingGroups;
  final List<ToolItem> allMasterTools;
  final Future<bool> Function(String groupName, List<String> toolIds, List<String> toolGroupIds) onSave;
  

  const CreateToolGroupPanel({
    super.key,
    required this.existingGroups,
    required this.allMasterTools,
    required this.onSave,
  });

  @override
  State<CreateToolGroupPanel> createState() => _CreateToolGroupPanelState();
}

class _CreateToolGroupPanelState extends State<CreateToolGroupPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final Set<String> _selectedGroupIds = {};
  final Set<String> _selectedToolIds = {};
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 🚀 Premium UX: Checks if a tool is selected because its parent group was selected
  bool _isToolSelectedViaGroup(String toolId) {
    for (var group in widget.existingGroups.where((g) => _selectedGroupIds.contains(g.id))) {
      if (group.tools.any((t) => t.id == toolId)) return true;
    }
    return false;
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // Set<String> finalToolIds = {..._selectedToolIds};
    // for (var group in widget.existingGroups.where((g) => _selectedGroupIds.contains(g.id))) {
    //   finalToolIds.addAll(group.tools.map((t) => t.id));
    // }

    bool success = await widget.onSave(
      _nameController.text.trim(), 
      _selectedToolIds.toList(),
      _selectedGroupIds.toList()
    );
    
    // Make sure the widget is still on screen after the await
    if (!mounted) return; 

    setState(() => _isLoading = false);

    // 🚀 4. ONLY CLOSE THE POPUP IF SUCCESSFUL
    if (success) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final filteredTools = widget.allMasterTools
        .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Container(
      color: theme.colorScheme.surfaceContainer,
      // Wrap in AbsorbPointer to prevent ANY clicks while loading
      child: AbsorbPointer(
        absorbing: _isLoading,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            // --- HEADER ---
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.only(left: 24, right: 16, top: 16, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Create Tool Set", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    // Disable close button while loading
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

            // --- SCROLLABLE FORM BODY ---
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    const Text("Tool Set Name *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    FormControlTextField(
                      controller: _nameController,
                      hintText: "Enter a name for this tool set...",
                      prefixIcon: Icons.folder_special_outlined,
                      validator: (val) => (val == null || val.trim().isEmpty) ? "Set name is required" : null,
                    ),
                    const SizedBox(height: 32),

                    if (widget.existingGroups.isNotEmpty) ...[
                      const Text("Include Existing Tool Sets (Optional)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: widget.existingGroups.map((group) {
                          bool isSelected = _selectedGroupIds.contains(group.id);
                          return FilterChip(
                            label: Text(group.name),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                selected ? _selectedGroupIds.add(group.id) : _selectedGroupIds.remove(group.id);
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                            checkmarkColor: theme.colorScheme.primary,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 32),
                    ],

                    const Text("Select Individual Tools", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SearchField(
                      hintText: "Search tools...",
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    
                    Container(
                      height: 250, 
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: filteredTools.isEmpty
                          ? Center(child: Text("No tools found.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                          : ListView.separated(
                              itemCount: filteredTools.length,
                              separatorBuilder: (context, index) => Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                              itemBuilder: (context, index) {
                                final tool = filteredTools[index];
                                bool isSelectedViaGroup = _isToolSelectedViaGroup(tool.id);
                                bool isChecked = isSelectedViaGroup || _selectedToolIds.contains(tool.id);

                                return CheckboxListTile(
                                  title: Text(
                                    tool.name, 
                                    style: TextStyle(
                                      fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                      color: isSelectedViaGroup ? theme.colorScheme.onSurfaceVariant : null,
                                    )
                                  ),
                                  subtitle: isSelectedViaGroup 
                                      ? Text("Included via selected set", style: TextStyle(color: theme.colorScheme.primary, fontSize: 11))
                                      : null,
                                  value: isChecked,
                                  activeColor: theme.colorScheme.primary,
                                  controlAffinity: ListTileControlAffinity.trailing,
                                  onChanged: isSelectedViaGroup ? null : (bool? checked) {
                                    setState(() {
                                      if (checked == true) _selectedToolIds.add(tool.id);
                                      else _selectedToolIds.remove(tool.id);
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

            // --- ACTION BUTTONS ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    label: "Cancel",
                    variant: ButtonVariant.outline,
                    // Disable cancel button while loading
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  
                  // 🚀 5. UPDATE THE SAVE BUTTON UI
                  Button(
                    label: _isLoading ? "Creating..." : "Create Set",
                    variant: ButtonVariant.filled,
                    icon: _isLoading ? Icons.hourglass_top : Icons.check,
                    // Setting onPressed to null disables the button natively in Flutter!
                    onPressed: _isLoading ? null : _handleSave,
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

