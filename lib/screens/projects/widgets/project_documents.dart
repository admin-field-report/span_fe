import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';

class ProjectDocuments extends StatefulWidget {
    final String projectId;

  const ProjectDocuments({super.key, required this.projectId});

  @override
  State<ProjectDocuments> createState() => _ProjectDocumentsState();
}

class _ProjectDocumentsState extends State<ProjectDocuments> {

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    projectController.getAllDocuments(widget.projectId);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [          
          // The Common Table
          Expanded(
            child: ListenableBuilder(
              listenable: projectController,
              builder: (context, child) {
                return CommonTable<ProjectDocument>(
                  isLoading: projectController.isDocumentsLoading,
                  data: projectController.documents.toList(),
                  showCheckboxes: false,
                  // onRowTap: (item) => debugPrint("Navigating to ${item['id']}"),
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
                      sortable: true,
                      builder: (item) => Text(
                        item.documentName ?? "Unknown", 
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    TableColumn(
                      title: 'Document',
                      flex: 2,
                      sortable: true,
                      builder: (item) => Text(
                        item.documentUrl, 
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, overflow: TextOverflow.ellipsis),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}