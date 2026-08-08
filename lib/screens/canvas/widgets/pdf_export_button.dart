import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/button/button.dart';
import '../../projects/controllers/inspection_controller.dart';
import '../../projects/controllers/project_controller.dart';
import 'custom_action_button.dart';

class PdfExportButton extends StatefulWidget {
  final String documentId;
  final bool hasUnsavedChanges;
  final VoidCallback onExportStart;
  final VoidCallback onExportEnd;

  const PdfExportButton({
    super.key,
    required this.documentId,
    required this.hasUnsavedChanges,
    required this.onExportStart,
    required this.onExportEnd,
  });

  @override
  State<PdfExportButton> createState() => _PdfExportButtonState();
}

class _PdfExportButtonState extends State<PdfExportButton> {
  final ApiService _apiService = ApiService();

  Future<void> _exportPdf() async {
    if (widget.hasUnsavedChanges) {
      ToastService.show(context, message: "Please save annotations before exporting.", type: ToastType.error);
      return;
    }

    if (!kIsWeb && io.Platform.isAndroid) {
      var manageStatus = await Permission.manageExternalStorage.status;
      var storageStatus = await Permission.storage.status;
      if (!manageStatus.isGranted && !storageStatus.isGranted) {
        if (!mounted) return;
        bool? allow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Storage Permission Required"),
            content: const Text("We need storage access to save the exported PDF to your device. Please allow access."),
            actions: [
              Button(
                label: "Cancel",
                variant: ButtonVariant.outline,
                onPressed: () => Navigator.pop(context, false),
              ),
              Button(
                label: "Allow",
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );

        if (allow == true) {
          if (await Permission.storage.isPermanentlyDenied) {
            await openAppSettings();
          } else {
            await Permission.manageExternalStorage.request();
            await Permission.storage.request();
          }
        }
        
        return;
      }
    }

    widget.onExportStart();
    try {
      final response = await _apiService.get('/canvas/exportPdf/${widget.documentId}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isNotEmpty) {
          final bodyString = response.body.replaceAll('"', '').replaceAll('\n', '').replaceAll('\r', '').trim();
          Uint8List pdfBytes;

          if (bodyString.startsWith('JVBER')) {
            String normalized = bodyString;
            while (normalized.length % 4 != 0) {
              normalized += '=';
            }
            pdfBytes = base64Decode(normalized);
          } else {
            pdfBytes = response.bodyBytes;
          }

          if (mounted) {
            String fileName = 'exported_document_${widget.documentId}';
            String prefix = '';
            
            final activeProject = projectController.currentProject;
            if (activeProject != null && activeProject.name.isNotEmpty) {
              prefix = '${activeProject.name} - ';
            }
            
            final activeInspection = inspectionController.currentInspection;
            if (activeInspection != null) {
              final rawDate = activeInspection.createTime;
              final parsedDate = rawDate is DateTime
                  ? rawDate
                  : DateTime.tryParse(rawDate.toString());
              if (parsedDate != null) {
                fileName = "${prefix}Inspection - ${DateFormat('dd MMM yyyy').format(parsedDate)}";
              } else {
                fileName = "$prefix$fileName";
              }
            } else {
              fileName = "$prefix$fileName";
            }

            String filePath = '';

            if (kIsWeb) {
              filePath = await FileSaver.instance.saveFile(
                name: fileName,
                bytes: pdfBytes,
                fileExtension: 'pdf',
                mimeType: MimeType.pdf,
              );
            } else {
              io.Directory? baseDirectory;
              if (io.Platform.isAndroid) {
                baseDirectory = io.Directory('/storage/emulated/0/Documents');
                if (!await baseDirectory.exists()) {
                  baseDirectory = await getExternalStorageDirectory(); // fallback
                }
              } else {
                baseDirectory = await getApplicationDocumentsDirectory();
              }
              
              if (baseDirectory != null) {
                final io.Directory targetDirectory = io.Directory('${baseDirectory.path}/Span Inspect');
                try {
                  if (!await targetDirectory.exists()) {
                    await targetDirectory.create(recursive: true);
                  }
                  
                  final io.File file = io.File('${targetDirectory.path}/$fileName.pdf');
                  await file.writeAsBytes(pdfBytes, flush: true);
                  filePath = file.path;
                  
                  if (io.Platform.isAndroid) {
                    try {
                      const platform = MethodChannel('com.fieldreport.field_report_fe/mediascanner');
                      await platform.invokeMethod('scanFile', {'path': filePath});
                    } catch (e) {
                      debugPrint('MediaScanner error: $e');
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ToastService.show(context, message: "Android blocked folder creation. Check permissions! Error: $e", type: ToastType.error);
                  }
                  final fallbackDir = await getExternalStorageDirectory();
                  if (fallbackDir != null) {
                    final io.File file = io.File('${fallbackDir.path}/$fileName.pdf');
                    await file.writeAsBytes(pdfBytes, flush: true);
                    filePath = file.path;
                    
                    if (io.Platform.isAndroid) {
                      try {
                        const platform = MethodChannel('com.fieldreport.field_report_fe/mediascanner');
                        await platform.invokeMethod('scanFile', {'path': filePath});
                      } catch (e) {
                        debugPrint('MediaScanner error: $e');
                      }
                    }
                  }
                }
              }
            }

            if (mounted && filePath.isNotEmpty) {
              if (kIsWeb) {
                ToastService.show(context, message: "The PDF has been successfully downloaded.", type: ToastType.success);
              } else {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Export Complete"),
                      content: const Text("The PDF has been successfully downloaded."),
                      actions: [
                        Button(
                          label: "Close",
                          variant: ButtonVariant.outline,
                          onPressed: () => Navigator.pop(context),
                        ),
                        Button(
                          label: "Open File",
                          onPressed: () async {
                            Navigator.pop(context);
                            final result = await OpenFilex.open(filePath);
                            if (result.type != ResultType.done && mounted) {
                              ToastService.show(context, message: "Could not open file: ${result.message}", type: ToastType.error);
                            }
                          },
                        ),
                      ],
                    );
                  },
                );
              }
            }
          }
        } else {
          if (mounted) ToastService.show(context, message: "Received empty PDF data.", type: ToastType.error);
        }
      } else {
        if (mounted) ToastService.show(context, message: "Failed to export PDF (Status: ${response.statusCode}).", type: ToastType.error);
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Export Error: $e", type: ToastType.error);
    } finally {
      if (mounted) widget.onExportEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CanvasToolbarActionButton(
      tooltip: "Export PDF",
      icon: Icons.picture_as_pdf_outlined,
      onTap: _exportPdf,
    );
  }
}
