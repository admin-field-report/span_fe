import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../widgets/form_components/text_field.dart';
import '../../../../widgets/button/button.dart';
import '../../../../services/toast_service.dart';
import 'package:go_router/go_router.dart';
import '../controllers/report_controller.dart';

class AddReportForm extends StatefulWidget {
  final bool isDesktop;
  const AddReportForm({super.key, required this.isDesktop});

  @override
  State<AddReportForm> createState() => _AddReportFormState();
}

class _AddReportFormState extends State<AddReportForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _reportCreated = false;
  String? _errorMessage;
  List<PlatformFile> _selectedFiles = [];
  ReportCreationPhase? _currentPhase;

  static const Map<ReportCreationPhase, String> _phaseLabels = {
    ReportCreationPhase.creatingTemplate: "Creating report template...",
    ReportCreationPhase.uploadingDocument: "Uploading document...",
    ReportCreationPhase.assigningDocument: "Assigning document to template...",
    ReportCreationPhase.generatingSkills: "Generating report skills...",
  };

  // 🚀 Temporarily restricted to a single document upload from the UI (the
  // presigned-url/upload APIs still support multiple — only this form limits it).
  Future<void> _pickFiles() async {
    if (_selectedFiles.isNotEmpty) {
      setState(() => _errorMessage = "Only one document can be uploaded. Remove the current document to choose another.");
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _errorMessage = null;
          _selectedFiles = [result.files.first];
        });
      }
    } catch (e) {
      debugPrint("File picker error: $e");
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _currentPhase = ReportCreationPhase.creatingTemplate;
    });

    final name = _nameController.text.trim();
    final result = await reportController.createReportWithDocuments(
      name,
      _selectedFiles,
      onPhaseChange: (phase) {
        if (mounted) setState(() => _currentPhase = phase);
      },
    );
    final status = result.status;

    if (!mounted) return;

    if (status == CreateReportStatus.success) {
      ToastService.show(context, message: "Report created successfully", type: ToastType.success);
      reportController.getAllReports(); // Refresh list in the background
      // Routed through go_router (not Navigator.push) so it stays nested
      // inside MainScaffold's shell instead of covering the whole screen.
      final goRouter = GoRouter.of(context);
      Navigator.of(context).pop(); // Auto-close the dialog/sheet
      goRouter.push(
        '/report-placeholder',
        extra: {'templateId': result.reportId, 'templateName': name},
      );
    }
    else if (status == CreateReportStatus.partialSuccess) {
      setState(() {
        _isSubmitting = false;
        _currentPhase = null;
        _reportCreated = true;
        _errorMessage = result.message ?? "Report template created, but there was an issue with document upload.";
      });
    }
    else {
      setState(() {
        _isSubmitting = false;
        _currentPhase = null;
        _errorMessage = "Failed to create report. Please try again.";
      });
    }
  }

  void _handleDismiss() {
    Navigator.pop(context);
    if (_reportCreated) {
      reportController.getAllReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final content = SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Create Report Template",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer, 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  _errorMessage!, 
                  style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                ),
              ),
            
            // 🚀 THE FIX: Only wrap the input fields in AbsorbPointer, NOT the buttons!
            AbsorbPointer(
              absorbing: _isSubmitting || _reportCreated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Template Name", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  FormControlTextField(
                    controller: _nameController,
                    hintText: "e.g., Monthly Inspection Report",
                    prefixIcon: Icons.description_outlined,
                    validator: (val) => val == null || val.trim().isEmpty ? "Name is required" : null,
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      RichText(
                        text: TextSpan(
                          text: "Document",
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface),
                          // children: [
                          //   TextSpan(
                          //     text: "(1 PDF only)",
                          //     style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.normal),
                          //   )
                          // ],
                        ),
                      ),
                      Button(
                        label: "Browse File",
                        icon: Icons.upload_file_rounded,
                        variant: ButtonVariant.outline,
                        onPressed: _selectedFiles.isNotEmpty ? null : _pickFiles,
                      ),
                    ],
                  ),
                  
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedFiles.map((file) {
                          return Chip(
                            label: Text(
                              file.name, 
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            backgroundColor: theme.colorScheme.surface,
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                            deleteIcon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
                            onDeleted: () => setState(() => _selectedFiles.remove(file)),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_isSubmitting && _currentPhase != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _phaseLabels[_currentPhase]!,
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

            // 🚀 The buttons are now permanently accessible
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  label: _reportCreated ? "Close" : "Cancel",
                  variant: ButtonVariant.outline,
                  // Disabled *only* while actively submitting
                  onPressed: _isSubmitting ? null : _handleDismiss,
                ),
                const SizedBox(width: 12),
                Button(
                  label: _reportCreated
                      ? "Created"
                      : (_isSubmitting ? "Please wait..." : "Create Template"),
                  isLoading: _isSubmitting,
                  onPressed: (_isSubmitting || _reportCreated) ? null : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (widget.isDesktop) {
      return Dialog(
        backgroundColor: Colors.transparent, 
        child: Container(
          width: 480, 
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: content,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(
        left: 24, 
        right: 24, 
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: content,
    );
  }
}