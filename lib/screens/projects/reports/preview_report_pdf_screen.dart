import 'dart:convert';
import 'dart:typed_data';
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

  Uint8List? _pdfBytes;
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
              final bodyString = response.body.trim();
              
              // 1. Check if it's a raw Base64 string (PDFs in base64 always start with 'JVBER')
              // Sometimes APIs return the raw base64 string without JSON wrapping.
              // Note: It might be wrapped in quotes or have newlines, so we clean it.
              String cleanString = bodyString.replaceAll('"', '').replaceAll('\n', '').replaceAll('\r', '').trim();
              
              Uint8List decodeBase64Safe(String base64Str) {
                String normalized = base64Str.replaceAll('\n', '').replaceAll('\r', '').trim();
                while (normalized.length % 4 != 0) {
                  normalized += '=';
                }
                return base64Decode(normalized);
              }

              if (cleanString.startsWith('JVBER')) {
                _pdfBytes = decodeBase64Safe(cleanString);
              } else {
                // 2. Try parsing as JSON
                final decoded = jsonDecode(bodyString);
                if (decoded != null && decoded['data'] != null) {
                  if (decoded['data'] is String) {
                    _pdfBytes = decodeBase64Safe(decoded['data']);
                  } else if (decoded['data']['data'] != null) {
                    _pdfBytes = Uint8List.fromList(List<int>.from(decoded['data']['data']));
                  } else if (decoded['data'] is List) {
                    _pdfBytes = Uint8List.fromList(List<int>.from(decoded['data']));
                  } else {
                    _pdfBytes = response.bodyBytes;
                  }
                } else if (decoded != null && decoded['type'] == 'Buffer' && decoded['data'] != null) {
                  _pdfBytes = Uint8List.fromList(List<int>.from(decoded['data']));
                } else {
                  _pdfBytes = response.bodyBytes;
                }
              }
            } catch (e) {
              // 3. Not JSON and not a raw Base64 string, assume it's raw PDF bytes (starts with %PDF)
              _pdfBytes = response.bodyBytes;
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
                    : _pdfBytes != null
                        ? SfPdfViewer.memory(
                            _pdfBytes!,
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
