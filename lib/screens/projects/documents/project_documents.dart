import 'dart:async';
import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';
import './upload_document_panel.dart';
import './document_pdf_viewer.dart'; 

class ProjectDocuments extends StatefulWidget {
  final String projectId;

  const ProjectDocuments({super.key, required this.projectId});

  @override
  State<ProjectDocuments> createState() => _ProjectDocumentsState();
}

class _ProjectDocumentsState extends State<ProjectDocuments> with WidgetsBindingObserver {
  String _searchQuery = "";
  final ApiService _apiService = ApiService();
  
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    projectController.addListener(_checkAndStartPolling); 
    projectController.getAllDocuments(widget.projectId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    projectController.removeListener(_checkAndStartPolling);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndStartPolling();
    } else {
      _stopPolling();
    }
  }

  void _checkAndStartPolling() {
    if (!mounted) return;
    
    bool needsPolling = projectController.documents.any((doc) => 
      doc.status.trim().toLowerCase() == 'processing'
    );

    if (needsPolling) {
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
          if (mounted) {
            projectController.getAllDocuments(widget.projectId);
          }
        });
      }
    } else {
      _stopPolling(); 
    }
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Widget _buildStatusBadge(String status, ThemeData theme) {
    Color bgColor;
    Color textColor;
    String label = status;

    switch (status.toLowerCase()) {
      case 'processing':
        bgColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue[800]!;
        label = 'Processing';
        break;
      case 'completed':
        bgColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green[800]!;
        label = 'Completed';
        break;
      case 'failed':
        bgColor = Colors.red.withOpacity(0.1);
        textColor = Colors.red[800]!;
        label = 'Failed';
        break;
      default:
        bgColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.toLowerCase() == 'processing') ...[
            SizedBox(
              width: 10, 
              height: 10, 
              child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  List<ProjectDocument> _getFilteredDocuments() {
    return projectController.documents.where((p) {
      return p.documentName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> removeDocument(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/projectDocument/$id');
      if (!context.mounted) return;

      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
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
              description: "Are you sure you want to remove document '${document.documentName}'?",
              confirmLabel: "Remove",
              onConfirm: () async => await removeDocument(context, document.id),
            ),
          ),
        ),
      );
  }

  void _showUploadPanel() async {
    final isMobile = AppResponsive.isMobileScreen(context);

    final didUpload = await (isMobile 
        ? showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: UploadDocumentPanel(projectId: widget.projectId),
            ),
          )
        : showDialog<bool>(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 500, 
                child: UploadDocumentPanel(projectId: widget.projectId),
              ),
            ),
          ));

    if (didUpload == true && mounted) {
      projectController.getAllDocuments(widget.projectId);
    }
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
            const SizedBox(height: 10),
            
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    _buildTopToolbar(theme),
                    const SizedBox(height: 10),
                    
                    Expanded(
                      child: ListenableBuilder(
                        listenable: projectController,
                        builder: (context, child) {
                          final displayData = _getFilteredDocuments();
                          return CommonTable<ProjectDocument>(
                            isLoading: projectController.isDocumentsLoading,
                            data: displayData,
                            showCheckboxes: false,
                            // 🚀 ADDED ROW TAP TO OPEN THE PDF VIEWER
                            onRowTap: (doc) {
                              if (doc.status.toLowerCase() == 'completed') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DocumentPdfViewerScreen(
                                      documentId: doc.id,
                                      documentName: doc.documentName,
                                    ),
                                  ),
                                );
                              } else {
                                ToastService.show(
                                  context, 
                                  message: "Document is still processing.", 
                                  type: ToastType.warning
                                );
                              }
                            },
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
                                sortValue: (item) => item.documentName,
                                builder: (item) => Text(
                                  item.documentName,
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                              
                              TableColumn(
                                title: 'Status',
                                flex: 1,
                                sortable: true,
                                sortValue: (item) => item.status, 
                                builder: (item) => _buildStatusBadge(item.status, theme), 
                              ),

                              TableColumn(
                                title: 'Created Date',
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
                                    const SizedBox(height: 2), 
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
                              TableColumn(
                                title: "Actions",
                                flex: 0,
                                minWidth: 60, 
                                isStickyRight: true, 
                                builder: (doc) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      color: colorScheme.error,
                                      onPressed: () => _confirmDelete(context, doc),
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
          Expanded(
            child: SearchField(
              width: isDesktop ? 350 : double.infinity,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) const Spacer(),
          if (!isDesktop) const SizedBox(width: 12),

          if (isDesktop) ...[
            Tooltip(
              message: 'Refresh Documents',
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
            const SizedBox(width: 16),
          ],

          Button(
            label: isDesktop ? "Upload Document" : "Upload", 
            variant: ButtonVariant.filled,
            icon: Icons.upload_file, 
            onPressed: () => _showUploadPanel(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ],
      )
    );
  }
}