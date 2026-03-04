import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';

class ProjectInspectionsTab extends StatefulWidget {
    final String projectId;

  const ProjectInspectionsTab({super.key, required this.projectId});

  @override
  State<ProjectInspectionsTab> createState() => _ProjectInspectionsTabState();
}

class _ProjectInspectionsTabState extends State<ProjectInspectionsTab> {

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // Fetch inspections for the project
    projectController.getAllInspections(widget.projectId);
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
              SizedBox(height: 20),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    ListenableBuilder(
                      listenable: projectController,
                      builder: (context, child) {
                        return CommonTable<ProjectInspection>(
                          isLoading: projectController.isInspectionsLoading,
                          data: projectController.inspections.toList(),
                          showCheckboxes: false,
                          // onRowTap: (item) => debugPrint("Navigating to ${item['id']}"),
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
                              sortable: true,
                              builder: (item) => Text(
                                "Unknown", 
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6)),
                              ),
                            ),
                            TableColumn(
                              title: 'Date',
                              flex: 2,
                              sortable: true,
                              sortValue: (item) => item.createTime,
                              builder: (item) {
                                final date = item.createTime;
                                return Text(DateFormat('dd MMM yyyy').format(date));
                              },
                            ),
                            TableColumn(
                              title: "Actions",
                              flex: 0,
                              minWidth: 150,
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
              )
            ]
        );
      }
     );
  }
}