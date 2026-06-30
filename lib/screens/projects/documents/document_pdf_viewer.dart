import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../../core/api_service.dart';

class DocumentPdfViewerScreen extends StatefulWidget {
  final String documentId;
  final String documentName;

  const DocumentPdfViewerScreen({
    super.key, 
    required this.documentId, 
    required this.documentName,
  });

  @override
  State<DocumentPdfViewerScreen> createState() => _DocumentPdfViewerScreenState();
}

class _DocumentPdfViewerScreenState extends State<DocumentPdfViewerScreen> {
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
    _fetchPresignedUrl();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _fetchPresignedUrl() async {
    try {
      final response = await _apiService.get('/projectDocument/pdf/presigned-url/${widget.documentId}');
      final responseData = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && responseData['success'] == true && responseData['data'] != null) {
        setState(() {
          _pdfUrl = responseData['data']['signedUrl'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = responseData['message'] ?? "Failed to retrieve secure document link.";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "A network error occurred while loading the document.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.documentName,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        
        // 🚀 NEW: Move the PDF Controls to the AppBar actions!
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
        ] : null, // Hide controls until document is loaded
        
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: colorScheme.outlineVariant.withOpacity(0.5), height: 1.0),
        ),
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              "Retrieving secure document...",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              "Please wait. Large files may take a moment.",
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              "Could not load PDF",
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _fetchPresignedUrl();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text("Try Again"),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }

    // 🚀 Clean, full-screen PDF view
    return SfPdfViewer.network(
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
          _errorMessage = "Network Error: ${details.description}";
        });
      },
    );
  }
}