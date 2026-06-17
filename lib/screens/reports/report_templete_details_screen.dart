import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import '../../../widgets/button/button.dart';
import './controllers/report_controller.dart';
import '../../services/toast_service.dart';
import './skill_regeneration_progress_screen.dart';

class ReportTemplateDetailsScreen extends StatefulWidget {
  final String templateId;

  const ReportTemplateDetailsScreen({
    super.key,
    required this.templateId,
  });

  @override
  State<ReportTemplateDetailsScreen> createState() => _ReportTemplateDetailsScreenState();
}

class _ReportTemplateDetailsScreenState extends State<ReportTemplateDetailsScreen> {

  @override
  void initState() {
    super.initState();
    reportController.fetchTemplateDetails(widget.templateId);

    reportController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  // ==========================================
  // UPLOAD LOGIC (Multi-file Support)
  // ==========================================
  
  // 🚀 Pass the current document count so we can validate the limit
  Future<void> _pickAndUploadFiles(int currentDocCount) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'], 
      withData: true, 
      allowMultiple: true, // 🚀 ENABLING MULTIPLE FILES
    );

    if (result != null && result.files.isNotEmpty) {
      
      // 🚀 THE LIMIT CHECK: Calculate if this batch pushes them over 5
      if (currentDocCount + result.files.length > 5) {
        if (mounted) {
          int allowedCount = 5 - currentDocCount;
          ToastService.show(
            context, 
            type: ToastType.error, 
            message: allowedCount > 0 
                ? "Limit exceeded. You can only upload $allowedCount more document(s)."
                : "Limit reached. You cannot upload any more documents."
          );
        }
        return;
      }

      // If valid, proceed to confirmation
      _showUploadConfirmation(result.files);
    }
  }

  Future<void> _showUploadConfirmation(List<PlatformFile> files) async {
    final theme = Theme.of(context);
    
    final String fileText = files.length == 1 
        ? "'${files.first.name}'" 
        : "${files.length} documents";

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isUploading = false;
        int currentFileIndex = 0;
        String phaseText = "Preparing upload...";

        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            // 🚀 Helper callback to pass to the execute method
            void updateProgress(int current, int total, String phase) {
              setDialogState(() {
                currentFileIndex = current;
                phaseText = phase;
              });
            }

            return PopScope(
              canPop: !isUploading,
              child: AlertDialog(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                title: Row(
                  children: [
                    Icon(isUploading ? Icons.cloud_upload_rounded : Icons.upload_file_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(isUploading ? "Uploading..." : "Upload Documents"),
                  ],
                ),
                content: isUploading 
                  // 🚀 SHOW PROGRESS UI WHEN UPLOADING
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phaseText, 
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: files.isEmpty ? null : currentFileIndex / files.length,
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            "$currentFileIndex of ${files.length} files",
                            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    )
                  // 🚀 SHOW CONFIRMATION UI BEFORE UPLOADING
                  : Text(
                      "You selected $fileText.\n\nDo you want to update the template's AI skills based on these new documents?",
                      style: theme.textTheme.bodyMedium,
                    ),
                actionsAlignment: MainAxisAlignment.end,
                
                // Hide actions entirely while uploading so user can't interrupt it
                actions: isUploading ? [] : [
                  Button(
                    label: "Cancel",
                    variant: ButtonVariant.outline,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Button(
                    label: "Upload Only",
                    variant: ButtonVariant.outline,
                    onPressed: () async {
                      setDialogState(() => isUploading = true);
                      await _executeUpload(files, updateSkill: false, onProgressUpdate: updateProgress);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                  Button(
                    label: "Upload & Update Skill",
                    onPressed: () async {
                      setDialogState(() => isUploading = true);
                      await _executeUpload(files, updateSkill: true, onProgressUpdate: updateProgress);
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            );
          },
        );
      }
    );
  }

  // 🚀 Pass the progress callback down to the controller
  Future<bool> _executeUpload(
    List<PlatformFile> files, {
    required bool updateSkill, 
    required Function(int current, int total, String phase) onProgressUpdate
  }) async {
    try {
      // 1. Upload files
      onProgressUpdate(0, files.length, "Uploading to secure storage...");
      
      List<Map<String, String>> docsPayload = await reportController.uploadDocumentsToS3(
        widget.templateId, 
        files,
        onProgress: (current, total) {
          onProgressUpdate(current, total, "Uploading to secure storage...");
        }
      );

      if (docsPayload.isEmpty) {
        throw Exception("No documents were successfully uploaded.");
      }

      // 2. Register documents
      onProgressUpdate(files.length, files.length, "Registering files with server...");
      
      final resData = await reportController.addDocuments(
        widget.templateId, 
        docsPayload, 
        updateSkill
      );

      if (mounted) {
        if (updateSkill && resData['job_id'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SkillRegenerationProgressScreen(
                templateId: widget.templateId,
                jobId: resData['job_id'],
                statusEndpoint: resData['status_endpoint'],
              ),
            ),
          ).then((_) => reportController.fetchTemplateDetails(widget.templateId));
        } else {
          ToastService.show(context, type: ToastType.success, message: resData['message'] ?? "Documents uploaded successfully.");
          reportController.fetchTemplateDetails(widget.templateId);
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll("Exception: ", ""));
      }
      return false;
    }
  }

  // ==========================================
  // DELETE LOGIC
  // ==========================================
  Future<void> _showDeleteConfirmation(String docId, String docName) async {
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        bool isDeletingOnly = false;
        bool isDeletingAndUpdate = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isAnyLoading = isDeletingOnly || isDeletingAndUpdate;

            return PopScope(
              canPop: !isAnyLoading,
              child: AlertDialog(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    const Text("Delete Document"),
                  ],
                ),
                content: Text(
                  "Are you sure you want to delete '$docName'?\n\nYou can choose to just delete the document, or delete it and trigger a skill update.",
                  style: theme.textTheme.bodyMedium,
                ),
                actionsAlignment: MainAxisAlignment.end,
                actions: [
                  Button(
                    label: "Cancel",
                    variant: ButtonVariant.outline,
                    onPressed: isAnyLoading ? null : () => Navigator.pop(context),
                  ),
                  Button(
                    label: "Delete Only",
                    variant: ButtonVariant.outline,
                    color: Colors.red,
                    isLoading: isDeletingOnly,
                    onPressed: isAnyLoading ? null : () async {
                      setDialogState(() => isDeletingOnly = true);
                      await _executeDelete(docId, updateSkill: false);
                      if (mounted) Navigator.pop(context); 
                    },
                  ),
                  Button(
                    label: "Delete & Update Skill",
                    color: Colors.red,
                    isLoading: isDeletingAndUpdate, 
                    onPressed: isAnyLoading ? null : () async {
                      setDialogState(() => isDeletingAndUpdate = true);
                      await _executeDelete(docId, updateSkill: true);
                      if (mounted) Navigator.pop(context); 
                    },
                  ),
                ],
              ),
            );
          },
        );
      }
    );
  }

  Future<bool> _executeDelete(String docId, {required bool updateSkill}) async {
    try {
      final resData = await reportController.deleteDocument(docId, updateSkill);

      if (mounted) {
        if (updateSkill && resData['job_id'] != null && resData['status_endpoint'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SkillRegenerationProgressScreen(
                templateId: widget.templateId,
                jobId: resData['job_id'],
                statusEndpoint: resData['status_endpoint'],
              ),
            ),
          ).then((_) => reportController.fetchTemplateDetails(widget.templateId));
          
        } 
        else if (updateSkill && resData['job_id'] == null) {
          ToastService.show(
            context, 
            type: ToastType.success, 
            message: resData['message'] ?? "Document deleted and skills cleared."
          );
          reportController.fetchTemplateDetails(widget.templateId);
        } 
        // 🚀 CASE 3: Standard Delete Only
        else {
          ToastService.show(
            context, 
            type: ToastType.success, 
            message: resData['message'] ?? "Document deleted successfully."
          );
          reportController.fetchTemplateDetails(widget.templateId);
        }
      }
      return true; 
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll("Exception: ", ""));
      }
      return false; 
    }
  }
  
  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return "N/A";
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    } catch (e) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      appBar: AppBar(
        title: const Text("Template Details"),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 1,
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        titleSpacing: 0,
        centerTitle: false,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (reportController.isLoadingTemplateDetails) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              "Loading details...",
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (reportController.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(reportController.errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => reportController.fetchTemplateDetails(widget.templateId),
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            )
          ],
        ),
      );
    }

    if (reportController.templateData == null) {
      return const Center(child: Text("No data found."));
    }

    final data = reportController.templateData!;
    final List documents = data['report_template_document'] ?? [];
    final String skillContent = data['skill_content'] ?? "";

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildHeaderCard(theme, data),
              const SizedBox(height: 24),
              
              // 🚀 UPDATED: Document Section Header with Limit check
              _buildDocumentsSectionHeader(theme, documents.length),
              const SizedBox(height: 12),
              _buildDocumentsSection(theme, documents),
              
              const SizedBox(height: 24),
              
              _buildSectionTitle(theme, "Skill Content", Icons.code_rounded),
              const SizedBox(height: 12),
              _buildSkillContentSection(theme, skillContent),
              
              const SizedBox(height: 40), 
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Map<String, dynamic> data) {
    final user = data['user'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment_rounded, color: theme.colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] ?? "Unnamed Template",
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          _buildInfoRow(
            theme, 
            Icons.person_outline_rounded, 
            "Created By", 
            user != null ? "${user['first_name']} ${user['last_name']}" : "N/A"
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            theme, 
            Icons.calendar_today_rounded, 
            "Created On", 
            _formatDate(data['create_time'])
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildDocumentsSectionHeader(ThemeData theme, int documentCount) {
    bool isLimitReached = documentCount >= 5;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionTitle(theme, "Attached Documents ($documentCount/5)", Icons.description_outlined),
        Tooltip(
          message: isLimitReached ? "Maximum 5 documents allowed" : "Upload new document",
          child: Button(
            label: "Upload",
            icon: Icons.upload_rounded,
            variant: ButtonVariant.outline,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: isLimitReached ? null : () => _pickAndUploadFiles(documentCount),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsSection(ThemeData theme, List documents) {
    if (documents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5), style: BorderStyle.solid),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.folder_off_outlined, size: 32, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text(
                "No documents available",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: documents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final doc = documents[index];
        final docName = doc['name'] ?? "Unknown Document";
        final docId = doc['id'];
        
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.errorContainer.withOpacity(0.5),
              child: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.error, size: 20),
            ),
            title: Text(
              docName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              "Uploaded: ${_formatDate(doc['create_time'])}",
              style: theme.textTheme.bodySmall,
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              tooltip: "Delete Document",
              onPressed: () => _showDeleteConfirmation(docId, docName),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkillContentSection(ThemeData theme, String skillContent) {
    if (skillContent.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Center(
          child: Text(
            "No skill content provided",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: MarkdownBody(
        data: skillContent,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          h2: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold, 
          ),
          listBullet: TextStyle(color: theme.colorScheme.primary),
          code: theme.textTheme.bodySmall?.copyWith(
            backgroundColor: Colors.transparent,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}