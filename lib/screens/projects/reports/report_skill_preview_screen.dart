import 'dart:convert';
import 'dart:ui';
import 'package:field_report_fe/utils/app_responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/api_service.dart';
import '../../../widgets/widgets.dart'; 
import '../../../services/toast_service.dart';
import 'generated_report_view.dart'; // Make sure this import matches your file structure!

class ReportSkillPreviewScreen extends StatefulWidget {
  final String projectId;
  // final String skillId;
  final String reportTemplateId;
  final String initialContent;
  final List<String> inspectionIds;

  const ReportSkillPreviewScreen({
    super.key, 
    required this.projectId,
    // required this.skillId,
    required this.reportTemplateId,
    required this.initialContent,
    required this.inspectionIds,
  });

  @override
  State<ReportSkillPreviewScreen> createState() => _ReportSkillPreviewScreenState();
}

class _ReportSkillPreviewScreenState extends State<ReportSkillPreviewScreen> {
  final ApiService _apiService = ApiService();
  late TextEditingController _contentController;
  
  // 🚀 Tracks the source of truth to detect unsaved changes
  // late String _originalContent; 
  
  bool _isPreviewMode = true; 
  
  // Shared Loading State
  bool _isProcessing = false;
  String _loadingMessage = "";

  @override
  void initState() {
    super.initState();
    // _originalContent = widget.initialContent;
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 🚀 UPDATE SKILL API (Returns a bool so we know if it succeeded!)
  // Future<bool> _handleUpdateSkill() async {
  //   setState(() {
  //     _isProcessing = true;
  //     _loadingMessage = "Updating Skill...";
  //   });
    
  //   try {
  //     final payload = {
  //       "skill_content": _contentController.text,
  //     };

  //     final response = await _apiService.patch('/report-skills/${widget.skillId}', payload);
      
  //     if (response.statusCode == 200 || response.statusCode == 201) {
  //       final responseData = jsonDecode(response.body);
        
  //       if (mounted) {
  //         if (responseData['data'] != null && responseData['data']['skill_content'] != null) {
  //           _contentController.text = responseData['data']['skill_content'];
  //         }
  //         // 🚀 Update the baseline to match the newly saved content!
  //         _originalContent = _contentController.text; 

  //         ToastService.show(
  //           context, 
  //           message: responseData['message'] ?? "Skill updated successfully!", 
  //           type: ToastType.success
  //         );
  //       }
  //       return true;
  //     } else {
  //       throw Exception("Failed to update skill.");
  //     }
  //   } catch (e) {
  //     debugPrint("🚨 Error updating skill: $e");
  //     if (mounted) {
  //       ToastService.show(context, message: "Error updating skill: $e", type: ToastType.error);
  //     }
  //     return false;
  //   } finally {
  //     if (mounted) setState(() => _isProcessing = false);
  //   }
  // }

  // 🚀 GENERATION WRAPPER WITH UNSAVED CHANGES CHECK
  Future<void> _handleGenerateReport() async {
    // Check if the current text differs from the last saved baseline
    // if (_contentController.text != _originalContent) {
    //   final String? action = await _showUnsavedChangesDialog();
      
    //   if (action == null || action == 'cancel') {
    //     return; // User backed out
    //   } else if (action == 'update_and_generate') {
    //     // Await the update. If it fails, abort generation.
    //     final success = await _handleUpdateSkill();
    //     if (!success) return; 
    //   }
    //   // If action was 'continue_anyway', it skips the update and proceeds below.
    // }

    _executeGeneration();
  }

  // 🚀 UNSAVED CHANGES DIALOG
  // Future<String?> _showUnsavedChangesDialog() {
  //   return showDialog<String>(
  //     context: context,
  //     builder: (BuildContext context) {
  //       final colorScheme = Theme.of(context).colorScheme;
  //       return AlertDialog(
  //         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //         title: const Row(
  //           children: [
  //             Icon(Icons.warning_amber_rounded, color: Colors.orange),
  //             SizedBox(width: 8),
  //             Text("Unsaved Changes", style: TextStyle(fontWeight: FontWeight.bold)),
  //           ],
  //         ),
  //         content: const Text(
  //           "You have edited the skill configuration. If you generate the report now, your manual edits will not be included.\n\nWould you like to update the skill first?",
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context, 'cancel'),
  //             child: Text("Cancel", style: TextStyle(color: colorScheme.onSurfaceVariant)),
  //           ),
  //           TextButton(
  //             onPressed: () => Navigator.pop(context, 'continue_anyway'),
  //             child: const Text("Continue Anyway"),
  //           ),
  //           FilledButton(
  //             style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
  //             onPressed: () => Navigator.pop(context, 'update_and_generate'),
  //             child: const Text("Update & Generate"),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

  // 🚀 THE ACTUAL GENERATION LOGIC
  Future<void> _executeGeneration() async {
    setState(() {
      _isProcessing = true;
      _loadingMessage = "Initializing Report Generation...";
    });

    try {
      final payload = {
        "inspection_ids": widget.inspectionIds,
        // "skill_id": widget.skillId,
        "report_template_id": widget.reportTemplateId,
        "project_id": widget.projectId,
      };

      final startRes = await _apiService.post('/inspection/report/generate', payload);
      final startData = jsonDecode(startRes.body);

      final String rawEndpoint = startData['status_endpoint'];
      final String statusEndpoint = rawEndpoint.startsWith('/v1') ? rawEndpoint.replaceFirst('/v1', '') : rawEndpoint;

      setState(() => _loadingMessage = "Compiling Report Data...");
      
      bool isComplete = false;
      int attempts = 0;
      final int maxAttempts = 40; 

      while (!isComplete && attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 3));
        attempts++;

        final pollRes = await _apiService.get(statusEndpoint);
        final pollData = jsonDecode(pollRes.body);

        if (pollData['status'] == 'completed') {
          isComplete = true;
          
          if (!mounted) return;

          final String finalHtml = pollData['result']['data']['report_html'] ?? "<h1>No content generated</h1>";
          ToastService.show(context, message: "Report Generated!", type: ToastType.success);
          
          final bool? didFinish = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => GeneratedReportView(htmlContent: finalHtml),
              fullscreenDialog: true, 
            ),
          );
          if (!context.mounted) return;
          if (didFinish == true) {
            Navigator.pop(context, true);
          }
        } else if (pollData['status'] == 'failed' || pollData['status'] == 'error') {
          throw Exception("Report generation failed on the server.");
        }
      }

      if (!isComplete) throw Exception("Report generation timed out.");

    } catch (e) {
      debugPrint("🚨 Error generating report: $e");
      if (mounted) ToastService.show(context, message: "Error: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = AppResponsive.isMobileScreen(context);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        centerTitle: false, 
        titleSpacing: 0, 
        title: const Text("Review Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, true), 
        ),
      ),
      body: PopScope(
        canPop: !_isProcessing,
        child: AbsorbPointer(
          absorbing: _isProcessing,
          child: Stack(
            children: [
              Column(
                children: [
                  // EDITOR / PREVIEW AREA
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                        ]
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
                            ),
                            child: Row(
                              children: [
                                // Icon(_isPreviewMode ? Icons.visibility : Icons.code, color: colorScheme.primary, size: 20),
                                // const SizedBox(width: 8),
                                Text("Skill Configuration", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                const Spacer(),
                                
                                // Container(
                                //   decoration: BoxDecoration(
                                //     color: colorScheme.surfaceContainer,
                                //     borderRadius: BorderRadius.circular(8),
                                //     border: Border.all(color: colorScheme.outlineVariant),
                                //   ),
                                //   child: Row(
                                //     children: [
                                //       _buildToggleOption(
                                //         "Edit", 
                                //         Icons.edit_note, 
                                //         !_isPreviewMode, 
                                //         () => setState(() => _isPreviewMode = false), 
                                //         colorScheme,
                                //         showText: !isMobile, // 🚀 NEW: Tell it whether to show text!
                                //       ),
                                //       _buildToggleOption(
                                //         "Preview", 
                                //         Icons.remove_red_eye_outlined, 
                                //         _isPreviewMode, 
                                //         () { 
                                //           FocusScope.of(context).unfocus(); 
                                //           setState(() => _isPreviewMode = true); 
                                //         }, 
                                //         colorScheme,
                                //         showText: !isMobile, // 🚀 NEW: Tell it whether to show text!
                                //       ),
                                //     ],
                                //   ),
                                // )
                              ],
                            ),
                          ),
                          
                          Expanded(
                            child: _isPreviewMode ? _buildMarkdownPreview(colorScheme) : _buildRawEditor(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // BOTTOM ACTION BAR
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]
                    ),
                    child: SafeArea(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Button(
                          //   label: "Update Skill",
                          //   icon: Icons.save,
                          //   variant: ButtonVariant.outline,
                          //   onPressed: _handleUpdateSkill, // Removed isLoading property since the overlay handles it now
                          // ),
                          // const SizedBox(width: 12),
                          Button(
                            label: "Generate Report",
                            icon: Icons.auto_awesome,
                            variant: ButtonVariant.filled,
                            onPressed: _handleGenerateReport,
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),

              // 🚀 THE SHARED FROSTED GLASS LOADER OVERLAY
              if (_isProcessing)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0), 
                    child: Container(
                      color: colorScheme.scrim.withOpacity(0.3), 
                      child: Center(
                        child: Container(
                          width: 320, 
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(28), 
                            border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1),
                            boxShadow: [
                              BoxShadow(color: colorScheme.shadow.withOpacity(0.15), blurRadius: 40, spreadRadius: -5, offset: const Offset(0, 10))
                            ]
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 72, height: 72,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 5, strokeCap: StrokeCap.round, 
                                      color: colorScheme.primary, backgroundColor: colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                                  Icon(Icons.auto_awesome, color: colorScheme.primary, size: 32),
                                ],
                              ),
                              const SizedBox(height: 32),
                              Text(
                                _loadingMessage, 
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.onSurface, letterSpacing: 0.2),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Please do not close the app.", 
                                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildRawEditor() {
    return TextField(
      controller: _contentController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.5),
      decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(24), hintText: "Report formatting rules..."),
    );
  }

  Widget _buildMarkdownPreview(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surface, 
      child: Markdown(
        data: _contentController.text.isEmpty ? "*No content to preview.*" : _contentController.text,
        padding: const EdgeInsets.all(24),
        selectable: true, 
        styleSheet: MarkdownStyleSheet(
          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.5),
          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.5),
          p: TextStyle(fontSize: 15, height: 1.6, color: colorScheme.onSurface),
          listBullet: TextStyle(color: colorScheme.primary),
          code: TextStyle(backgroundColor: colorScheme.surfaceContainer, fontFamily: 'monospace', fontSize: 13),
          codeblockDecoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildToggleOption(
    String label, 
    IconData icon, 
    bool isSelected, 
    VoidCallback onTap, 
    ColorScheme colorScheme, {
    bool showText = true, // 🚀 NEW: Defaults to true so it doesn't break other screens
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: 8, 
          horizontal: showText ? 16 : 12, // Slightly tighter padding if it's just an icon
        ),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              size: 20, 
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant
            ),
            
            // 🚀 ONLY render the text and spacing if showText is true!
            if (showText) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}