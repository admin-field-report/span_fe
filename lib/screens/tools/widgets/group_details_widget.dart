import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:field_report_fe/models/tag_models.dart';
import '../models/tool_group.dart';
import '../../../widgets/canvas/models/canvas_models.dart';
import './custom_tool_preview.dart';
import '../../../widgets/search_field/search_field.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/confirmation/confirmation_remove.dart';
import './manage_tools_panel.dart';
import '../controllers/tool_controller.dart';
import '../../../utils/app_responsive.dart';
import '../../../services/toast_service.dart';

class GroupDetailsWidget extends StatefulWidget {
  final ToolGroup group;
  final List<ToolGroup> allToolGroups;
  final List<ToolItem> allMasterTools;
  final List<AppTagGroup> allTagGroups;
  final VoidCallback? onGroupUpdated;
  final Future<bool> Function(String groupId, String newName, List<String> toolIds) onManageSave;

  const GroupDetailsWidget({
    super.key,
    required this.group,
    required this.allToolGroups,
    required this.allMasterTools,
    required this.allTagGroups,
    this.onGroupUpdated,
    required this.onManageSave,
  });

  @override
  State<GroupDetailsWidget> createState() => _GroupDetailsWidgetState();
}

class _GroupDetailsWidgetState extends State<GroupDetailsWidget> {
  String _searchQuery = '';

  Future<void> _deleteTool(ToolItem tool) async {
    await showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Delete Tool?",
        description: "Are you sure you want to delete this tool? This action cannot be undone.",
        confirmLabel: "Delete",
        cancelLabel: "Cancel",
        confirmColor: Colors.red,
        onConfirm: () async {
          
          // 🚀 1. Call the Controller!
          final bool isSuccess = await ToolController().deleteTool(tool.custom_tool_group_item_id);

          if (isSuccess) {
            // 2. Update UI
            setState(() {
              widget.group.tools.removeWhere((t) => t.id == tool.id);
            });
            
            // 3. Trigger parent refresh
            if (widget.onGroupUpdated != null) {
              widget.onGroupUpdated!();
            }

            if (mounted) ToastService.show(context, message: "Tool deleted successfully!", type: ToastType.success);
            
            return; // Exit normally to close the dialog
          } 
          
          // 4. Handle Failure
          if (mounted) ToastService.show(context, message: "Failed to delete tool. Please try again.", type: ToastType.error);
          throw Exception("Deletion failed"); 
        },
      ),
    );
  }

  Widget _buildCanvasPreview(BuildContext context, String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty || jsonString == "[]" || jsonString == "{}") {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, color: Theme.of(context).colorScheme.outlineVariant, size: 32),
            const SizedBox(height: 8),
            Text("Empty Canvas", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10)),
          ],
        ),
      );
    }

    try {
      final dynamic decoded = jsonDecode(jsonString);
      List<dynamic> rawObjects = [];

      if (decoded is List) {
        rawObjects = decoded;
      } else if (decoded is Map) {
        if (decoded.containsKey('objects') && decoded['objects'] is List) {
          rawObjects = decoded['objects'];
        } else {
          rawObjects = [decoded];
        }
      }

      List<DrawingObject> objects = rawObjects.map((json) => DrawingObject.fromJson(json as Map<String, dynamic>)).toList();

      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: IgnorePointer(
          child: SizedBox(
            width: 300,
            height: 300,
            child: CustomPaint(
              painter: CenteredPreviewPainter(context, objects), // 🚀 Use the new wrapper
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
            Text("Preview Error", style: TextStyle(color: Colors.grey[600], fontSize: 10)),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = AppResponsive.isMobileScreen(context);

    final filteredTools = widget.group.tools.where((tool) {
      return tool.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    Widget actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Button(
          label: "Manage Tools",
          variant: ButtonVariant.outline,
          icon: Icons.settings,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: () {
            Widget panelContent = ManageToolsPanel(
              group: widget.group,
              allMasterTools: widget.allMasterTools,
              onSave: (String newName, List<String> selectedToolIds) async {
                bool success = await widget.onManageSave(widget.group.id, newName, selectedToolIds);
                if (success) {
                  setState(() {
                    widget.group.name = newName;
                    widget.group.tools = widget.allMasterTools.where((t) => selectedToolIds.contains(t.id)).toList();
                  });
                  if (widget.onGroupUpdated != null) widget.onGroupUpdated!();
                }
                return success;
              },
            );

            if (isMobile) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                clipBehavior: Clip.antiAlias,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                builder: (context) => SizedBox(height: MediaQuery.of(context).size.height * 0.85, child: panelContent),
              );
            } else {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: SizedBox(width: 500, height: 600, child: panelContent),
                ),
              );
            }
          },
        ),
      ],
    );

    return Padding(
      padding: isMobile ? const EdgeInsets.fromLTRB(0, 10, 0, 10) : const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if(!isMobile) Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.group.name, 
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              actionButtons,
            ],
          ),

          SizedBox(height: isMobile ? 0 : 15),
          
          Row(
            children: [
              Expanded(
                child: SearchField(
                  hintText: "Search tools...", 
                  onChanged: (value) => setState(() => _searchQuery = value)
                ),
              ),
              
              if (isMobile) ...[
                const SizedBox(width: 16),
                actionButtons,
              ]
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (filteredTools.isEmpty)
            Expanded(child: Center(child: Text(_searchQuery.isEmpty ? "No tools assigned yet." : "No tools match your search.")))
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 250, childAspectRatio: 0.85, crossAxisSpacing: 16, mainAxisSpacing: 16,
                ),
                itemCount: filteredTools.length,
                itemBuilder: (context, index) {
                  final tool = filteredTools[index];
                  return Card(
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                            child: _buildCanvasPreview(context, tool.canvasJson ?? "[]"),
                          ),
                        ),
                        Container(
                          color: Theme.of(context).colorScheme.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(tool.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _deleteTool(tool),
                                borderRadius: BorderRadius.circular(16),
                                child: const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.delete_outline, size: 20, color: Colors.red)),
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



class MobileGroupDetailsScreen extends StatelessWidget {
  final ToolGroup group;
  final List<ToolGroup> allToolGroups; 
  final List<ToolItem> allMasterTools; 
  final List<AppTagGroup> allTagGroups; 
  final VoidCallback? onGroupUpdated;
  final Future<bool> Function(String groupId, String newName, List<String> toolIds) onManageSave;
  final ToolController toolController;

  const MobileGroupDetailsScreen({
    super.key,
    required this.group,
    required this.allToolGroups, 
    required this.allMasterTools, 
    required this.allTagGroups, 
    this.onGroupUpdated,
    required this.onManageSave,
    required this.toolController,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: false,
      ),
      
      body: ListenableBuilder(
        listenable: toolController,
        builder: (context, child) {
        
          if (toolController.isGroupDetailsLoading) {
            return Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
            );
          }
          final freshGroup = toolController.toolGroups.firstWhere(
            (g) => g.id == group.id,
            orElse: () => group,
          );
          return GroupDetailsWidget(
            group: freshGroup,
            
            allToolGroups: toolController.toolGroups, 
            allMasterTools: toolController.masterTools, 
            
            allTagGroups: allTagGroups, 
            onGroupUpdated: onGroupUpdated,
            onManageSave: onManageSave, 
          );
        },
      ),
    );
  }
}