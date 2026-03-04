import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';

class ProjectReports extends StatefulWidget {
    final String projectId;

  const ProjectReports({super.key, required this.projectId});

  @override
  State<ProjectReports> createState() => _ProjectReportsState();
}

class _ProjectReportsState extends State<ProjectReports> {

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    projectController.getAllReports(widget.projectId);
  }

  Future<void> removeReport(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/report/delete/$id');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        ToastService.show(context, 
          message: "Report deleted successfully", 
          type: ToastType.success
        );
        projectController.getAllReports(widget.projectId);
      } else {
        ToastService.show(context, 
          message: "Unexpected error occurred", 
          type: ToastType.error
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastService.show(context, 
        message: "Failed to delete report: $e", 
        type: ToastType.error
      );
    }
  }

  void _confirmDelete(BuildContext context,  ProjectReport report) {
    showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: ConfirmationDialog(
              title: "Remove Report",
              description: "Are you sure you want to remove this for '${report.name}'?",
              confirmLabel: "Remove",
              onConfirm: () async => await removeReport(context, report.id),
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
                        return CommonTable<ProjectReport>(
                        isLoading: projectController.isReportLoading,
                        data: projectController.reports.toList(),
                        showCheckboxes: false,
                        // onRowTap: (item) => debugPrint("Navigating to ${item['id']}"),
                        columns: [
                          TableColumn(
                            title: 'Sr No.',
                            flex: 1,
                            minWidth: 60,
                            builder: (item) {
                              final index = projectController.reports.indexOf(item) + 1;
                              return Text(index.toString().padLeft(2, '0'));
                            },
                          ),
                          TableColumn(
                            title: 'Report Name',
                            flex: 2,
                            sortable: true,
                            builder: (item) => Text(  
                              item.name, 
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          TableColumn(
                            title: 'Created Date',
                            flex: 2,
                            sortable: true,
                            sortValue: (item) => item.createDate,
                            builder: (item) {
                              final date = item.createDate;
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