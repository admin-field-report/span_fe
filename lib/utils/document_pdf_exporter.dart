import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/api_service.dart';
import '../services/toast_service.dart';
import '../widgets/button/button.dart';
import '../screens/projects/controllers/inspection_controller.dart';
import '../screens/projects/controllers/project_controller.dart';

// 🚀 Exports an inspection document (with its saved annotations) as a PDF and
// saves it to the device. Used from the inspection details document list so
// users don't have to open the canvas just to download.
class DocumentPdfExporter {
  static final ApiService _apiService = ApiService();

  static Future<void> export(BuildContext context, {required String documentId}) async {
    if (!kIsWeb && io.Platform.isAndroid) {
      var manageStatus = await Permission.manageExternalStorage.status;
      var storageStatus = await Permission.storage.status;
      if (!manageStatus.isGranted && !storageStatus.isGranted) {
        if (!context.mounted) return;
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

    try {
      final startResponse = await _apiService.get('/projectDocument/exportPdf/$documentId');
      final startData = jsonDecode(startResponse.body);

      if (startData['success'] != true || startData['status_endpoint'] == null) {
        throw Exception(startData['message'] ?? "Failed to start PDF export.");
      }

      final String statusEndpoint = startData['status_endpoint'];
      final Map<String, dynamic> jobData = await _pollExportJob(statusEndpoint);

      final String? signedUrl = jobData['signedUrl'] ?? "";
      if (signedUrl == null || signedUrl.isEmpty) {
        throw Exception("PDF export finished but no download URL was returned.");
      }

      final pdfResponse = await http.get(Uri.parse(signedUrl));

      if (pdfResponse.statusCode == 200 || pdfResponse.statusCode == 201) {
        if (pdfResponse.bodyBytes.isNotEmpty) {
          final Uint8List pdfBytes = pdfResponse.bodyBytes;

          if (context.mounted) {
            String fileName = 'exported_document_$documentId';
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
                  if (context.mounted) {
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

            if (context.mounted && filePath.isNotEmpty) {
              if (kIsWeb) {
                ToastService.show(context, message: "The PDF has been successfully downloaded.", type: ToastType.success);
              } else {
                showDialog(
                  context: context,
                  builder: (BuildContext dialogContext) {
                    return AlertDialog(
                      title: const Text("Export Complete"),
                      content: const Text("The PDF has been successfully downloaded."),
                      actions: [
                        Button(
                          label: "Close",
                          variant: ButtonVariant.outline,
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                        Button(
                          label: "Open File",
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            final result = await OpenFilex.open(filePath);
                            if (result.type != ResultType.done && context.mounted) {
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
          if (context.mounted) ToastService.show(context, message: "Received empty PDF data.", type: ToastType.error);
        }
      } else {
        if (context.mounted) ToastService.show(context, message: "Failed to export PDF (Status: ${pdfResponse.statusCode}).", type: ToastType.error);
      }
    } catch (e) {
      if (context.mounted) ToastService.show(context, message: "Export Error: $e", type: ToastType.error);
    }
  }

  /// Polls the export job's status_endpoint until it reports 'completed' or
  /// 'failed'. Gives up after ~5 minutes so a stuck job can't hang forever.
  static Future<Map<String, dynamic>> _pollExportJob(String statusEndpoint) async {
    const maxAttempts = 100;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final response = await _apiService.get(statusEndpoint);
      final data = jsonDecode(response.body);
      final String? status = data['status'];

      if (status == 'completed') return data;
      if (status == 'failed' || status == 'error') {
        throw Exception(data['message'] ?? "PDF export failed.");
      }

      await Future.delayed(const Duration(seconds: 3));
    }

    throw Exception("PDF export timed out.");
  }
}
