import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../controllers/inspection_controller.dart'; 
import '../../projects/controllers/project_controller.dart';
import '../../../core/api_service.dart'; 
import '../../../services/toast_service.dart'; 
import '../../../widgets/button/button.dart'; 
import '../../../widgets/breadcrumb/breadcrumb.dart';

class InspectionDetailsScreen extends StatefulWidget {
  final String inspectionId;

  const InspectionDetailsScreen({
    super.key,
    required this.inspectionId,
  });

  @override
  State<InspectionDetailsScreen> createState() => _InspectionDetailsScreenState();
}

class _InspectionDetailsScreenState extends State<InspectionDetailsScreen> {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspectionController.fetchInspectionDetails(widget.inspectionId);
      
      final projectId = _extractProjectId();
      if (projectId.isNotEmpty) {
        projectController.fetchProjectDetails(projectId);
      }
    });
  }

  String _extractProjectId() {
    final path = GoRouterState.of(context).uri.path;
    final segments = path.split('/');
    final detailsIndex = segments.indexOf('details');
    if (detailsIndex != -1 && detailsIndex + 1 < segments.length) {
      return segments[detailsIndex + 1];
    }
    return ''; 
  }

  Future<void> _openAssignDocumentModal(BuildContext context, ThemeData theme) async {
    final isWeb = MediaQuery.of(context).size.width > 600;
    final projectId = _extractProjectId();

    bool? assignmentSuccessful;

    if (isWeb) {
      assignmentSuccessful = await showDialog<bool>(
        context: context,
        barrierDismissible: false, 
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
            child: _AssignDocumentModalContent(
              inspectionId: widget.inspectionId,
              projectId: projectId,
              theme: theme,
              alreadyAssignedDocuments: inspectionController.documents, 
            ),
          ),
        ),
      );
    } else {
      assignmentSuccessful = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false, 
        enableDrag: false,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            child: _AssignDocumentModalContent(
              inspectionId: widget.inspectionId,
              projectId: projectId,
              theme: theme,
              alreadyAssignedDocuments: inspectionController.documents, 
            ),
          ),
        ),
      );
    }

    if (assignmentSuccessful == true && mounted) {
      inspectionController.fetchInspectionDetails(widget.inspectionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: inspectionController,
      builder: (context, _) {
        
        if (inspectionController.isDetailsLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text("Loading inspection details...", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        if (inspectionController.detailsError != null) {
          return _buildErrorState(theme);
        }

        if (inspectionController.documents.isEmpty && inspectionController.mediaUrls.isEmpty) {
          return _buildEmptyState(context, theme);
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListenableBuilder(
                  listenable: projectController,
                  builder: (context, _) => _buildHeader(context, theme),
                ),
                
                const SizedBox(height: 32),
                
                _buildSectionTitle(
                  title: "Documents", 
                  count: inspectionController.documents.length, 
                  theme: theme,
                  trailing: Button(
                    label: "Assign",
                    variant: ButtonVariant.outline,
                    icon: Icons.add_link_rounded,
                    onPressed: () => _openAssignDocumentModal(context, theme),
                  ),
                ),
                const SizedBox(height: 16),
                _buildDocumentsList(theme, inspectionController.documents),
                
                const SizedBox(height: 40),
                
                _buildSectionTitle(
                  title: "Inspection Media", 
                  count: inspectionController.mediaUrls.length, 
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildMediaGrid(theme, inspectionController.mediaUrls),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final projectId = _extractProjectId();
    final projectName = projectController.currentProject?.name ?? "Loading...";

    String inspectionLabel = "Inspection details";
    
    // 🚀 READ DIRECTLY FROM THE CONTROLLER'S CLEAN STATE
    final activeInspection = inspectionController.currentInspection;
    
    if (activeInspection != null) {
      final rawDate = activeInspection.createTime; 
      final parsedDate = rawDate is DateTime 
          ? rawDate 
          : DateTime.tryParse(rawDate.toString());
          
      if (parsedDate != null) {
        inspectionLabel = "Inspection - ${DateFormat('dd MMM yyyy').format(parsedDate)}";
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(
              label: "Projects",
              onTap: () => context.go('/projects'),
            ),
            BreadcrumbItem(
              label: projectName,
              onTap: () {
                if (projectId.isNotEmpty) {
                  context.go('/projects/details/$projectId/inspections');
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            BreadcrumbItem(
              label: inspectionLabel, 
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Text(
              "Inspection Detail",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle({
    required String title, 
    required int count, 
    required ThemeData theme,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ],
    );
  }

  Widget _buildDocumentsList(ThemeData theme, List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return _buildEmptySection(theme, "No documents attached.");
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: documents.length,
      itemBuilder: (context, index) {
        final doc = documents[index];
        final docName = doc['document_name'] ?? 'Document ${index + 1}'; 
        final docDescription = doc['description']?.toString().trim() ?? ''; 

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final String documentId = doc['id']; 

                final currentPath = GoRouterState.of(context).uri.path;
                final cleanPath = currentPath.endsWith('/') 
                    ? currentPath.substring(0, currentPath.length - 1) 
                    : currentPath;
                    
                final canvasUrl = '$cleanPath/canvas';

                context.go(
                  canvasUrl,
                  extra: {
                    'documentId': documentId,
                    'onRefresh': () {
                      if (mounted) {
                        inspectionController.fetchInspectionDetails(widget.inspectionId);
                      }
                    },
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (docDescription.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            RichText(
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Summary: ', 
                                    style: TextStyle(fontWeight: FontWeight.bold)
                                  ),
                                  TextSpan(text: docDescription),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaGrid(ThemeData theme, List<String> mediaUrls) {
    if (mediaUrls.isEmpty) {
      return _buildEmptySection(theme, "No media attached.");
    }

    return GridView.builder(
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250, 
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0, 
      ),
      itemCount: mediaUrls.length,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              mediaUrls[index],
              fit: BoxFit.cover, 
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SkeletonContainer(
                  width: double.infinity,
                  height: double.infinity,
                ); 
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            inspectionController.detailsError!,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => inspectionController.fetchInspectionDetails(widget.inspectionId),
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined, size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            "No Data Found",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "This inspection doesn't have any documents or media yet.",
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Go Back"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySection(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, color: theme.colorScheme.outlineVariant, size: 32),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }
}

// =========================================================
// ASSIGN DOCUMENT MODAL CONTENT 
// =========================================================
class _AssignDocumentModalContent extends StatefulWidget {
  final String inspectionId;
  final String projectId;
  final ThemeData theme;
  final List<dynamic> alreadyAssignedDocuments;

  const _AssignDocumentModalContent({
    required this.inspectionId,
    required this.projectId,
    required this.theme,
    required this.alreadyAssignedDocuments,
  });

  @override
  State<_AssignDocumentModalContent> createState() => _AssignDocumentModalContentState();
}

class _AssignDocumentModalContentState extends State<_AssignDocumentModalContent> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  List<dynamic> _allDocuments = [];
  bool _isSubmitting = false;
  
  bool _isPolling = false;

  final Set<String> _selectedDocumentIds = {};
  late Set<String> _alreadyAssignedIds;

  bool get _isAnyDocumentProcessing {
    return _allDocuments.any((doc) => doc['status']?.toString().toLowerCase().trim() == 'processing');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _alreadyAssignedIds = widget.alreadyAssignedDocuments.map((d) => d['parent_project_document_id'].toString()).toSet();
    _fetchProjectDocuments();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _isPolling = false; 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndStartPolling();
    } else {
      _isPolling = false; 
    }
  }

  void _checkAndStartPolling() {
    if (!mounted) return;
    
    if (_isAnyDocumentProcessing) {
      if (!_isPolling) {
        _startPollingLoop();
      }
    } else {
      _isPolling = false; 
    }
  }

  Future<void> _startPollingLoop() async {
    _isPolling = true;
    
    while (_isPolling && mounted) {
      await Future.delayed(const Duration(seconds: 10));
      
      if (!_isPolling || !mounted) break;
      
      await _fetchProjectDocuments(isPolling: true);
    }
  }

  Future<void> _fetchProjectDocuments({bool isPolling = false}) async {
    if (!isPolling) setState(() => _isLoading = true);

    try {
      final response = await _apiService.get('/projectDocument/project/${widget.projectId}');
      
      if (!mounted) return;
      final docData = jsonDecode(response.body);
      
      if (docData['success'] == true && docData['data'] != null) {
        List<dynamic> fetchedDocuments = docData['data'];
        
        fetchedDocuments.sort((a, b) {
          final dateA = DateTime.tryParse(a['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dateB = DateTime.tryParse(b['create_time']?.toString() ?? "") ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dateB.compareTo(dateA);
        });

        setState(() {
          _allDocuments = fetchedDocuments;
          if (!isPolling) _isLoading = false;
        });
        
        _checkAndStartPolling(); 
      } else {
        if (!isPolling) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted && !isPolling) setState(() => _isLoading = false);
    }
  }

  void _toggleDocumentSelection(String id, bool? value) {
    setState(() {
      if (value == true) {
        _selectedDocumentIds.add(id);
      } else {
        _selectedDocumentIds.remove(id);
      }
    });
  }

  Future<void> _submitAssignment() async {
    if (_isSubmitting || _selectedDocumentIds.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId,
        "project_document_id_list": _selectedDocumentIds.toList(),
      };

      final response = await _apiService.post('/inspection/add-project-document-to-inspection', payload);
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['success'] == true) {
          ToastService.show(context, message: "Documents assigned successfully", type: ToastType.success);
          Navigator.pop(context, true);
        } else {
          ToastService.show(context, message: responseData['message'] ?? "Failed to assign documents.", type: ToastType.error);
        }
      } else {
        ToastService.show(context, message: responseData['message'] ?? "Failed to assign documents", type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Network error occurred.", type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildStatusBadge(String? statusStr, ThemeData theme) {
    final status = (statusStr ?? 'unknown').toLowerCase().trim();
    Color bgColor;
    Color textColor;
    String label = statusStr ?? 'Unknown';

    switch (status) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'processing') ...[
            SizedBox(
              width: 8, 
              height: 8, 
              child: CircularProgressIndicator(strokeWidth: 2, color: textColor)
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(dynamic doc, ColorScheme colorScheme, ThemeData theme) {
    final date = DateTime.tryParse(doc['create_time'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMM yyyy').format(date) : 'Unknown Date';
    final name = doc['document_name'] ?? doc['document_url']?.split('/').last ?? 'Unnamed Document';
    
    final status = doc['status']?.toString().toLowerCase().trim() ?? 'unknown'; 
    final docId = doc['id'].toString();

    final bool isAlreadyAssigned = _alreadyAssignedIds.contains(docId);
    final bool isProcessing = status == 'processing';
    final bool isCompleted = status == 'completed';
    
    final bool isAvailable = isCompleted && !isAlreadyAssigned;
    final bool isChecked = isAlreadyAssigned || _selectedDocumentIds.contains(docId);
    final bool isBorderHighlighted = _selectedDocumentIds.contains(docId);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isBorderHighlighted ? colorScheme.primary : colorScheme.outlineVariant.withOpacity(0.5), 
          width: isBorderHighlighted ? 1.5 : 1.0
        ),
      ),
      child: ListTile(
        onTap: isAvailable && !_isSubmitting ? () => _toggleDocumentSelection(docId, !isChecked) : null,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: isChecked,
              onChanged: isAvailable && !_isSubmitting ? (val) => _toggleDocumentSelection(docId, val) : null,
            ),
            Icon(Icons.description_outlined, color: isAvailable ? colorScheme.primary : theme.disabledColor),
          ],
        ),
        title: Text(
          name, 
          style: TextStyle(fontWeight: FontWeight.w500, color: isAvailable ? null : theme.disabledColor)
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Created: $dateStr", 
              style: TextStyle(fontSize: 12, color: isAvailable ? null : theme.disabledColor)
            ),
            if (isAlreadyAssigned) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "This document already exists in this inspection.",
                      style: TextStyle(fontSize: 12, color: colorScheme.outline, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: _buildStatusBadge(status, theme), 
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.theme.colorScheme;
    final theme = widget.theme;

    final availableDocsToAssign = _allDocuments.where((d) => 
      d['status']?.toString().toLowerCase().trim() == 'completed' && 
      !_alreadyAssignedIds.contains(d['id'].toString())
    ).toList();
    
    final bool allAvailableSelected = availableDocsToAssign.isNotEmpty && 
      availableDocsToAssign.every((d) => _selectedDocumentIds.contains(d['id'].toString()));

    return PopScope(
      canPop: !_isSubmitting,
      child: AbsorbPointer(
        absorbing: _isSubmitting,
        child: Stack(
          children: [
            Material(
              color: Colors.transparent,
              child: Container(
                color: colorScheme.surfaceContainer,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Assign Documents", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    Flexible(
                      child: _isLoading 
                        ? Padding(
                            padding: const EdgeInsets.all(40.0),
                            child: CircularProgressIndicator(color: colorScheme.primary),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                
                                if (_isAnyDocumentProcessing)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 16, 
                                          height: 16, 
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber[800])
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "Some documents are currently processing. You can assign them once processing is complete.", 
                                            style: TextStyle(color: Colors.amber[900], fontSize: 13, fontWeight: FontWeight.w500)
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                if (_allDocuments.isEmpty)
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 40),
                                      Icon(
                                        Icons.description_outlined, 
                                        size: 48, 
                                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3)
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        "No template documents available.", 
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold, 
                                          color: theme.colorScheme.onSurfaceVariant
                                        )
                                      ),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                        child: Text(
                                          "Please upload a document from Project Documents first.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13, 
                                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0, left: 4.0, right: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Checkbox(
                                              value: availableDocsToAssign.isEmpty ? false : allAvailableSelected,
                                              onChanged: availableDocsToAssign.isEmpty ? null : (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedDocumentIds.addAll(availableDocsToAssign.map((d) => d['id'].toString()));
                                                  } else {
                                                    _selectedDocumentIds.removeAll(availableDocsToAssign.map((d) => d['id'].toString()));
                                                  }
                                                });
                                              },
                                            ),
                                            Text("Select All", style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                        Text(
                                          "${_selectedDocumentIds.length} Selected", 
                                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold)
                                        ),
                                      ],
                                    ),
                                  ),

                                  ..._allDocuments.map((doc) => _buildDocumentCard(doc, colorScheme, theme)),
                                ],
                              ],
                            ),
                          ),
                    ),
                    
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(20.0),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Button(
                              label: "Cancel",
                              variant: ButtonVariant.outline,
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 16),
                            Button(
                              label: "Assign",
                              variant: ButtonVariant.filled,
                              onPressed: _selectedDocumentIds.isEmpty ? null : _submitAssignment,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            if (_isSubmitting)
              Positioned.fill(
                child: Container(
                  color: colorScheme.surfaceContainer.withOpacity(0.6), 
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          )
                        ]
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            "Assigning Documents...",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SkeletonContainer extends StatefulWidget {
  final double? width;
  final double? height;
  final bool isCircle;

  const SkeletonContainer({
    super.key,
    this.width,
    this.height,
    this.isCircle = false,
  });

  @override
  State<SkeletonContainer> createState() => _SkeletonContainerState();
}

class _SkeletonContainerState extends State<SkeletonContainer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true); 
    
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine)
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle ? null : BorderRadius.circular(12),
        ),
      ),
    );
  }
}