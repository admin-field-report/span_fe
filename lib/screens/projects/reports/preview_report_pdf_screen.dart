import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../core/api_service.dart';
import '../../../widgets/widgets.dart';
import '../../../services/toast_service.dart';

class PreviewReportPdfScreen extends StatefulWidget {
  final String reportId;
  final bool isReadOnly;

  const PreviewReportPdfScreen({
    super.key, 
    required this.reportId,
    this.isReadOnly = false,
  });

  @override
  State<PreviewReportPdfScreen> createState() => _PreviewReportPdfScreenState();
}

class _PreviewReportPdfScreenState extends State<PreviewReportPdfScreen> {
  final ApiService _apiService = ApiService();
  final PdfViewerController _pdfViewerController = PdfViewerController();

  String? _pdfUrl;
  bool _isLoading = true;
  String? _errorMessage;

  int _currentPage = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchPdf();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _fetchPdf() async {
    try {
      final response = await _apiService.get('/report/exportPdf/${widget.reportId}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          setState(() {
            try {
              final decoded = jsonDecode(response.body);
              if (decoded != null && decoded['data'] != null && decoded['data']['signedUrl'] != null) {
                _pdfUrl = decoded['data']['signedUrl'];
              } else {
                _errorMessage = "Invalid response format.";
              }
            } catch (e) {
              _errorMessage = "Failed to parse API response.";
            }
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Failed to load PDF.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        ToastService.show(context, message: "Error loading PDF: $e", type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainer,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Project Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: colorScheme.surface,
        automaticallyImplyLeading: false, 
        leading: widget.isReadOnly 
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ) 
          : null,
        actions: _pageCount > 0 ? [
          // Zoom Controls
          IconButton(
            icon: const Icon(Icons.zoom_out_rounded, size: 20),
            tooltip: "Zoom Out",
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel - 0.25).clamp(1.0, 3.0);
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in_rounded, size: 20),
            tooltip: "Zoom In",
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel + 0.25).clamp(1.0, 3.0);
            },
          ),
          
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 12.0),
            child: VerticalDivider(color: colorScheme.outlineVariant, width: 1),
          ),

          // Navigation Controls
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
            tooltip: "Previous Page",
            color: _currentPage > 1 ? colorScheme.onSurfaceVariant : theme.disabledColor,
            onPressed: _currentPage > 1 ? () => _pdfViewerController.previousPage() : null,
          ),
          
          // Page Counter
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                '$_currentPage / $_pageCount',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            tooltip: "Next Page",
            color: _currentPage < _pageCount ? colorScheme.onSurfaceVariant : theme.disabledColor,
            onPressed: _currentPage < _pageCount ? () => _pdfViewerController.nextPage() : null,
          ),
          const SizedBox(width: 8),
        ] : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: colorScheme.outlineVariant.withValues(alpha: 0.5), height: 1.0),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text("Error: $_errorMessage"))
                    : _pdfUrl != null
                        ? SfPdfViewer.network(
                            _pdfUrl!,
                            controller: _pdfViewerController,
                            interactionMode: PdfInteractionMode.pan,
                            canShowScrollHead: false,
                            canShowScrollStatus: false,
                            onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                              setState(() {
                                _pageCount = details.document.pages.count;
                              });
                            },
                            onPageChanged: (PdfPageChangedDetails details) {
                              setState(() {
                                _currentPage = details.newPageNumber;
                              });
                            },
                            onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                              setState(() {
                                _errorMessage = "Error loading PDF: ${details.description}";
                              });
                            },
                          )
                        : const Center(child: Text("Empty PDF data")),
          ),
          // BOTTOM STICKY ACTION BAR
          if (!widget.isReadOnly)
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
                      label: "Finish",
                      icon: Icons.check_circle,
                      variant: ButtonVariant.filled,
                      onPressed: () {
                        Navigator.pop(context, true); // Pop back to GeneratedReportView with success flag
                      },
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
