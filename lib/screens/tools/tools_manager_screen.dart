import 'package:flutter/material.dart';
import './models/tool_group.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../../widgets/button/button.dart';
import './create_tool_screen.dart';
import './controllers/tool_controller.dart';
import '../tags/controllers/tag_controller.dart';
import '../../services/toast_service.dart';
import './widgets/group_details_widget.dart';

class ToolsManagerScreen extends StatefulWidget {
  const ToolsManagerScreen({super.key});

  @override
  State<ToolsManagerScreen> createState() => _ToolsManagerScreenState();
}

class _ToolsManagerScreenState extends State<ToolsManagerScreen> {
  final ToolController _toolController = ToolController();
  final TagController _tagController = TagController();
  
  String? _selectedGroupId; 
  String _groupSearchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {         
      _toolController.fetchMasterTools();
      _tagController.fetchGroups();
      await _toolController.fetchGroups(); 

      if (_toolController.toolGroups.isNotEmpty && mounted) {
        setState(() {
          _selectedGroupId = _toolController.toolGroups.first.id;
        });
        _toolController.fetchGroupDetails(_toolController.toolGroups.first.id);
      }
    });
  }

  @override
  void dispose() {
    _toolController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _deleteGroup(ToolGroup group) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return ConfirmationDialog(
          title: "Delete Tool Set",
          description: "Are you sure you want to delete '${group.name}'?",
          confirmLabel: "Delete",
          confirmColor: Colors.red,
          onConfirm: () async {
            bool success = await _toolController.deleteToolGroup(group.id);
            if (success) {
              _toolController.fetchGroups();
              if (_selectedGroupId == group.id && mounted) {
                setState(() => _selectedGroupId = null);
              }
              if (mounted) ToastService.show(context, message: "Tool Set deleted successfully!", type: ToastType.success);
            } else {
              if (mounted) ToastService.show(context, message: "Failed to delete tool set.", type: ToastType.error);
              throw Exception("API Deletion Failed"); 
            }
          },
        );
      },
    );
  }

  void _handleGroupSelected(ToolGroup group, bool isMobile) {
    _toolController.fetchGroupDetails(group.id); 

    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MobileGroupDetailsScreen(
            group: group,
            allToolGroups: _toolController.toolGroups,
            allMasterTools: _toolController.masterTools,
            allTagGroups: _tagController.tagGroups,
            onGroupUpdated: () {
              _toolController.fetchGroupDetails(group.id);
            },
            onManageSave: (groupId, newName, toolIds) async {
              bool success = await _toolController.updateToolGroup(
                groupId: groupId,
                name: newName,
                toolIds: toolIds,
              );

              if (success) {
                 _toolController.fetchGroups();
              }

              return success;
            },
            toolController: _toolController,
          )
        ),
      );
    } else {
      setState(() => _selectedGroupId = group.id);
    }
  }

  void _showCreateSetPanel(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 800;

    Widget panel = CreateToolGroupPanel(
      existingGroups: _toolController.toolGroups,
      allMasterTools: _toolController.masterTools, 
      onSave: (name, toolIds, toolGroupIds) async {
        bool success = await _toolController.createToolGroup(name, toolIds, toolGroupIds);
        if (success) {
           _toolController.fetchGroups();
           if(mounted) ToastService.show(context, message: "Tool Set created successfully!", type: ToastType.success);
        }        
        return success;
      },
    );

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        builder: (context) => ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: panel),
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 550, maxHeight: 800), child: panel),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_toolController, _tagController]),
          builder: (context, _) {
            if (_selectedGroupId == null && _toolController.toolGroups.isNotEmpty) {
              _selectedGroupId = _toolController.toolGroups.first.id;
            }

            final activeGroup = _toolController.toolGroups.where((g) => g.id == _selectedGroupId).firstOrNull;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0, bottom: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Tools Management", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Button(
                        label: "Create Tool Set",
                        variant: ButtonVariant.filled,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        icon: Icons.create_new_folder_outlined,
                        onPressed: () => _showCreateSetPanel(context)
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
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
                            Container(
                              width: 320, 
                              decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.5)))),
                              child: _buildGroupList(isMobile: false),
                            ),
                            Expanded(
                              child: activeGroup != null
                                  ? _toolController.isGroupDetailsLoading 
                                      ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                                      : GroupDetailsWidget(
                                          group: activeGroup,
                                          allToolGroups: _toolController.toolGroups,
                                          allMasterTools: _toolController.masterTools,
                                          allTagGroups: _tagController.tagGroups,
                                          onGroupUpdated: () {
                                            _toolController.fetchGroupDetails(activeGroup.id); 
                                          },

                                          // 🚀 1. UPDATE THE DESKTOP CALLBACK
                                          onManageSave: (groupId, newName, toolIds) async {
                                            bool success = await _toolController.updateToolGroup(
                                              groupId: groupId,
                                              name: newName,
                                              toolIds: toolIds,
                                            );

                                            // If successful, silently refresh the left menu to show the new group name!
                                            if (success) {
                                               _toolController.fetchGroups();
                                            }

                                            return success;
                                          },
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
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SearchField(
            hintText: "Search groups...",
            onChanged: (val) => setState(() => _groupSearchQuery = val),
          ),
        ),
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
                      final isSelected = !isMobile && _selectedGroupId == group.id;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        child: ListTile(
                          selected: isSelected,
                          selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
                          title: Text(group.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface)),
                          subtitle: Text("${group.tools.length} tools", style: TextStyle(color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.7) : Colors.grey, fontSize: 12)),
                          onTap: () => _handleGroupSelected(group, isMobile),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: isSelected ? Colors.red[400] : Colors.red),
                                tooltip: "Delete Group",
                                onPressed: () => _deleteGroup(group),
                              ),
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