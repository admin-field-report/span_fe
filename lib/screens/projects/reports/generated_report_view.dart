import 'package:flutter/material.dart';
import 'package:html_editor_enhanced/html_editor.dart';
import '../../../widgets/widgets.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import 'preview_report_pdf_screen.dart';

class GeneratedReportView extends StatefulWidget {
  final String htmlContent;
  final String reportId;

  const GeneratedReportView({super.key, required this.htmlContent, required this.reportId});

  @override
  State<GeneratedReportView> createState() => _GeneratedReportViewState();
}

class _GeneratedReportViewState extends State<GeneratedReportView> {
  final ApiService _apiService = ApiService();
  final HtmlEditorController _editorController = HtmlEditorController();

  late String _currentHtml;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentHtml = widget.htmlContent;
  }

  Future<void> _navigateToPreview() async {
    final didFinish = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreviewReportPdfScreen(reportId: widget.reportId),
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

    setState(() => _isUpdating = true);

    try {
      final htmlPayload = await _editorController.getText();
      final payload = {"body_html": htmlPayload};
      final response = await _apiService.patch('/report/update/${widget.reportId}', payload);

      if (response.statusCode == 200 || response.statusCode == 201) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        centerTitle: true,
        title: const Text("Final Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: Stack(
        children: [
          Column(
            children: [
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
                  const SizedBox(width: 12),
                  Button(
                    label: "Next",
                    variant: ButtonVariant.outline,
                    onPressed: _navigateToPreview,
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
  );
}
}
