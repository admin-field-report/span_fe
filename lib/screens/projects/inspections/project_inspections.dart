import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/inspection_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';
import './create_inspection_panel.dart';

class ProjectInspectionsTab extends StatefulWidget {
  final String projectId;

  const ProjectInspectionsTab({super.key, required this.projectId});

  @override
  State<ProjectInspectionsTab> createState() => _ProjectInspectionsTabState();
}

class _ProjectInspectionsTabState extends State<ProjectInspectionsTab> {
  String _searchQuery = "";
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    inspectionController.getAllInspections(widget.projectId);
  }

  List<ProjectInspection> _getFilteredInspections() {
    return inspectionController.inspections.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> removeInspection(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/inspection/$id');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        ToastService.show(context, 
          message: "Inspection deleted successfully", 
          type: ToastType.success
        );
        inspectionController.getAllInspections(widget.projectId);
      } else {
        ToastService.show(context, 
          message: "Unexpected error occurred", 
          type: ToastType.error
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastService.show(context, 
        message: "Failed to delete inspection: $e", 
        type: ToastType.error
      );
    }
  }

  void _confirmDelete(BuildContext context, ProjectInspection project) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: ConfirmationDialog(
            title: "Remove Inspection",
            description: "Are you sure you want to remove inspection for '${DateFormat('dd MMM yyyy').format(project.createTime)}'?",
            confirmLabel: "Remove",
            onConfirm: () async => await removeInspection(context, project.id),
          ),
        ),
      ),
    );
  }

  void _showCreateInspectionPanel() async {
    final isMobile = AppResponsive.isMobileScreen(context);
    String? newInspectionId;

    if (isMobile) {
    newInspectionId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.85, 
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: CreateInspectionPanel(projectId: widget.projectId),
          ),
        ),
      );
    } else {
     newInspectionId = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 600, 
            height: 700, 
            child: CreateInspectionPanel(projectId: widget.projectId),
          ),
        ),
      );
    }
    // 🚀 2. If we got an ID back, the creation was successful!
    if (newInspectionId != null && newInspectionId.isNotEmpty) {
      
      // A. Trigger the background refresh so the list is updated when they hit "Back"
      // TODO: Replace this with your actual fetch method
      inspectionController.getAllInspections(widget.projectId); 

      // B. Navigate to the new details screen safely using the Parent's context!
      if (context.mounted) {
        final exactUrl = '/projects/details/${widget.projectId}/inspections/$newInspectionId';
        context.go(exactUrl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: inspectionController,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            // 🚀 1. Wrap the entire AppCard in Expanded
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    _buildTopToolbar(theme),

                    // 🚀 2. Wrap the Table in Expanded so it fills the rest of the card
                    Expanded(
                      child: ListenableBuilder(
                        listenable: inspectionController,
                        builder: (context, child) {
                          final displayData = _getFilteredInspections();
                          return CommonTable<ProjectInspection>(
                            isLoading: inspectionController.isInspectionsLoading,
                            data: displayData,
                            showCheckboxes: false,
                            
                            // 🚀 1. ACTIVATED: Entire row is now tappable!
                            onRowTap: (item) {
                              final exactUrl = '/projects/details/${widget.projectId}/inspections/${item.id}';
                              context.go(exactUrl);
                            },

                            columns: [
                              TableColumn(
                                title: 'Sr No.',
                                flex: 1,
                                minWidth: 60,
                                builder: (item) {
                                  final index = inspectionController.inspections.indexOf(item) + 1;
                                  return Text(index.toString().padLeft(2, '0'));
                                },
                              ),
                              TableColumn(
                                title: 'Inspector',
                                flex: 2,
                                sortable: false,
                                builder: (item) => Text(item.name),
                              ),
                              TableColumn(
                                title: 'Date',
                                flex: 2,
                                sortable: true,
                                sortValue: (item) => item.createTime,
                                builder: (item) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('dd MMM yyyy').format(item.createTime),
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2), // Tiny spacing
                                    Text(
                                      DateFormat('hh:mm a').format(item.createTime),
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurfaceVariant, 
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // 🚀 2. UPDATED: Removed View icon, shrank width, kept Sticky!
                              TableColumn(
                                title: "Actions",
                                flex: 0,
                                minWidth: 60, // Shrank from 100 since there is only one icon now
                                isStickyRight: true, 
                                builder: (p) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // DELETE BUTTON
                                    IconButton(
                                      tooltip: "Delete",
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      color: colorScheme.error,
                                      onPressed: () => _confirmDelete(context, p),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    ),  
                  ]
                )
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16), 
      child: Row(
        children: [
          // Search Field
          Expanded(
            child: SearchField(
              // On desktop we restrict the width, on mobile we let it fill the remaining space flexibly
              width: isDesktop ? 350 : double.infinity, 
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) const Spacer(),
          if (!isDesktop) const SizedBox(width: 12), // Adds spacing on mobile so the button doesn't hug the search bar

          // Refresh Button (Desktop Only)
          if (isDesktop) ...[
            Tooltip(
              message: 'Refresh Inspections',
              child: InkWell(
                onTap: inspectionController.isInspectionsLoading ? null : () {
                  inspectionController.getAllInspections(widget.projectId);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded, 
                    size: 20, 
                    color: colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],

          // 🚀 THE NEW CREATE BUTTON
          Button(
            label: isDesktop ? "Create Inspection" : "Create",
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
            variant: ButtonVariant.filled,
            icon: Icons.add,
            onPressed: _showCreateInspectionPanel,
          ),
        ],
      )
    );
  }
}