import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';

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
    projectController.getAllInspections(widget.projectId);
  }

  List<ProjectInspection> _getFilteredInspections() {
    return projectController.inspections.where((p) {
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
        projectController.getAllInspections(widget.projectId);
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

  void _confirmDelete(BuildContext context,  ProjectInspection project) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: projectController,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                crossAxisAlignment: CrossAxisAlignment.stretch, 
                children: [
                  _buildTopToolbar(theme),
                  const SizedBox(height: 10),

                    ListenableBuilder(
                    listenable: projectController,
                    builder: (context, child) {
                    final displayData = _getFilteredInspections();
                    return CommonTable<ProjectInspection>(
                        isLoading: projectController.isInspectionsLoading,
                        data: displayData,
                        showCheckboxes: false,
                        columns: [
                          TableColumn(
                            title: 'Sr No.',
                            flex: 1,
                            minWidth: 60,
                            builder: (item) {
                              final index = projectController.inspections.indexOf(item) + 1;
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
                            builder: (item) => Text(
                              DateFormat('dd MMM yyyy').format(item.createTime),
                            ),
                          ),
                          TableColumn(
                            title: "Actions",
                            flex: 0,
                            minWidth: 100,
                            builder: (p) => IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: colorScheme.error,
                              onPressed: () => _confirmDelete(context, p),
                            ),
                          ),
                        ],
                      );
                    }
                  )  
                ]
              )
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
          Expanded(
            child: SearchField(
              width: 350,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) ...[
            const Spacer(),
            Tooltip(
              message: 'Refresh Inspections',
              child: InkWell(
                onTap: projectController.isInspectionsLoading ? null : () {
                  projectController.getAllInspections(widget.projectId);
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
          ],
        ],
      )
    );
  }
}