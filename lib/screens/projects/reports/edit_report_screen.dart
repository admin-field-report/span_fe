import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:html_editor_enhanced/html_editor.dart';

import '../../../core/api_service.dart';
import '../../../widgets/widgets.dart';
import '../../../services/toast_service.dart';
import '../controllers/project_controller.dart';

class EditReportScreen extends StatefulWidget {
  final String reportId;

  const EditReportScreen({super.key, required this.reportId});

  @override
  State<EditReportScreen> createState() => _EditReportScreenState();
}

class _EditReportScreenState extends State<EditReportScreen> {
  final ApiService _apiService = ApiService();
  final HtmlEditorController _editorController = HtmlEditorController();
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = true;
  bool _isUpdating = false;
  String _currentHtml = "";
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _fetchReportDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 🚀 FETCH REPORT NAME + HTML (HTML is stored in S3, fetched via pre-signed URL)
  Future<void> _fetchReportDetails() async {
    try {
      final response = await _apiService.get('/report/getById/${widget.reportId}');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      final data = responseData['data'];
      if (data == null) {
        setState(() => _isLoading = false);
        return;
      }

      final String reportName = data['name'] ?? "";

      final preSignedResponse = await _apiService.get('/report/preSignedUrl/${widget.reportId}');
      final preSignedData = jsonDecode(preSignedResponse.body)['data'];
      final String? preSignedUrl = preSignedData?['preSignedUrl'];

      String html = "";
      if (preSignedUrl != null && preSignedUrl.isNotEmpty) {
        final htmlResponse = await http.get(Uri.parse(preSignedUrl));
        if (htmlResponse.statusCode == 200) {
          html = utf8.decode(htmlResponse.bodyBytes);
        }
      }

      if (!mounted) return;
      setState(() {
        _currentHtml = html;
        _nameController.text = reportName;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Failed to load report.", type: ToastType.error);
        setState(() => _isLoading = false);
      }
    }
  }

  // 🚀 SAVE EDITED HTML
  Future<void> _handleUpdateReport() async {
    if (_isUpdating) return;

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

      final payload = {"name": reportName};
      final response = await _apiService.patch('/report/update/${widget.reportId}', payload);

      if (response.statusCode == 200) {
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
          ToastService.show(context, message: "Report updated successfully!", type: ToastType.success);
          Navigator.pop(context, true); // Refresh table
        }
      } else {
        throw Exception("Server failed to update.");
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Update failed: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // Page header in the same shape as the other project screens: breadcrumb
  // (Projects · <project name> · Reports · <report name>) on top, then a back
  // arrow + title row. This screen is pushed imperatively on top of the
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
              final String reportName = value.text.trim().isNotEmpty ? value.text.trim() : "Edit Report";
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(
                "Edit Report",
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
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
        child: Column(
          children: [
            // Header stays visible during save but can't be tapped.
            AbsorbPointer(
              absorbing: _isUpdating,
              child: _buildHeader(theme),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            Expanded(
              child: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🚀 REPORT NAME (mandatory — sent as `name` in the update API)
                Container(
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

                // 🚀 MAIN CONTENT AREA (Full Width & Height)
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
                            customOptions: 'disableResizeEditor: true,', // The trailing comma is critical
                          ),
                          htmlToolbarOptions: const HtmlToolbarOptions(
                            toolbarPosition: ToolbarPosition.aboveEditor,
                            toolbarType: ToolbarType.nativeGrid,
                            defaultToolbarButtons: [
                              StyleButtons(),
                              FontSettingButtons(),
                              FontButtons(clearAll: false),
                              ColorButtons(),
                              ListButtons(listStyles: false),
                              ParagraphButtons(textDirection: false, caseConverter: false, lineHeight: false),
                              InsertButtons(picture: false, audio: false, video: false, otherFile: false),
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

                // 🚀 SAVE ACTION BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))
                    ]
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Button(
                          label: "Cancel",
                          variant: ButtonVariant.outline,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Button(
                          label: "Save Changes",
                          icon: Icons.check_circle_outline,
                          variant: ButtonVariant.filled,
                          // No longer need isLoading here since we show a full overlay
                          onPressed: _handleUpdateReport,
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
            
          // 🚀 FULL SCREEN UPDATING OVERLAY
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
          ],
        ),
      ),
    );
  }
}