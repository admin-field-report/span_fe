import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

// Adjust your imports as needed
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/button/button.dart'; 

class UploadDocumentPanel extends StatefulWidget {
  final String projectId;

  const UploadDocumentPanel({super.key, required this.projectId});

  @override
  State<UploadDocumentPanel> createState() => _UploadDocumentPanelState();
}

class _UploadDocumentPanelState extends State<UploadDocumentPanel> {
  final ApiService _apiService = ApiService();
  
  bool _isUploading = false;
  PlatformFile? _selectedFile;

  // 🚀 1. FILE PICKER LOGIC (Enforces PDF only!)
  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'], // Strictly PDFs
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Failed to pick file", type: ToastType.error);
      }
    }
  }

  // 🚀 4-STEP UPLOAD LOGIC
  Future<void> _uploadDocument() async {
    if (_selectedFile == null || _isUploading) return;

    setState(() => _isUploading = true);

    try {
      // ==========================================
      // STEP 1: Get Presigned URL & S3 Key
      // ==========================================
      final preSignPayload = {
        "file": _selectedFile!.name,
        "project_id": widget.projectId
      };

      final preSignResponse = await _apiService.post('/presignedurl/project-document', preSignPayload);
      final preSignData = jsonDecode(preSignResponse.body);

      final signedUrl = preSignData['signedUrl'];
      final documentKey = preSignData['key']; 
      
      if (signedUrl == null || documentKey == null) {
        throw Exception("Failed to generate secure upload URL or missing S3 key.");
      }

      // ==========================================
      // STEP 2: Upload File Directly to AWS S3
      // ==========================================      
      List<int> fileBytes;
      if (_selectedFile!.bytes != null) {
        fileBytes = _selectedFile!.bytes!;
      } else {
        fileBytes = await File(_selectedFile!.path!).readAsBytes();
      }

      final s3Response = await http.put(
        Uri.parse(signedUrl),
        headers: { 'Content-Type': 'application/pdf' },
        body: fileBytes,
      );

      if (s3Response.statusCode != 200) {
        throw Exception("S3 Upload Failed with status: ${s3Response.statusCode}");
      }

      // ==========================================
      // STEP 3: Save Base Document Record
      // ==========================================      
      // final createPayload = {
      //   "document_url": documentKey, 
      //   "document_name": _selectedFile!.name,
      // };

      // final createResponse = await _apiService.post('/templateDocument/createTemplateDocument', createPayload);
      // final createData = jsonDecode(createResponse.body);

      // if (createData['success'] != true) {
      //   throw Exception(createData['message'] ?? "Database creation failed.");
      // }

      // // 🚀 Grab the newly created document ID for Step 4!
      // final newTemplateDocumentId = createData['data']['id'];

      // ==========================================
      // STEP 4: Link Document to Project
      // ==========================================

      final linkPayload = {
        "project_id": widget.projectId,
        // "template_document_id": newTemplateDocumentId,
        "document_url": documentKey,
        "document_name": _selectedFile!.name,
      };

      final linkResponse = await _apiService.post('/projectDocument/document', linkPayload);
      final linkData = jsonDecode(linkResponse.body);

      if (!mounted) return;

      if (linkData['success'] == true) {
          ToastService.show(context, message: "Document uploaded successfully!", type: ToastType.success);
          
          // Close the panel and pass 'true' to trigger the table refresh
          Navigator.pop(context, true); 
        } else {
          throw Exception("Failed to link document to project.");
        }

    } catch (e) {
      if (mounted) {
        ToastService.show(context, message: "Upload failed: $e", type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 🚀 Protect UI while uploading (blocks back button and physical taps)
    return PopScope(
      canPop: !_isUploading,
      child: AbsorbPointer(
        absorbing: _isUploading,
        child: Container(
          color: colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Hugs the content tightly
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              
              // --- HEADER ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Upload Document", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      // Disable the close button during upload
                      onPressed: _isUploading ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // --- CONTENT ---
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    
                    // Pick File Area
                    InkWell(
                      onTap: _pickDocument,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border.all(
                            color: _selectedFile == null ? colorScheme.outlineVariant : colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                _selectedFile == null ? Icons.upload_file : Icons.picture_as_pdf, 
                                size: 48, 
                                color: _selectedFile == null ? colorScheme.outline : Colors.redAccent
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedFile == null ? "Click to browse (PDF only)" : _selectedFile!.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16, 
                                  fontWeight: FontWeight.w500,
                                  color: _selectedFile == null ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                                ),
                              ),
                              if (_selectedFile != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  "${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB", 
                                  style: TextStyle(color: colorScheme.outline, fontSize: 12)
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Button(
                          label: "Cancel",
                          variant: ButtonVariant.outline,
                          // Disable cancel button while uploading
                          onPressed: _isUploading ? null : () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        
                        Button(
                            label: "Upload Document",
                            variant: ButtonVariant.filled,
                            icon: Icons.cloud_upload,
                            onPressed: _selectedFile == null ? null : _uploadDocument,
                            isLoading: _isUploading, 
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}