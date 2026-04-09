import 'package:field_report_fe/models/tag_models.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import './models/tool_group.dart';
import '../canvas/models/canvas_models.dart';
import '../canvas/widgets/canvas_painter.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/button/button.dart';
import './create_tool_screen.dart';
import './controllers/tool_controller.dart'; // 🚀 IMPORT YOUR NEW CONTROLLER
import '../tags/controllers/tag_controller.dart'; // 🚀 IMPORT TAG CONTROLLER FOR LATER USE

class ToolsManagerScreen extends StatefulWidget {
  const ToolsManagerScreen({super.key});

  @override
  State<ToolsManagerScreen> createState() => _ToolsManagerScreenState();
}

class _ToolsManagerScreenState extends State<ToolsManagerScreen> {
  // 🚀 1. INITIALIZE THE CONTROLLER
  final ToolController _toolController = ToolController();
  final TagController _tagController = TagController();
  
  // 🚀 2. STORE ID INSTEAD OF OBJECT to prevent stale data issues
  String? _selectedGroupId; 
  String _groupSearchQuery = '';

  @override
  void initState() {
    super.initState();
    // 🚀 3. FETCH DATA ON LOAD
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _toolController.fetchGroups();
      _tagController.fetchGroups();
      // _toolController.fetchMasterTools(); <-- Assuming you add this to controller later!
    });
  }

  @override
  void dispose() {
    _toolController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _deleteGroup(ToolGroup group) async {
    // 🚀 TODO: Add _toolController.deleteGroup(group.id) here!
    // For now, we simulate the UI update:
    setState(() {
      if (_selectedGroupId == group.id) _selectedGroupId = null;
    });
  }

  void _editGroupName(ToolGroup group) {
    TextEditingController textController = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Group Name"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(labelText: "Name"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              // 🚀 TODO: Add _toolController.updateGroupName(group.id, textController.text) here!
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _handleGroupSelected(ToolGroup group, bool isMobile) {
    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MobileGroupDetailsScreen(
            group: group,
            // allMasterTools: _toolController.masterTools, // 🚀 Powered by controller
            allMasterTools: [], // 🚀 Powered by controller
            allToolGroups: _toolController.toolGroups, // 🚀 Powered by controller
            allTagGroups: _tagController.tagGroups, // 🚀 Powered by controller
          )
        ),
      );
    } else {
      setState(() => _selectedGroupId = group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // 🚀 4. WRAP IN LISTENABLE BUILDER
        child: ListenableBuilder(
          listenable: Listenable.merge([_toolController, _tagController]),
          builder: (context, _) {
            
            // Auto-select the first group if nothing is selected and data arrives
            if (_selectedGroupId == null && _toolController.toolGroups.isNotEmpty) {
              _selectedGroupId = _toolController.toolGroups.first.id;
            }

            // Find the active group object based on the ID
            final activeGroup = _toolController.toolGroups.where((g) => g.id == _selectedGroupId).firstOrNull;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER ROW ---
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0, bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Tools Management",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      // THE CREATE SET BUTTON
                      Button(
                        label: "Create Set",
                        variant: ButtonVariant.filled,
                        icon: Icons.create_new_folder_outlined,
                        onPressed: () {
                          // ... [Keep your existing Create Dialog/BottomSheet Logic here]
                        },
                      ),
                    ],
                  ),
                ),
                
                Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),

                // --- MAIN RESPONSIVE LAYOUT ---
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      bool isMobile = constraints.maxWidth < 800;

                      if (isMobile) {
                        return _buildGroupList(isMobile: true);
                      } else {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Side: Group List
                            Container(
                              width: 320, 
                              decoration: BoxDecoration(
                                border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5))),
                              ),
                              child: _buildGroupList(isMobile: false),
                            ),
                            
                            // Right Side: Details Panel
                            Expanded(
                              child: activeGroup != null
                                  ? GroupDetailsWidget(
                                      group: activeGroup,
                                      // allMasterTools: _toolController.masterTools, // 🚀
                                      allMasterTools: [], // 🚀
                                      onGroupUpdated: () {
                                        // 🚀 TODO: Trigger _toolController.fetchGroups() to refresh API
                                      },
                                      allToolGroups: _toolController.toolGroups, // 🚀 Pass all groups for Create Tool dropdown
                                      allTagGroups: _tagController.tagGroups, // 🚀 Pass all tag groups for Create Tool dropdown
                                    )
                                  : const Center(child: Text("Select a group to view details")),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildGroupList({required bool isMobile}) {
    final filteredGroups = _toolController.toolGroups.where((g) {
      return g.name.toLowerCase().contains(_groupSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // SEARCH FIELD
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SearchField(
            hintText: "Search groups...",
            onChanged: (val) {
              setState(() {
                _groupSearchQuery = val;
              });
            },
          ),
        ),
        
        // 🚀 5. ADDED LOADING STATE
        Expanded(
          child: _toolController.isGroupsLoading 
            ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
            : filteredGroups.isEmpty
                ? const Center(child: Text("No groups found."))
                : ListView.separated(
                    itemCount: filteredGroups.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
                    itemBuilder: (context, index) {
                      final group = filteredGroups[index];
                      final isSelected = !isMobile && _selectedGroupId == group.id; // 🚀 Checked against ID

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        child: ListTile(
                          selected: isSelected,
                          selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                          
                          title: Text(
                            group.name, 
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                            )
                          ),
                          subtitle: Text(
                            "${group.tools.length} tools",
                            style: TextStyle(
                              color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.7) : Colors.grey,
                              fontSize: 12
                            ),
                          ),
                          onTap: () => _handleGroupSelected(group, isMobile),
                          
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: "Edit Name",
                                onPressed: () => _editGroupName(group),
                                color: isSelected ? Theme.of(context).colorScheme.primary : null,
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: isSelected ? Colors.red[400] : Colors.red),
                                tooltip: "Delete Group",
                                onPressed: () => _deleteGroup(group),
                              ),
                              if (isMobile)
                                Icon(Icons.chevron_right, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
// --- 1. THE REUSABLE DETAILS UI ---
class GroupDetailsWidget extends StatefulWidget {
  final ToolGroup group;
  final List<ToolGroup> allToolGroups; // 🚀 ADD THIS
  final List<ToolItem> allMasterTools; // 🚀 ADD THIS
  final VoidCallback? onGroupUpdated;
  final List<AppTagGroup> allTagGroups; // 🚀 ADD THIS

  const GroupDetailsWidget({
    super.key,
    required this.group,
    required this.allToolGroups, // 🚀 ADD THIS
    this.onGroupUpdated,
    required this.allMasterTools,
    required this.allTagGroups, // 🚀 ADD THIS
  });

  @override
  State<GroupDetailsWidget> createState() => _GroupDetailsWidgetState();
}

class _GroupDetailsWidgetState extends State<GroupDetailsWidget> {
  // 🚀 1. Add state for the search query
  String _searchQuery = '';

  void _deleteTool(ToolItem tool) {
    setState(() {
      widget.group.tools.removeWhere((t) => t.id == tool.id);
    });
    if (widget.onGroupUpdated != null) widget.onGroupUpdated!();
  }

  Widget _buildCanvasPreview(BuildContext context, String jsonString) {
    try {
      List<dynamic> decodedJson = jsonDecode(jsonString);
      List<DrawingObject> objects = decodedJson
          .map((json) => DrawingObject.fromJson(json))
          .toList();

      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: FittedBox(
          fit: BoxFit.contain,
          child: IgnorePointer(
            child: SizedBox(
              width: 300,
              height: 300,
              child: CustomPaint(painter: MainPainter(context, objects, null)),
            ),
          ),
        ),
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, color: Colors.grey[400], size: 32),
            const SizedBox(height: 8),
            Text(
              "Preview Error",
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 2. Filter the tools based on the search query
    final filteredTools = widget.group.tools.where((tool) {
      return tool.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Group ID: ${widget.group.id}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              // 🚀 THE UPDATED BUTTON ROW (Manage & Create)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    label: "Manage Tools",
                    variant: ButtonVariant.outline,
                    icon: Icons.settings,
                    onPressed: () {
                      bool isMobile = MediaQuery.of(context).size.width < 800;

                      Widget panelContent = ManageToolsPanel(
                        group: widget.group,
                        allMasterTools: widget.allMasterTools, // Passed from parent
                        onSave: (List<ToolItem> newTools) {
                          setState(() {
                            widget.group.tools = newTools;
                          });
                          if (widget.onGroupUpdated != null) {
                            widget.onGroupUpdated!();
                          }
                        },
                      );

                      if (isMobile) {
                        // Mobile Bottom Sheet
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          clipBehavior: Clip.antiAlias,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          builder: (context) => SizedBox(
                            height: MediaQuery.of(context).size.height * 0.85, // 85% height
                            child: panelContent,
                          ),
                        );
                      } else {
                        // Desktop Dialog Popup
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            clipBehavior: Clip.antiAlias,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SizedBox(
                              width: 500, // Fixed width for desktop
                              height: 600,
                              child: panelContent,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: "Create Tool",
                    variant: ButtonVariant.outline,
                    icon: Icons.add,
                    onPressed: () {
                      // 🚀 FULL PAGE NAVIGATION
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateToolScreen(
                            availableGroups: widget.allToolGroups, // Pass all groups
                            initialGroupId: widget.group.id,
                            availableTagGroups: widget.allTagGroups,         // 🚀 Pass the active group's ID!
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 🚀 3. Add the SearchField row
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              Text(
                "${filteredTools.length} Tools found:",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SearchField(
                width: 250, // Uses the width prop you built into the widget
                hintText: "Search tools...",
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // The Grid
          if (filteredTools.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _searchQuery.isEmpty
                      ? "No tools assigned yet."
                      : "No tools match your search.",
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: filteredTools.length, 
                itemBuilder: (context, index) {
                  final tool = filteredTools[index]; 

                  return Card(
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The Canvas Preview Area
                        Expanded(
                          child: Container(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                            child: _buildCanvasPreview(
                              context,
                              tool.canvasJson,
                            ),
                          ),
                        ),

                        // The Toolbar (Name & Delete)
                        Container(
                          color: Theme.of(context).colorScheme.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tool.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _deleteTool(tool),
                                borderRadius: BorderRadius.circular(16),
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- 2. THE MOBILE WRAPPER SCREEN ---
// This wraps the Details UI in a Scaffold so it gets a Back Button on mobile!
class MobileGroupDetailsScreen extends StatelessWidget {
  final ToolGroup group;
  final List<ToolGroup> allToolGroups; // 🚀 ADD THIS
  final List<ToolItem> allMasterTools; // 🚀 ADD THIS
  final List<AppTagGroup> allTagGroups; // 🚀 ADD THIS

  const MobileGroupDetailsScreen({
    super.key,
    required this.group,
    required this.allToolGroups, // 🚀 ADD THIS
    required this.allMasterTools, // 🚀 ADD THIS
    required this.allTagGroups, // 🚀 ADD THIS
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: GroupDetailsWidget(
        group: group,
        allMasterTools: allMasterTools, // 🚀 PASS IT DOWN
        allToolGroups: allToolGroups, // 🚀 PASS IT DOWN
        allTagGroups: allTagGroups, // 🚀 PASS IT DOWN
      ),
    );
  }
}

class ManageToolsPanel extends StatefulWidget {
  final ToolGroup group;
  final List<ToolItem> allMasterTools;
  final Function(List<ToolItem>) onSave;

  const ManageToolsPanel({
    super.key,
    required this.group,
    required this.allMasterTools,
    required this.onSave,
  });

  @override
  State<ManageToolsPanel> createState() => _ManageToolsPanelState();
}

class _ManageToolsPanelState extends State<ManageToolsPanel> {
  late Set<String> _selectedToolIds;
  String _searchQuery = '';
  String _filterMode = 'All'; // 'All', 'Selected', 'Unselected'

  @override
  void initState() {
    super.initState();
    _selectedToolIds = widget.group.tools.map((t) => t.id).toSet();
  }

  // Helper to build the custom filter chips matching your design
  Widget _buildFilterChip(String label, ThemeData theme) {
    bool isActive = _filterMode == label;

    return InkWell(
      onTap: () => setState(() => _filterMode = label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.transparent,
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // THE FILTERING LOGIC
    final filteredTools = widget.allMasterTools.where((tool) {
      bool matchesSearch = tool.name.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      bool isSelected = _selectedToolIds.contains(tool.id);

      bool matchesFilter =
          _filterMode == 'All' ||
          (_filterMode == 'Selected' && isSelected) ||
          (_filterMode == 'Unselected' && !isSelected);

      return matchesSearch && matchesFilter;
    }).toList();

    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🚀 HEADER (Now using surface color for contrast!)
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.only(
              left: 24,
              right: 16,
              top: 16,
              bottom: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Manage Tools: ${widget.group.name}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          // 🚀 SEARCH & FILTERS
          Padding(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchField(
                  hintText: "Search...",
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 16),

                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip('All', theme),
                    _buildFilterChip('Selected', theme),
                    _buildFilterChip('Unselected', theme),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),

          // 🚀 LIST OF TOOLS
          Expanded(
            child: filteredTools.isEmpty
                ? Center(
                    child: Text(
                      "No tools match your criteria.",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filteredTools.length,
                    itemBuilder: (context, index) {
                      final tool = filteredTools[index];
                      final isSelected = _selectedToolIds.contains(tool.id);

                      return CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        title: Text(
                          tool.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        value: isSelected,
                        controlAffinity: ListTileControlAffinity.trailing,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedToolIds.add(tool.id);
                            } else {
                              _selectedToolIds.remove(tool.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),

          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),

          // 🚀 ACTION BUTTONS
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  label: "Close",
                  variant: ButtonVariant.outline,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Button(
                  label: "Save Changes",
                  variant: ButtonVariant.filled,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  onPressed: () {
                    List<ToolItem> finalSelection = widget.allMasterTools
                        .where((t) => _selectedToolIds.contains(t.id))
                        .toList();
                    widget.onSave(finalSelection);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
