import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/toast_service.dart';
import '../widgets/button/button.dart';

class MediaDownloader {
  static String _extensionFromUrl(String url, {String fallback = 'jpg'}) {
    final path = Uri.parse(url).path;
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return fallback;
    final ext = path.substring(dotIndex + 1).toLowerCase();
    const validExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'zip'};
    return validExtensions.contains(ext) ? ext : fallback;
  }

  // Same storage-permission flow as ProjectReports/PdfExportButton: ask once
  // via a dialog, send the user to settings when permanently denied, and
  // require a fresh tap after granting.
  static Future<bool> _ensureStoragePermission(BuildContext context) async {
    if (kIsWeb || !io.Platform.isAndroid) return true;

    var manageStatus = await Permission.manageExternalStorage.status;
    var storageStatus = await Permission.storage.status;
    if (manageStatus.isGranted || storageStatus.isGranted) return true;

    if (!context.mounted) return false;
    bool? allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Storage Permission Required"),
        content: const Text("We need storage access to save the downloaded file to your device. Please allow access."),
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

    return false;
  }

  static Future<void> _saveBytesToDownloads(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String extension,
    required MimeType mimeType,
    required String successMessage,
  }) async {
    final String fullName = '$fileName.$extension';

    if (kIsWeb) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: extension,
        mimeType: mimeType,
      );
      if (context.mounted) {
        ToastService.show(context, message: successMessage, type: ToastType.success);
      }
      return;
    }

    io.Directory? downloadsDirectory;

    if (io.Platform.isAndroid) {
      downloadsDirectory = io.Directory('/storage/emulated/0/Download');
      if (!await downloadsDirectory.exists()) {
        downloadsDirectory = await getExternalStorageDirectory();
      }
    } else if (io.Platform.isIOS) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    } else {
      // Desktop platforms (macOS, Windows, Linux)
      downloadsDirectory = await getDownloadsDirectory();
      downloadsDirectory ??= await getApplicationDocumentsDirectory();
    }

    if (downloadsDirectory == null) {
      if (context.mounted) {
        ToastService.show(context, message: "Could not locate the Downloads folder.", type: ToastType.error);
      }
      return;
    }

    if (!await downloadsDirectory.exists()) {
      await downloadsDirectory.create(recursive: true);
    }

    final io.File file = io.File('${downloadsDirectory.path}/$fullName');
    await file.writeAsBytes(bytes, flush: true);

    if (io.Platform.isAndroid) {
      try {
        const platform = MethodChannel('com.fieldreport.field_report_fe/mediascanner');
        await platform.invokeMethod('scanFile', {'path': file.path});
      } catch (e) {
        debugPrint('MediaScanner error: $e');
      }
    }

    if (context.mounted) {
      ToastService.show(context, message: successMessage, type: ToastType.success);
    }
  }

  static Future<void> downloadImage(
    BuildContext context, {
    required String imageUrl,
    required String fileName,
  }) async {
    if (!await _ensureStoragePermission(context)) return;
    if (!context.mounted) return;

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        if (context.mounted) {
          ToastService.show(context, message: "Failed to download image.", type: ToastType.error);
        }
        return;
      }

      if (!context.mounted) return;
      await _saveBytesToDownloads(
        context,
        bytes: response.bodyBytes,
        fileName: fileName,
        extension: _extensionFromUrl(imageUrl, fallback: 'jpg'),
        mimeType: MimeType.other,
        successMessage: "Image saved to Downloads.",
      );
    } catch (e) {
      if (context.mounted) {
        ToastService.show(context, message: "Download Error: $e", type: ToastType.error);
      }
    }
  }

  /// Downloads a file (e.g. the pre-signed S3 zip URL returned by the
  /// inspection images-zip endpoint) and saves it to Downloads.
  static Future<void> downloadFromUrl(
    BuildContext context, {
    required String url,
    required String fileName,
    String fallbackExtension = 'zip',
    MimeType mimeType = MimeType.zip,
    String successMessage = "File saved to Downloads.",
  }) async {
    if (!await _ensureStoragePermission(context)) return;
    if (!context.mounted) return;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (context.mounted) {
          ToastService.show(context, message: "Failed to download file.", type: ToastType.error);
        }
        return;
      }

      if (!context.mounted) return;
      await _saveBytesToDownloads(
        context,
        bytes: response.bodyBytes,
        fileName: fileName,
        extension: _extensionFromUrl(url, fallback: fallbackExtension),
        mimeType: mimeType,
        successMessage: successMessage,
      );
    } catch (e) {
      if (context.mounted) {
        ToastService.show(context, message: "Download Error: $e", type: ToastType.error);
      }
    }
  }
}
