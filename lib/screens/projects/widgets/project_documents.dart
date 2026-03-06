import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';

class ProjectDocuments extends StatefulWidget {
    final String projectId;

  const ProjectDocuments({super.key, required this.projectId});

  @override
  State<ProjectDocuments> createState() => _ProjectDocumentsState();
}

class _ProjectDocumentsState extends State<ProjectDocuments> {
  String _searchQuery = "";
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    projectController.getAllDocuments(widget.projectId);
  }

  List<ProjectDocument> _getFilteredDocuments() {
    return projectController.documents.where((p) {
      return p.documentName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> removeDocument(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/templateDocument/$id');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        ToastService.show(context, 
          message: "Document deleted successfully", 
          type: ToastType.success
        );
        projectController.getAllDocuments(widget.projectId);
      } else {
        ToastService.show(context, 
          message: "Unexpected error occurred", 
          type: ToastType.error
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastService.show(context, 
        message: "Failed to delete document: $e", 
        type: ToastType.error
      );
    }
  }

  void _confirmDelete(BuildContext context,  ProjectDocument document) {
    showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: ConfirmationDialog(
              title: "Remove Document",
              description: "Are you sure you want to remove document for '${DateFormat('dd MMM yyyy').format(document.createTime)}'?",
              confirmLabel: "Remove",
              onConfirm: () async => await removeDocument(context, document.id),
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
                      final displayData = _getFilteredDocuments();
                      return CommonTable<ProjectDocument>(
                        isLoading: projectController.isDocumentsLoading,
                        data: displayData,
                        showCheckboxes: false,
                        columns: [
                          TableColumn(
                            title: 'Sr No.',
                            flex: 1,
                            minWidth: 60,
                            builder: (item) {
                              final index = projectController.documents.indexOf(item) + 1;
                              return Text(index.toString().padLeft(2, '0'));
                            },
                          ),
                          TableColumn(
                            title: 'Document Name',
                            flex: 2,
                            sortable: false,
                            builder: (item) => Text(
                              item.documentName,
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          TableColumn(
                            title: 'Created Date',
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
                            builder: (doc) => IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: colorScheme.error,
                              onPressed: () => _confirmDelete(context, doc),
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
              message: 'Refresh Document',
              child: InkWell(
                onTap: projectController.isDocumentsLoading ? null : () {
                  projectController.getAllDocuments(widget.projectId);
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