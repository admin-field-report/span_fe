import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:html_editor_enhanced/html_editor.dart';
import '../../../widgets/widgets.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../controllers/project_controller.dart';
import 'preview_report_pdf_screen.dart';

class GeneratedReportView extends StatefulWidget {
  final String htmlContent;
  final String reportId;
  final String reportURL;

  const GeneratedReportView({super.key, required this.htmlContent, required this.reportId, required this.reportURL});

  @override
  State<GeneratedReportView> createState() => _GeneratedReportViewState();
}

class _GeneratedReportViewState extends State<GeneratedReportView> {
  final ApiService _apiService = ApiService();
  final HtmlEditorController _editorController = HtmlEditorController();
  final TextEditingController _nameController = TextEditingController();

  late String _currentHtml;
  bool _isUpdating = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _currentHtml = widget.htmlContent;
    _fetchReportName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Prefill the mandatory name field with the report's current name.
  Future<void> _fetchReportName() async {
    if (widget.reportId.isEmpty) return;
    try {
      final response = await _apiService.get('/report/getById/${widget.reportId}');
      final responseData = jsonDecode(response.body);
      if (!mounted) return;
      final String? name = responseData['data']?['name'];
      if (name != null && name.isNotEmpty && _nameController.text.isEmpty) {
        setState(() => _nameController.text = name);
      }
    } catch (_) {
      // Best-effort prefill — the user can still type a name manually.
    }
  }

  Future<void> _navigateToPreview() async {
    final didFinish = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewReportPdfScreen(
          reportId: widget.reportId,
          reportName: _nameController.text.trim(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (didFinish == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleSave({required bool navigateToNext}) async {
    if (_isUpdating) return;
    if (widget.reportId.isEmpty) {
      ToastService.show(context, message: "Error: No report ID found.", type: ToastType.error);
      return;
    }

    // Name is mandatory
    final String reportName = _nameController.text.trim();
    if (reportName.isEmpty) {
      setState(() => _nameError = "Report name is required.");
      return;
    }
    setState(() => _nameError = null);

    setState(() => _isUpdating = true);

    try {
      final htmlPayload = await _editorController.getText();
      final payload = {
        "name": reportName,
        "report_url": widget.reportURL,
        };
      final response = await _apiService.patch('/report/update/${widget.reportId}', payload);

      if (response.statusCode == 200) {
        // The update API returns a pre-signed S3 PUT URL. Upload the edited
        // HTML directly to S3 so the stored report reflects the latest edits.
        final responseData = jsonDecode(response.body);
        final String? putSignedUrl = responseData['data']?['putSignedUrl'];
        final String contentType = responseData['data']?['contentType'] ?? 'text/html';

        if (putSignedUrl == null || putSignedUrl.isEmpty) {
          throw Exception("Missing upload URL in server response.");
        }

        final uploadResponse = await http.put(
          Uri.parse(putSignedUrl),
          headers: {'Content-Type': contentType},
          body: utf8.encode(htmlPayload),
        );

        if (uploadResponse.statusCode != 200) {
          throw Exception("Failed to upload report HTML (${uploadResponse.statusCode}).");
        }

        if (mounted) {
          ToastService.show(context, message: "Updated successfully!", type: ToastType.success);
          if (navigateToNext) {
            await _navigateToPreview();
          }
        }
      } else {
        throw Exception("Server failed to update.");
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Error saving: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // Page header in the same shape as the other project screens: breadcrumb
  // (Projects · <project name> · Reports · <report name>) on top, then the
  // title row. No back arrow here on purpose — this step is left via
  // Update & Next. This screen is pushed imperatively on top of the
  // project's reports route, so "Reports" pops back to that route while the
  // other crumbs navigate through the router.
  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final project = projectController.currentProject;
    final String? projectId = project?.id;

    return Container(
      width: double.infinity,
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rebuilds with the name field so the last crumb tracks edits.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _nameController,
            builder: (context, value, _) {
              final String reportName = value.text.trim().isNotEmpty ? value.text.trim() : "Final Report";
              return AppBreadcrumbs(
                items: [
                  BreadcrumbItem(
                    label: "Projects",
                    onTap: () => context.go('/projects'),
                  ),
                  BreadcrumbItem(
                    label: project?.name ?? "Project",
                    onTap: projectId == null || projectId.isEmpty
                        ? null
                        : () => context.go('/projects/details/$projectId/inspections'),
                  ),
                  BreadcrumbItem(
                    label: "Reports",
                    onTap: () => Navigator.of(context).popUntil((route) => route.settings is Page),
                  ),
                  BreadcrumbItem(label: reportName),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            "Final Report",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      body: SafeArea(
        bottom: false,
        child: Stack(
        children: [
          Column(
            children: [
          _buildHeader(theme),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          // 🚀 REPORT NAME (mandatory — sent as `name` in the update API)
          Container(
            width: double.infinity,
            color: colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: FormControlTextField(
              controller: _nameController,
              labelText: "Report Name *",
              hintText: "Enter report name",
              errorText: _nameError,
              textInputAction: TextInputAction.done,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: HtmlEditor(
                    controller: _editorController,
                    htmlEditorOptions: HtmlEditorOptions(
                      initialText: _currentHtml,
                      shouldEnsureVisible: true,
                      darkMode: isDark,
                      customOptions: 'disableResizeEditor: true,', // The trailing comma is critical to prevent JS syntax errors in the package's webview
                    ),
                    htmlToolbarOptions: const HtmlToolbarOptions(
                      toolbarPosition: ToolbarPosition.aboveEditor,
                      toolbarType: ToolbarType.nativeGrid, // Fixes scrollbar context errors & centering
                      defaultToolbarButtons: [
                        StyleButtons(),
                        FontSettingButtons(),
                        FontButtons(clearAll: false),
                        ColorButtons(),
                        ListButtons(listStyles: false),
                        ParagraphButtons(textDirection: false, caseConverter: false, lineHeight: false),
                        InsertButtons(picture: false, audio: false, video: false, otherFile: false), // picture: false removes image picker
                        OtherButtons(fullscreen: false, codeview: false, help: false),
                      ],
                    ),
                    otherOptions: OtherOptions(
                      height: constraints.maxHeight,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // BOTTOM STICKY ACTION BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, -5))
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    label: "Update",
                    variant: ButtonVariant.outline,
                    onPressed: () => _handleSave(navigateToNext: false),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: "Update & Next",
                    variant: ButtonVariant.filled,
                    onPressed: () => _handleSave(navigateToNext: true),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
      if (_isUpdating)
        Container(
          color: Colors.black.withValues(alpha: 0.3),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  "Saving changes...",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    ),
  );
}
}
