import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'package:markdown/markdown.dart' as md;

import '../../../core/api_service.dart';
import '../../../widgets/widgets.dart';
import '../../../services/toast_service.dart';

class EditReportScreen extends StatefulWidget {
  final String reportId;

  const EditReportScreen({super.key, required this.reportId});

  @override
  State<EditReportScreen> createState() => _EditReportScreenState();
}

class _EditReportScreenState extends State<EditReportScreen> {
  final ApiService _apiService = ApiService();
  late TextEditingController _contentController;
  
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isEditMode = true;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController();
    _fetchReportDetails();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 🚀 FETCH & CONVERT: HTML -> MARKDOWN
  Future<void> _fetchReportDetails() async {
    try {
      final response = await _apiService.get('/report/getById/${widget.reportId}');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (responseData['data'] != null) {
        final data = responseData['data'];
        setState(() {          
          final rawHtml = data['report_body'] ?? "";
          
          // 🚀 Convert the backend HTML into clean Markdown for the editor
          _contentController.text = html2md.convert(rawHtml);
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Failed to load report.", type: ToastType.error);
        setState(() => _isLoading = false);
      }
    }
  }

  // 🚀 CONVERT & SAVE: MARKDOWN -> HTML
  Future<void> _handleUpdateReport() async {
    if (_isUpdating) return;
    
    setState(() => _isUpdating = true);
    
    try {
      // 🚀 Convert the user's Markdown back to standard HTML for the API
      final htmlPayload = md.markdownToHtml(_contentController.text);
      
      final payload = {"report_body": htmlPayload};
      final response = await _apiService.patch('/report/update/${widget.reportId}', payload);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text("Edit Report", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        // 🚀 TOGGLE ICONS IN HEADER RIGHT SIDE
        actions: [
          IconButton(
            icon: Icon(Icons.edit_note, color: _isEditMode ? colorScheme.primary : colorScheme.onSurfaceVariant),
            tooltip: "Edit Mode",
            onPressed: () => setState(() => _isEditMode = true),
          ),
          IconButton(
            icon: Icon(Icons.remove_red_eye_outlined, color: !_isEditMode ? colorScheme.primary : colorScheme.onSurfaceVariant),
            tooltip: "Preview Mode",
            onPressed: () {
              FocusScope.of(context).unfocus(); // Dismiss keyboard when previewing
              setState(() => _isEditMode = false);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🚀 MAIN CONTENT AREA (Full Width & Height)
              Expanded(
                child: Container(
                  // Removed margins, borders, radius, and shadow for edge-to-edge feel
                  color: Colors.white,
                  child: _isEditMode 
                    ? TextField(
                        controller: _contentController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          fontFamily: 'monospace', // Monospace is standard for Markdown editing
                          fontSize: 14,
                          height: 1.6,
                          color: Colors.black87,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(24), // Keeps text readable away from screen edge
                          hintText: "# Report Title\n\nStart typing in Markdown...",
                        ),
                      )
                    : Markdown(
                        data: _contentController.text.isEmpty ? "*No content*" : _contentController.text,
                        padding: const EdgeInsets.all(24), // Keeps text readable away from screen edge
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.5, color: Colors.black),
                          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.5, color: Colors.black87),
                          h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.5, color: Colors.black87),
                          p: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                          listBullet: TextStyle(color: colorScheme.primary),
                          code: TextStyle(backgroundColor: colorScheme.surfaceContainer, fontFamily: 'monospace'),
                          codeblockDecoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
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
                        isLoading: _isUpdating,
                        onPressed: _handleUpdateReport,
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
    );
  }
}