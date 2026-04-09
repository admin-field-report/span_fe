import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../widgets/button/button.dart';
import '../../../widgets/canvas/canvas.dart';
import '../../../widgets/form_components/text_field.dart';
import '../../../widgets/form_components/select_field.dart';
import '../../../widgets/search_field/search_field.dart';
import './models/tool_group.dart';
import '../../../models/tag_models.dart';

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
  final List<AppTagGroup> availableTagGroups; // 🚀 Using the real TagGroups
  final String? initialGroupId;

  const CreateToolScreen({
    super.key, 
    required this.availableGroups,
    required this.availableTagGroups,
    this.initialGroupId,
  });

  @override
  State<CreateToolScreen> createState() => _CreateToolScreenState();
}

class _CreateToolScreenState extends State<CreateToolScreen> {
  final GlobalKey<CanvasState> _canvasKey = GlobalKey<CanvasState>();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  String? _selectedGroupId;
  final Set<String> _selectedTagIds = {};

  @override
  void initState() {
    super.initState();
    // Auto-select the group if passed in from the previous screen
    if (widget.initialGroupId != null && widget.availableGroups.any((g) => g.id == widget.initialGroupId)) {
      _selectedGroupId = widget.initialGroupId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveTool() {
    // 1. Form Validation
    if (!_formKey.currentState!.validate()) return;

    // 2. Canvas Validation
    final canvasState = _canvasKey.currentState;
    if (canvasState == null || canvasState.objects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("⚠️ Please draw a tool on the canvas before saving."),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String toolName = _nameController.text.trim();
    String canvasJson = jsonEncode(canvasState.objects.map((e) => e.toJson()).toList());
    debugPrint("🚀 Canvas JSON: $canvasJson");

    final payload = {
      "name": toolName,
      "tool_group_id": _selectedGroupId,
      "canvas_json": canvasJson,
      "tags": _selectedTagIds.toList(), 
    };

    debugPrint("🚀 ====== CREATE TOOL PAYLOAD ======");
    debugPrint(jsonEncode(payload)); 
    debugPrint("=====================================");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Tool '$toolName' created!"), backgroundColor: Colors.green),
    );
    Navigator.pop(context); 
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BACK BUTTON HEADER ---
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text("Back", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

            // --- RESPONSIVE LAYOUT WITH STICKY FOOTER ---
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  bool isMobile = constraints.maxWidth < 800;
                  Widget canvasSection = _buildCanvasSection(theme);
                  Widget formFields = _buildFormFields(theme);
                  Widget stickyFooter = _buildStickyFooter(theme);

                  if (isMobile) {
                    return Column(
                      children: [
                        // Scrollable Body
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                canvasSection,
                                const SizedBox(height: 32),
                                formFields,
                              ],
                            ),
                          ),
                        ),
                        // 🚀 Sticky Footer at the bottom of the screen
                        stickyFooter,
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Canvas Area
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32.0),
                            child: canvasSection,
                          ),
                        ),
                        Container(width: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                        // Right Form Area
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              // Scrollable Form
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(32.0),
                                  child: formFields,
                                ),
                              ),
                              // 🚀 Sticky Footer at the bottom of the right panel
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
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
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
        Container(
          height: 600, 
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Canvas(
            key: _canvasKey,
            leftActions: const [], rightActions: const [],
          ),
        ),
      ],
    );
  }

  // 🚀 EXTRACTED JUST THE FIELDS
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
          FormControlSelect<String>(
            value: _selectedGroupId,
            hintText: "Select a group",
            prefixIcon: Icons.folder_outlined,
            items: widget.availableGroups.map((g) => GroupSelectableItem(g)).toList(),
            onChanged: (val) => setState(() => _selectedGroupId = val),
            validator: (value) => (value == null || value.isEmpty) ? 'Please select a group' : null,
          ),
          const SizedBox(height: 32),

          const Text("3. Tags (Optional)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          
          // 🚀 RENDER THE COLORED TAG GROUPS
          ...widget.availableTagGroups.map((tagGroup) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tagGroup.name, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
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

  // 🚀 THE PREMIUM COLORED TAG COMPONENT
  Widget _buildColoredTagChip(AppTag tag, ThemeData theme) {
    bool isSelected = _selectedTagIds.contains(tag.id);

    return InkWell(
      onTap: () {
        setState(() {
          isSelected ? _selectedTagIds.remove(tag.id) : _selectedTagIds.add(tag.id);
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // 15% opacity background if selected, clear if not
          color: isSelected ? tag.color.withOpacity(0.15) : Colors.transparent,
          border: Border.all(
            // Colored border if selected, dim grey outline if not
            color: isSelected ? tag.color : theme.colorScheme.outlineVariant.withOpacity(0.5),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The colored circle indicator
            Container(width: 10, height: 10, decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(
              tag.name,
              style: TextStyle(
                color: isSelected ? tag.color : theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 THE NEW STICKY FOOTER
  Widget _buildStickyFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, -4))
        ]
      ),
      child: SafeArea(
        top: false, // Only apply safe area to the bottom (for iPhones with home bars)
        child: Button(
          label: "Save Tool",
          variant: ButtonVariant.filled,
          width: double.infinity,
          icon: Icons.check,
          padding: const EdgeInsets.symmetric(vertical: 16),
          onPressed: _saveTool,
        ),
      ),
    );
  }
}


class CreateToolGroupPanel extends StatefulWidget {
  final List<ToolGroup> existingGroups;
  final List<ToolItem> allMasterTools;
  final Function(ToolGroup) onSave;

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

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    // 1. Gather all unique tools from both selected groups and individually checked tools
    Set<String> finalToolIds = {..._selectedToolIds};
    for (var group in widget.existingGroups.where((g) => _selectedGroupIds.contains(g.id))) {
      finalToolIds.addAll(group.tools.map((t) => t.id));
    }

    List<ToolItem> finalTools = widget.allMasterTools
        .where((t) => finalToolIds.contains(t.id))
        .toList();

    // 2. Create the new Group
    ToolGroup newGroup = ToolGroup(
      id: "g_${DateTime.now().millisecondsSinceEpoch}", // Generate a unique ID
      name: _nameController.text.trim(),
      tools: finalTools,
    );

    // 3. Save and Close
    widget.onSave(newGroup);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Filter the individual tools list based on the search query
    final filteredTools = widget.allMasterTools
        .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          
          // 🚀 HEADER
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.only(left: 24, right: 16, top: 16, bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Create Tool Set", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  color: theme.colorScheme.onSurfaceVariant,
                )
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),

          // 🚀 SCROLLABLE FORM BODY
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24.0),
                children: [
                  
                  // 1. SET NAME (Required)
                  const Text("Tool Set Name *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  FormControlTextField(
                    controller: _nameController,
                    hintText: "Enter a name for this tool set...",
                    prefixIcon: Icons.folder_special_outlined,
                    validator: (val) => (val == null || val.trim().isEmpty) ? "Set name is required" : null,
                  ),
                  const SizedBox(height: 32),

                  // 2. QUICK ADD: EXISTING SETS
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

                  // 3. INDIVIDUAL TOOLS LIST
                  const Text("Select Individual Tools", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SearchField(
                    hintText: "Search tools...",
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                  const SizedBox(height: 12),
                  
                  // Bounded Box for the tools list so it doesn't take up the whole screen
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
                                    // Dim the text if it's forced-selected by a group
                                    color: isSelectedViaGroup ? theme.colorScheme.onSurfaceVariant : null,
                                  )
                                ),
                                subtitle: isSelectedViaGroup 
                                    ? Text("Included via selected set", style: TextStyle(color: theme.colorScheme.primary, fontSize: 11))
                                    : null,
                                value: isChecked,
                                activeColor: theme.colorScheme.primary,
                                controlAffinity: ListTileControlAffinity.trailing,
                                // Disable the checkbox if the tool is already included via a selected group
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

          // 🚀 ACTION BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  label: "Cancel",
                  variant: ButtonVariant.outline,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Button(
                  label: "Create Set",
                  variant: ButtonVariant.filled,
                  icon: Icons.check,
                  onPressed: _handleSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}