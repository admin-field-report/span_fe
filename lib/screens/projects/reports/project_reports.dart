import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';
import './create_report_screen.dart';

class ProjectReports extends StatefulWidget {
    final String projectId;

  const ProjectReports({super.key, required this.projectId});

  @override
  State<ProjectReports> createState() => _ProjectReportsState();
}

class _ProjectReportsState extends State<ProjectReports> {
  String _searchQuery = "";
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    projectController.getAllReports(widget.projectId);
  }

  List<ProjectReport> _getFilteredReports() {
    return projectController.reports.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
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
                      final displayData = _getFilteredReports();
                      return CommonTable<ProjectReport>(
                        isLoading: projectController.isReportLoading,
                        data: displayData,
                        showCheckboxes: false,
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
                            sortable: false,
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
                            builder: (item) => Text(
                              DateFormat('dd MMM yyyy').format(item.createDate),
                            ),
                          ),
                          TableColumn(
                            title: "Actions",
                            flex: 0,
                            minWidth: 100,
                            builder: (report) => IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: colorScheme.error,
                              onPressed: () => _confirmDelete(context, report),
                            ),
                          ),
                        ],
                      );
                    }
                  )  
                ]
              )
            )
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
              // Let it fill space on mobile, constrain to 350 on desktop
              width: isDesktop ? 350 : double.infinity, 
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) const Spacer(),
          if (!isDesktop) const SizedBox(width: 12), // Add breathing room on mobile

          // Refresh Button (Desktop Only)
          if (isDesktop) ...[
            Tooltip(
              message: 'Refresh Reports',
              child: InkWell(
                onTap: projectController.isReportLoading ? null : () {
                  projectController.getAllReports(widget.projectId);
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

          // 🚀 THE NEW CREATE REPORT BUTTON
          // 🚀 THE NEW CREATE REPORT BUTTON
          Button(
            label: isDesktop ? "Create Report" : "Create", 
            variant: ButtonVariant.filled,
            icon: Icons.add,
            onPressed: () async {
              // Push the new screen and wait for it to return true
              final didCreate = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateReportScreen(projectId: widget.projectId)),
              );

              // If report was created successfully, refresh the table!
              if (didCreate == true && mounted) {
                projectController.getAllReports(widget.projectId);
              }
            },
          ),
        ],
      )
    );
  }
}