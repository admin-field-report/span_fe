import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../widgets/button/button.dart';
import './controllers/report_controller.dart';
import '../../services/toast_service.dart';
import './skill_regeneration_progress_screen.dart';
import '../report_placeholder/models/report_element.dart';
import '../report_placeholder/region_html_codec.dart';

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
  final _nameFormKey = GlobalKey<FormState>();
  final _nameEditController = TextEditingController();
  bool _isEditingName = false;
  bool _isSavingName = false;
  int _previewIdCounter = 0;

  final _skillEditController = TextEditingController();
  bool _isEditingSkill = false;
  bool _isSavingSkill = false;

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    reportController.fetchTemplateDetails(widget.templateId);
    reportController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    reportController.removeListener(_onControllerChanged);
    _nameEditController.dispose();
    _skillEditController.dispose();
    super.dispose();
  }

  void _startEditingName(String currentName) {
    _nameEditController.text = currentName;
    setState(() => _isEditingName = true);
  }

  Future<void> _saveTemplateName() async {
    if (!(_nameFormKey.currentState?.validate() ?? false)) return;
    final newName = _nameEditController.text.trim();

    setState(() => _isSavingName = true);
    try {
      await reportController.updateReportTemplateFields(widget.templateId, {'name': newName});
      if (!mounted) return;
      setState(() {
        reportController.templateData?['name'] = newName;
        _isEditingName = false;
      });
      ToastService.show(context, message: "Name updated successfully", type: ToastType.success);
      reportController.getAllReports(); // keep the reports list in sync
    } catch (e) {
      if (!mounted) return;
      ToastService.show(context, message: e.toString().replaceAll("Exception: ", ""), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSavingName = false);
    }
  }

  void _startEditingSkill(String current) {
    _skillEditController.text = current;
    setState(() => _isEditingSkill = true);
  }

  Future<void> _saveSkillContent() async {
    final newSkill = _skillEditController.text;

    setState(() => _isSavingSkill = true);
    try {
      await reportController.updateReportTemplateFields(widget.templateId, {
        'skill_content': newSkill,
      });
      if (!mounted) return;
      setState(() {
        final data = reportController.templateData;
        if (data != null) {
          // final bodyConfig = (data['body_config'] as Map?) ?? <String, dynamic>{};
          data['skill_content'] = newSkill;
        }
        _isEditingSkill = false;
      });
      ToastService.show(context, message: "Updated successfully", type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      ToastService.show(context, message: e.toString().replaceAll("Exception: ", ""), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSavingSkill = false);
    }
  }

  // ==========================================
  // UPLOAD LOGIC (Single document only)
  // ==========================================

  // 🚀 Pass the current document count so we can validate the limit
  Future<void> _pickAndUploadFiles(int currentDocCount) async {
    if (currentDocCount >= 1) {
      ToastService.show(context, type: ToastType.error, message: "Only one document is allowed. Remove the current document to upload another.");
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: true,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      _showUploadConfirmation([result.files.first]);
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
                backgroundColor: theme.scaffoldBackgroundColor,
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
                      "You selected $fileText. Upload it to this template?",
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
                    label: "Upload",
                    onPressed: () async {
                      setDialogState(() => isUploading = true);
                      await _executeUpload(files, updateSkill: false, onProgressUpdate: updateProgress);
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
        bool isDeleting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isDeleting,
              child: AlertDialog(
                backgroundColor: theme.scaffoldBackgroundColor,
                title: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    const Text("Delete Document"),
                  ],
                ),
                content: Text(
                  "Are you sure you want to delete '$docName'?",
                  style: theme.textTheme.bodyMedium,
                ),
                actionsAlignment: MainAxisAlignment.end,
                actions: [
                  Button(
                    label: "Cancel",
                    variant: ButtonVariant.outline,
                    onPressed: isDeleting ? null : () => Navigator.pop(context),
                  ),
                  Button(
                    label: "Delete",
                    color: Colors.red,
                    isLoading: isDeleting,
                    onPressed: isDeleting ? null : () async {
                      setDialogState(() => isDeleting = true);
                      await _executeDelete(docId, updateSkill: false);
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
    final String skillContent = (data['skill_content'] as String?) ?? "";

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildHeaderCard(theme, data),
              const SizedBox(height: 32),

              _buildReportPlaceholderSection(theme, data),
              const SizedBox(height: 32),

              // 🚀 UPDATED: Document Section Header with Limit check
              _buildDocumentsSectionHeader(theme, documents.length),
              const SizedBox(height: 12),
              _buildDocumentsSection(theme, documents),

              const SizedBox(height: 32),

              _buildSkillSection(theme, skillContent),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Map<String, dynamic> data) {
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
                child: _isEditingName
                    ? Form(
                        key: _nameFormKey,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _nameEditController,
                                autofocus: true,
                                enabled: !_isSavingName,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                validator: (val) => val == null || val.trim().isEmpty ? "Name is required" : null,
                                onFieldSubmitted: (_) => _saveTemplateName(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (_isSavingName)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else ...[
                              IconButton(
                                icon: const Icon(Icons.check_rounded, color: Colors.green),
                                tooltip: "Save",
                                onPressed: _saveTemplateName,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: "Cancel",
                                onPressed: () => setState(() => _isEditingName = false),
                              ),
                            ],
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          Flexible(
                            child: Text(
                              data['name'] ?? "Unnamed Template",
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: "Edit name",
                            onPressed: () => _startEditingName(data['name'] ?? ''),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportPlaceholderSection(ThemeData theme, Map<String, dynamic> data) {
    String previewNextId() => 'preview_${DateTime.now().microsecondsSinceEpoch}_${_previewIdCounter++}';

    final header = parseRegionHtml(
      regionHtml: data['header_html'] as String?,
      regionType: ReportElementType.header,
      nextId: previewNextId,
    );
    final footer = parseRegionHtml(
      regionHtml: data['footer_html'] as String?,
      regionType: ReportElementType.footer,
      nextId: previewNextId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(theme, "Report Placeholder", Icons.dashboard_customize_outlined),
            Button(
              label: "Edit",
              icon: Icons.edit_outlined,
              variant: ButtonVariant.outline,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: () async {
                final didSave = await context.push<bool>(
                  '/report-placeholder',
                  extra: {'templateId': widget.templateId, 'templateName': data['name']},
                );
                // Only refetch if something was actually saved there, not
                // on every plain back navigation.
                if (didSave == true && mounted) {
                  reportController.fetchTemplateDetails(widget.templateId);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: header == null && footer == null
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Center(
                    child: Text(
                      "No header or footer configured yet",
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (header != null) _buildRegionPreview(theme, "Header", header),
                    if (header != null && footer != null) const SizedBox(height: 16),
                    if (footer != null) _buildRegionPreview(theme, "Footer", footer),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRegionPreview(ThemeData theme, String label, ReportElement region) {
    const previewPageWidth = 816.0;
    final regionHeight = region.size.height > 0 ? region.size.height : 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: AspectRatio(
              aspectRatio: previewPageWidth / regionHeight,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: previewPageWidth,
                  height: regionHeight,
                  child: Container(
                    color: region.backgroundColor,
                    child: Stack(
                      children: [
                        for (final child in region.children) _buildPreviewChild(child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewChild(ReportElement child) {
    if (child.type == ReportElementType.infoBar) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: child.size.height,
        child: Container(
          color: child.backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            children: [
              Text(child.text, style: TextStyle(color: child.color, fontSize: child.fontSize)),
              const Spacer(),
              Text(child.secondaryText, style: TextStyle(color: child.color, fontSize: child.fontSize)),
            ],
          ),
        ),
      );
    }

    if (child.type == ReportElementType.logo) {
      return Positioned(
        left: child.position.dx,
        top: child.position.dy,
        child: Container(
          width: child.size.width,
          height: child.size.height,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), color: Colors.grey.shade100),
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined, color: Colors.grey.shade500, size: 18),
        ),
      );
    }

    // Center/right-aligned text (e.g. the header "Centered" style's
    // companyName/address) is given a full-width box by the codec
    // specifically so alignment has something to align within — without
    // reproducing that width here too, it'd render left-aligned at x:0
    // regardless of `align`, same as the bug just fixed in the main editor.
    final text = Text(
      child.text,
      textAlign: child.align,
      style: TextStyle(
        fontSize: child.fontSize,
        fontWeight: child.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: child.isItalic ? FontStyle.italic : FontStyle.normal,
        color: child.color,
      ),
    );

    return Positioned(
      left: child.position.dx,
      top: child.position.dy,
      child: child.size.width > 0 ? SizedBox(width: child.size.width, child: text) : text,
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
    bool isLimitReached = documentCount >= 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionTitle(theme, "Attached Document ($documentCount/1)", Icons.description_outlined),
        Tooltip(
          message: isLimitReached ? "Only one document allowed" : "Upload document",
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
        final isDocx = docName.toLowerCase().endsWith('.docx');

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: isDocx
                  ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                  : theme.colorScheme.errorContainer.withOpacity(0.5),
              child: Icon(
                isDocx ? Icons.description_rounded : Icons.picture_as_pdf_rounded,
                color: isDocx ? theme.colorScheme.primary : theme.colorScheme.error,
                size: 20,
              ),
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

  Widget _buildSkillSection(ThemeData theme, String skillContent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle(theme, "Additional AI Prompt to Generate Report", Icons.auto_awesome_outlined),
            if (!_isEditingSkill)
              Button(
                label: "Edit",
                icon: Icons.edit_outlined,
                variant: ButtonVariant.outline,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: () => _startEditingSkill(skillContent),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: _isEditingSkill ? _buildSkillEditor(theme) : _buildSkillViewer(theme, skillContent),
        ),
      ],
    );
  }

  Widget _buildSkillEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _skillEditController,
          enabled: !_isSavingSkill,
          minLines: 6,
          maxLines: 16,
          style: theme.textTheme.bodyMedium,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Enter the AI prompt/skill used to generate this report...",
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Button(
              label: "Cancel",
              variant: ButtonVariant.outline,
              onPressed: _isSavingSkill ? null : () => setState(() => _isEditingSkill = false),
            ),
            const SizedBox(width: 8),
            Button(
              label: "Save",
              isLoading: _isSavingSkill,
              onPressed: _isSavingSkill ? null : _saveSkillContent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSkillViewer(ThemeData theme, String skillContent) {
    if (skillContent.trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Center(
          child: Text(
            "No prompt provided",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return MarkdownBody(
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
    );
  }
}