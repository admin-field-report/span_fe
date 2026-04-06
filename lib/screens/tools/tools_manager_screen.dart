import 'package:flutter/material.dart';
import 'dart:convert';
import './models/tool_group.dart';
import '../canvas/models/canvas_models.dart';
import '../canvas/widgets/canvas_painter.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/button/button.dart';
import './create_tool_screen.dart';

class ToolsManagerScreen extends StatefulWidget {
  const ToolsManagerScreen({super.key});

  @override
  State<ToolsManagerScreen> createState() => _ToolsManagerScreenState();
}

class _ToolsManagerScreenState extends State<ToolsManagerScreen> {
  // 1. DUMMY DATA
  final List<ToolGroup> _groups = [
    ToolGroup(id: '1', name: 'Custom Hatches', tools: [
      ToolItem(id: 't1', name: 'Red Brick Paving', canvasJson: '[{"type": "brick", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 200.0, "dy": 100.0}, "color": "FF000000", "fillColor": "FFD32F2F"}]'),
      ToolItem(id: 't2', name: 'Oak Wood Weave', canvasJson: '[{"type": "weave", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 150.0, "dy": 150.0}, "color": "FF3E2723", "fillColor": "FFD7CCC8"}]'),
    ]),
    ToolGroup(id: '2', name: 'Annotations', tools: [
      ToolItem(id: 't3', name: 'Blue Callout', canvasJson: '[{"type": "text", "isCallout": true, "text": "Check this detail", "start": {"dx": 50.0, "dy": 10.0}, "end": {"dx": 150.0, "dy": 40.0}, "color": "FF1565C0", "borderColor": "FF1565C0", "fillColor": "FFE3F2FD"}]'),
    ]),
  ];

  final List<ToolItem> _allMasterTools = [
    ToolItem(id: 't1', name: 'Red Brick Paving', canvasJson: '[{"type": "brick", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 200.0, "dy": 100.0}, "color": "FF000000", "fillColor": "FFD32F2F"}]'),
    ToolItem(id: 't2', name: 'Oak Wood Weave', canvasJson: '[{"type": "weave", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 150.0, "dy": 150.0}, "color": "FF3E2723", "fillColor": "FFD7CCC8"}]'),
    ToolItem(id: 't3', name: 'Blue Callout', canvasJson: '[{"type": "text", "isCallout": true, "text": "Note", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 100.0, "dy": 50.0}, "color": "FF1565C0"}]'),
    ToolItem(id: 't4', name: 'Gravel / Concrete', canvasJson: '[{"type": "concrete", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 100.0, "dy": 100.0}, "color": "FF424242", "patternDensity": 40.0}]'),
    ToolItem(id: 't5', name: 'Wall Insulation', canvasJson: '[{"type": "insulation", "start": {"dx": 0.0, "dy": 0.0}, "end": {"dx": 300.0, "dy": 60.0}, "color": "FFF48FB1"}]'),
  ];

  ToolGroup? _selectedGroup;
  
  // 🚀 NEW STATE: Search query for the group list
  String _groupSearchQuery = '';

  @override
  void initState() {
    super.initState();
    if (_groups.isNotEmpty) _selectedGroup = _groups.first;
  }

  void _deleteGroup(ToolGroup group) {
    setState(() {
      _groups.removeWhere((g) => g.id == group.id);
      if (_selectedGroup?.id == group.id) {
        _selectedGroup = _groups.isNotEmpty ? _groups.first : null;
      }
    });
  }

  void _editGroupName(ToolGroup group) {
    TextEditingController controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Group Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Name"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() => group.name = controller.text);
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
            allMasterTools: _allMasterTools,
          )
        ),
      );
    } else {
      setState(() => _selectedGroup = group);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🚀 REMOVED: AppBar has been completely removed
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            // 🚀 NEW: Just a simple label on the left side
            // 🚀 UPDATED HEADER ROW
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
                  
                  // 🚀 THE CREATE TOOL SET BUTTON
                  Button(
                    label: "Create Set",
                    variant: ButtonVariant.filled,
                    icon: Icons.create_new_folder_outlined,
                    onPressed: () {
                      bool isMobile = MediaQuery.of(context).size.width < 800;

                      Widget panelContent = CreateToolGroupPanel(
                        existingGroups: _groups,
                        allMasterTools: _allMasterTools,
                        onSave: (ToolGroup newGroup) {
                          setState(() {
                            _groups.add(newGroup);
                            _selectedGroup = newGroup; // Auto-select the newly created group!
                          });
                        },
                      );

                      if (isMobile) {
                        // 📱 Mobile Bottom Sheet
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          clipBehavior: Clip.antiAlias,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          builder: (context) => SizedBox(
                            height: MediaQuery.of(context).size.height * 0.90, // 90% height
                            child: panelContent,
                          ),
                        );
                      } else {
                        // 💻 Desktop Dialog
                        showDialog(
                          context: context,
                          builder: (context) => Dialog(
                            clipBehavior: Clip.antiAlias,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: SizedBox(
                              width: 550, // Perfect width for a form
                              height: 750, 
                              child: panelContent,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            
            Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),

            // Main Responsive Layout
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
                          width: 320, // Slightly wider to accommodate search
                          decoration: BoxDecoration(
                            border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5))),
                          ),
                          child: _buildGroupList(isMobile: false),
                        ),
                        
                        // Right Side: Details Panel
                        Expanded(
                          child: _selectedGroup != null
                              ? GroupDetailsWidget(
                                  group: _selectedGroup!,
                                  allMasterTools: _allMasterTools,
                                  onGroupUpdated: () => setState(() {}),
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
        ),
      ),
    );
  }

  Widget _buildGroupList({required bool isMobile}) {
    // 🚀 NEW: Filter groups based on search query
    final filteredGroups = _groups.where((g) {
      return g.name.toLowerCase().contains(_groupSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // 🚀 NEW: Search field added above the groups
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
        
        Expanded(
          child: filteredGroups.isEmpty
              ? const Center(child: Text("No groups found."))
              : ListView.separated(
                  itemCount: filteredGroups.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
                  itemBuilder: (context, index) {
                    final group = filteredGroups[index];
                    final isSelected = !isMobile && _selectedGroup?.id == group.id;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                      child: ListTile(
                        selected: isSelected,
                        
                        // 🚀 The premium 15% tinted highlight
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
  final List<ToolItem> allMasterTools; // 🚀 ADD THIS
  final VoidCallback? onGroupUpdated;

  const GroupDetailsWidget({
    super.key,
    required this.group,
    this.onGroupUpdated,
    required this.allMasterTools,
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
                            // Pass your master groups list here
                            availableGroups: widget.allMasterTools.isNotEmpty 
                                ? [widget.group] // Assuming you want them to be able to select the current group
                                : [], 
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
  final List<ToolItem> allMasterTools; // 🚀 ADD THIS

  const MobileGroupDetailsScreen({
    super.key,
    required this.group,
    required this.allMasterTools, // 🚀 ADD THIS
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: GroupDetailsWidget(
        group: group,
        allMasterTools: allMasterTools, // 🚀 PASS IT DOWN
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
