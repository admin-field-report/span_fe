import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_service.dart';
import '../../services/toast_service.dart';

import '../../../widgets/canvas/canvas.dart' as custom_canvas;
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/button/button.dart';
import 'widgets/properties_panel.dart';
import 'widgets/custom_tools_panel.dart';
import 'widgets/custom_action_button.dart';
import 'widgets/pdf_export_button.dart';


class CanvasDocumentPane extends StatefulWidget {
  final String documentId;
  final String projectId;
  final String inspectionId;
  final String page;
  final String? annotateImageKey;

  const CanvasDocumentPane({
    super.key,
    required this.projectId,
    required this.inspectionId,
    required this.documentId,
    this.page = '1',
    this.annotateImageKey,
  });

  @override
  State<CanvasDocumentPane> createState() => CanvasDocumentPaneState();
}

class CanvasDocumentPaneState extends State<CanvasDocumentPane> {
  final ApiService _apiService = ApiService();
  final Map<String, GlobalKey<custom_canvas.CanvasState>> _canvasKeys = {};

  bool _isInitializing = true;
  bool _isPageLoading = false;
  bool _isLoadingAnnotations = false;
  bool _isUploadingImage = false;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isFirstLoadComplete = false;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool _hasUnsavedImageChanges = false;

  DrawingObject? _selectedCanvasObject;
  List<CustomToolGroup> _customToolGroups = [];
  bool _isLoadingCustomTools = true;
  CustomTool? _selectedCustomTool;

  Map<String, dynamic> _rawDocumentData = {};

  List<String> _pages = [];
  String _currentPage = '';
  Map<String, PageData> _pageDataMap = {};
  List<TagGroup> _availableTagGroups = [];
  bool _isLoadingTags = false;

  String _inspectionDescription = "";
  List<String> _inspectionTagIds = [];
  List<dynamic> _inspectionImages = [];

  String? _overlayImageKey;
  bool _isOverlayInspection = false;
  DrawingObject? _overlayParentObject;

  Uint8List? _pendingUploadBytes;
  String? _pendingUploadFileName;

  Map<String, String>? _uploadedImageMetadata;

  @override
  void initState() {
    super.initState();
    _initializeCanvas();
  }

  GlobalKey<custom_canvas.CanvasState> _getCurrentCanvasKey() {
    String activeKey = _overlayImageKey != null ? 'IMG_$_overlayImageKey' : _currentPage;
    if (activeKey.isEmpty) return GlobalKey<custom_canvas.CanvasState>();

    _canvasKeys.putIfAbsent(activeKey, () => GlobalKey<custom_canvas.CanvasState>());
    return _canvasKeys[activeKey]!;
  }

  void _syncCurrentPageObjects() {
    String activeKey = _overlayImageKey != null ? 'IMG_$_overlayImageKey' : _currentPage;
    if (activeKey.isEmpty) return;

    final key = _getCurrentCanvasKey();
    if (key.currentState != null && _pageDataMap.containsKey(activeKey)) {
      _pageDataMap[activeKey]!.objects = key.currentState!.objects;
    }
  }

  void _switchPage(String newPage) async {
    if (_overlayImageKey != null || widget.annotateImageKey != null) {
      ToastService.show(context, message: "Please finish or discard current image first.", type: ToastType.warning);
      return;
    }

    _syncCurrentPageObjects();
    setState(() {
      _isPageLoading = true;
      _currentPage = newPage;
      _selectedCanvasObject = null;
    });

    await _fetchPageImage(newPage);

    if (mounted) {
      setState(() => _isPageLoading = false);
    }
  }

  Future<ui.Image> _decodeBase64Image(String base64Str) async {
    String cleanBase64 = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
    final Uint8List bytes = base64Decode(cleanBase64);
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> _decodeBytesToImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  // ==========================================
  // 🌟 IN-MEMORY IMAGE ANNOTATION LOGIC
  // ==========================================

  Future<void> _handleImageTap(String s3Key) async {
    if (_overlayImageKey != null) {
      ToastService.show(context, message: "Please finish or discard current image first.", type: ToastType.warning);
      return;
    }

    _syncCurrentPageObjects();

    bool isInspection = _selectedCanvasObject == null;
    Map<String, dynamic>? imgData;

    if (isInspection) {
      imgData = _inspectionImages.firstWhere(
        (img) => img['image_url'] == s3Key || img['key'] == s3Key,
        orElse: () => null
      );
    } else {
      imgData = _selectedCanvasObject!.imageUrls?.firstWhere(
        (img) => img['image_url'] == s3Key || img['key'] == s3Key,
        orElse: () => null
      );
    }

    if (imgData == null || imgData['preview_image'] == null || imgData['preview_image'].isEmpty) {
      ToastService.show(context, message: "Image preview not available.", type: ToastType.error);
      return;
    }

    setState(() => _isPageLoading = true);

    try {
      String base64Preview = imgData['preview_image'];
      String cleanBase64 = base64Preview.contains(',') ? base64Preview.split(',').last : base64Preview;

      final ui.Image decodedImage = await _decodeBase64Image(cleanBase64);
      final pageId = 'IMG_$s3Key';

      final pageData = PageData(
        pageId: pageId,
        backgroundImageBytes: base64Decode(cleanBase64),
        width: decodedImage.width.toDouble(),
        height: decodedImage.height.toDouble(),
      );

      if (imgData['annotation_list'] != null) {
        pageData.objects = _parseAnnotationsList(imgData['annotation_list'], pageData.width, pageData.height);
      }

      setState(() {
        _pageDataMap[pageId] = pageData;
        _overlayImageKey = s3Key;
        _isOverlayInspection = isInspection;
        _overlayParentObject = _selectedCanvasObject;
        _selectedCanvasObject = null;
        _isPageLoading = false;
      });
    } catch (e) {
      setState(() => _isPageLoading = false);
      ToastService.show(context, message: "Failed to load image preview.", type: ToastType.error);
    }
  }

  Future<void> _setupLocalImageOverlay(String fileName, Uint8List bytes, bool isInspection) async {
    _syncCurrentPageObjects();

    setState(() => _isUploadingImage = true);

    try {
      final uploadedData = await _executeDirectS3Upload(fileName, bytes, isInspection);
      final ui.Image decodedImage = await _decodeBytesToImage(bytes);
      final pageId = 'IMG_LOCAL_PENDING';

      final pageData = PageData(
        pageId: pageId,
        backgroundImageBytes: bytes,
        width: decodedImage.width.toDouble(),
        height: decodedImage.height.toDouble(),
      );

      setState(() {
        _pageDataMap[pageId] = pageData;
        _overlayImageKey = 'LOCAL_PENDING';
        _isOverlayInspection = isInspection;
        _overlayParentObject = _selectedCanvasObject;
        _selectedCanvasObject = null;

        _pendingUploadBytes = bytes;
        _pendingUploadFileName = fileName;
        _uploadedImageMetadata = uploadedData;

        _isUploadingImage = false;
      });
    } catch (e) {
      setState(() => _isUploadingImage = false);
      ToastService.show(context, message: "Failed to process image.", type: ToastType.error);
    }
  }

  // 🚀 BUG FIXED: Removed the destructive _canvasKeys.remove(_currentPage) so document stays exactly as you left it!
  void _closeOverlay() {
    _pageDataMap.remove('IMG_$_overlayImageKey');
    _overlayImageKey = null;
    _selectedCanvasObject = _overlayParentObject;
    _overlayParentObject = null;
    _pendingUploadBytes = null;
    _pendingUploadFileName = null;
    _uploadedImageMetadata = null;
  }

  void _discardImageAnnotations() {
    setState(() {
      _closeOverlay();
    });
  }

  Future<void> _saveImageAnnotationsToMemory() async {
    _syncCurrentPageObjects();

    if (_overlayImageKey != 'LOCAL_PENDING') {
      final pageData = _pageDataMap['IMG_$_overlayImageKey'];
      if (pageData != null) {
        final serialized = _serializeObjects(pageData.objects, pageData.width, pageData.height);
        setState(() {
          if (_isOverlayInspection) {
            final imgIndex = _inspectionImages.indexWhere((img) => img['image_url'] == _overlayImageKey || img['key'] == _overlayImageKey);
            if (imgIndex != -1) _inspectionImages[imgIndex]['annotation_list'] = serialized;
          } else if (_overlayParentObject != null && _overlayParentObject!.imageUrls != null) {
            final imgIndex = _overlayParentObject!.imageUrls!.indexWhere((img) => img['image_url'] == _overlayImageKey || img['key'] == _overlayImageKey);
            if (imgIndex != -1) _overlayParentObject!.imageUrls![imgIndex]['annotation_list'] = serialized;
          }
          _hasUnsavedChanges = true;
          _closeOverlay();
        });
        // ToastService.show(context, message: "Annotations applied.", type: ToastType.success);
      }
      return;
    }

    if (_uploadedImageMetadata == null || _pendingUploadFileName == null) return;

    final pageData = _pageDataMap['IMG_LOCAL_PENDING'];
    List<Map<String, dynamic>> annotations = [];
    if (pageData != null) {
      annotations = _serializeObjects(pageData.objects, pageData.width, pageData.height);
    }

    setState(() {
      if (_isOverlayInspection) {
        _inspectionImages.add({
          "image_id": _uploadedImageMetadata!['imageId'],
          "image_url": _uploadedImageMetadata!['s3Key'],
          "preview_image": _uploadedImageMetadata!['previewBase64'],
          "image_name": _pendingUploadFileName,
          "sort_order": _inspectionImages.length + 1,
          "annotation_list": annotations
        });
        _rawDocumentData['image_list'] = List.from(_inspectionImages);
      } else {
        _overlayParentObject!.imageUrls ??= [];
        _overlayParentObject!.imageUrls!.add({
          "image_id": _uploadedImageMetadata!['imageId'],
          "image_url": _uploadedImageMetadata!['s3Key'],
          "preview_image": _uploadedImageMetadata!['previewBase64'],
          "image_name": _pendingUploadFileName,
          "sort_order": _overlayParentObject!.imageUrls!.length + 1,
          "annotation_list": annotations
        });
      }

      _hasUnsavedChanges = true;
      _hasUnsavedImageChanges = true;
      _closeOverlay();
    });
    // ToastService.show(context, message: "Annotations applied successfully.", type: ToastType.info);
  }

  Future<Map<String, String>> _executeDirectS3Upload(String fileName, Uint8List bytes, bool isInspection) async {
    final String currentPageId = _pageDataMap[_currentPage]?.pageId ?? "";

    final Map<String, String> queryParams = {
      "fileName": fileName,
      "project_id": widget.projectId,
      "inspection_id": widget.inspectionId,
      "project_document_id": widget.documentId,
    };

    if (!isInspection && currentPageId.isNotEmpty) {
      queryParams["page_id"] = currentPageId;
    }

    final queryString = Uri(queryParameters: queryParams).query;
    final response = await _apiService.get('/image/presigned-url?$queryString');
    final responseData = jsonDecode(response.body);

    if (responseData['signedUrl'] != null && responseData['key'] != null) {
      final String signedUrl = responseData['signedUrl'];
      final String s3Key = responseData['key'];
      final String imageId = responseData['id'] ?? "";

      final uploadResponse = await http.put(Uri.parse(signedUrl), body: bytes);

      if (uploadResponse.statusCode == 200) {
        final encodedKey = Uri.encodeComponent(s3Key);
        String previewBase64 = "";
        bool isPreviewReady = false;
        int attempts = 0;
        const int maxAttempts = 10;

        while (!isPreviewReady && attempts < maxAttempts) {
          attempts++;
          final previewResponse = await _apiService.get('/dummyImageCompress/by-image-url?imageUrl=$encodedKey');
          if (previewResponse.statusCode == 200) {
            final previewData = jsonDecode(previewResponse.body);
            if (previewData['success'] == true && previewData['data'] != null && previewData['data']['compressed_base64'] != null) {
              previewBase64 = previewData['data']['compressed_base64'];
              isPreviewReady = true;
            } else throw Exception("Missing base64 data");
          } else if (previewResponse.statusCode == 404) {
            if (attempts < maxAttempts) await Future.delayed(const Duration(seconds: 2));
          } else throw Exception("API returned error: ${previewResponse.statusCode}");
        }

        if (!isPreviewReady) throw Exception("Image compression timeout");

        return {
          "imageId": imageId,
          "s3Key": s3Key,
          "previewBase64": previewBase64
        };
      } else {
         throw Exception("Upload failed with status: ${uploadResponse.statusCode}");
      }
    } else {
       throw Exception("Failed to get presigned URL");
    }
  }

  Future<String> _pollForBulkImagePreview(String s3Key) async {
    final encodedKey = Uri.encodeComponent(s3Key);
    String previewBase64 = "";
    bool isPreviewReady = false;
    int attempts = 0;
    const int maxAttempts = 10;

    while (!isPreviewReady && attempts < maxAttempts) {
      attempts++;
      final previewResponse = await _apiService.get('/dummyImageCompress/by-image-url?imageUrl=$encodedKey');
      if (previewResponse.statusCode == 200) {
        final previewData = jsonDecode(previewResponse.body);
        if (previewData['success'] == true && previewData['data'] != null && previewData['data']['compressed_base64'] != null) {
          previewBase64 = previewData['data']['compressed_base64'];
          isPreviewReady = true;
        } else {
          throw Exception("Missing base64 data");
        }
      } else if (previewResponse.statusCode == 404) {
        if (attempts < maxAttempts) await Future.delayed(const Duration(seconds: 2));
      } else {
        throw Exception("API returned error: ${previewResponse.statusCode}");
      }
    }

    if (!isPreviewReady) throw Exception("Image compression timeout");
    return previewBase64;
  }

  Future<void> _executeBulkS3Upload(
    List<Map<String, dynamic>> photos,
    void Function(int uploaded, int total) onProgress,
  ) async {
    final bool isInspection = _selectedCanvasObject == null;
    final DrawingObject? targetObject = _selectedCanvasObject;
    final String currentPageId = _pageDataMap[_currentPage]?.pageId ?? "";

    final Map<String, dynamic> body = {
      "file_names": photos.map((p) => p['fileName'] as String).toList(),
      "project_id": widget.projectId,
      "inspection_id": widget.inspectionId,
      "project_document_id": widget.documentId,
    };
    if (!isInspection && currentPageId.isNotEmpty) {
      body["page_id"] = currentPageId;
    }

    final response = await _apiService.post('/image/presigned-url-for-multiple-images', body);
    final responseData = jsonDecode(response.body);
    final List<dynamic> signedUrls = responseData['signedUrls'] ?? [];

    if (signedUrls.length != photos.length) {
      throw Exception("Failed to get presigned URLs for all photos");
    }

    final List<Map<String, dynamic>> newEntries = [];

    for (int i = 0; i < photos.length; i++) {
      final String fileName = photos[i]['fileName'] as String;
      final Uint8List bytes = photos[i]['bytes'] as Uint8List;
      final urlData = signedUrls[i];
      final String signedUrl = urlData['signedUrl'];
      final String s3Key = urlData['key'];
      final String imageId = urlData['id'] ?? "";

      final uploadResponse = await http.put(Uri.parse(signedUrl), body: bytes);
      if (uploadResponse.statusCode != 200) {
        throw Exception("Upload failed for $fileName with status: ${uploadResponse.statusCode}");
      }

      final previewBase64 = await _pollForBulkImagePreview(s3Key);

      newEntries.add({
        "image_id": imageId,
        "image_url": s3Key,
        "preview_image": previewBase64,
        "image_name": fileName,
      });

      onProgress(i + 1, photos.length);
    }

    setState(() {
      if (isInspection) {
        for (final entry in newEntries) {
          entry["sort_order"] = _inspectionImages.length + 1;
          _inspectionImages.add(entry);
        }
        _rawDocumentData['image_list'] = List.from(_inspectionImages);
      } else if (targetObject != null) {
        targetObject.imageUrls ??= [];
        for (final entry in newEntries) {
          entry["sort_order"] = targetObject.imageUrls!.length + 1;
          targetObject.imageUrls!.add(entry);
        }
      }
      _hasUnsavedChanges = true;
      _hasUnsavedImageChanges = true;
    });
  }


  // ==========================================
  // 🌟 UNIFIED GET API
  // ==========================================

  Future<void> _fetchAllDocumentData() async {
    try {
      final queryParams = {
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId,
        "project_document_id": widget.documentId,
      };

      final queryString = Uri(queryParameters: queryParams).query;
      final presignResponse = await _apiService.get('/canvas/pre-sign/inspection/read?$queryString');
      final presignData = jsonDecode(presignResponse.body);

      if (presignData['success'] == true && presignData['data'] != null) {
        final String signedUrl = presignData['data'];

        final s3Response = await http.get(Uri.parse(signedUrl));

        if (s3Response.statusCode == 200) {
          final data = jsonDecode(s3Response.body);
          _rawDocumentData = data;

          setState(() {
            _inspectionDescription = data['description'] ?? "";
            _inspectionTagIds = List<String>.from(data['tag_id_list'] ?? []);

            _inspectionImages.clear();
            if (data['image_list'] != null) {
              _inspectionImages = List<dynamic>.from(data['image_list']);
            }
          });

          if (widget.annotateImageKey != null) {
            _pages.clear();
            _pageDataMap.clear();

            _pages = ['Attached Image'];
            _currentPage = 'Attached Image';
            final pageData = PageData(pageId: widget.annotateImageKey!);

            var targetImageJson;
            if (data['image_list'] != null) {
              for (var img in data['image_list']) {
                if (img['image_url'] == widget.annotateImageKey) {
                  targetImageJson = img;
                  break;
                }
              }
            }

            if (targetImageJson != null) {
              final String base64String = targetImageJson['preview_image'] ?? '';
              if (base64String.isNotEmpty && base64String != "base64") {
                pageData.backgroundImageBytes = base64Decode(base64String.replaceAll('\n', ''));
                final ui.Image decodedImage = await _decodeBase64Image(base64String);
                pageData.width = decodedImage.width.toDouble();
                pageData.height = decodedImage.height.toDouble();
              } else {
                pageData.width = 816.0;
                pageData.height = 1056.0;
              }
              pageData.objects = _parseAnnotationsList(targetImageJson['annotation_list'], pageData.width, pageData.height);
            }
            pageData.hasLoadedAnnotations = true;
            _pageDataMap['Attached Image'] = pageData;

          } else {
            if (data['page_list'] != null) {
              for (var pageJson in data['page_list']) {
                final String pageId = pageJson['page_id'] ?? '';

                PageData? pageData;
                for (var pd in _pageDataMap.values) {
                  if (pd.pageId == pageId) {
                    pageData = pd;
                    break;
                  }
                }

                if (pageData != null) {
                  pageData.objects = _parseAnnotationsList(pageJson['annotation_list'], pageData.width, pageData.height);
                  pageData.hasLoadedAnnotations = true;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading document data from S3: $e");
    }
  }

  List<DrawingObject> _parseAnnotationsList(List<dynamic>? annList, double pWidth, double pHeight) {
    List<DrawingObject> loadedObjects = [];
    if (annList == null) return loadedObjects;

    for (var item in annList) {
      DrawingType parsedType = _parseDrawingType(item['type']);
      String? savedToolId = item['toolId'];

      List<DrawingObject>? matchedInternalShapes;
      if (parsedType == DrawingType.customTool && savedToolId != null) {
        for (var group in _customToolGroups) {
          try {
            final matchedTool = group.tools.firstWhere((t) => t.toolId == savedToolId);
            matchedInternalShapes = matchedTool.toolObjects;
            break;
          } catch(e) {}
        }
      }

      loadedObjects.add(DrawingObject(
        type: parsedType,
        toolId: savedToolId,
        internalShapes: matchedInternalShapes,
        start: Offset((item['start']['dx'] ?? 0.0) * pWidth, (item['start']['dy'] ?? 0.0) * pHeight),
        end: Offset((item['end']['dx'] ?? 0.0) * pWidth, (item['end']['dy'] ?? 0.0) * pHeight),
        strokeWidth: (item['strokeWidth'] ?? 2).toDouble(),
        text: item['text']?.isEmpty == true ? null : item['text'],
        description: item['description'],
        tagIds: List<String>.from(item['tagIds'] ?? []),
        imageUrls: item['image_list'] != null ? List<dynamic>.from(item['image_list']) : null,
        color: item['color'] != null ? Color(item['color']) : Colors.red[800]!,
        fillColor: item['fillColor'] != null ? Color(item['fillColor']) : Colors.transparent,
        borderColor: item['borderColor'] != null ? Color(item['borderColor']) : Colors.transparent,
        opacity: (item['opacity'] ?? 1.0).toDouble(),
        rotation: (item['rotation'] ?? 0.0).toDouble(),
        fontSize: (item['fontSize'] ?? 24.0).toDouble(),
        isBold: item['isBold'] ?? false,
        isItalic: item['isItalic'] ?? false,
        isUnderline: item['isUnderline'] ?? false,
        isStrikethrough: item['isStrikethrough'] ?? false,
        isCallout: item['isCallout'] ?? false,
        points: item['points'] != null ? (item['points'] as List).map((p) => Offset((p['dx'] ?? 0.0) * pWidth, (p['dy'] ?? 0.0) * pHeight)).toList() : null,
      ));
    }
    return loadedObjects;
  }

  // ==========================================
  // UNIFIED SAVING API
  // ==========================================

  List<Map<String, dynamic>> _serializeObjects(List<DrawingObject> objects, double pWidth, double pHeight) {
    List<Map<String, dynamic>> itemsList = [];
    for (var obj in objects) {
      List<Map<String, dynamic>> nestedImageList = [];
      if (obj.imageUrls != null) {
        for (var i = 0; i < obj.imageUrls!.length; i++) {
          var img = obj.imageUrls![i];
          if (img is Map) {
            nestedImageList.add({
              "image_id": img["image_id"] ?? "",
              "image_url": img["image_url"] ?? img["key"] ?? "",
              "preview_image": img["preview_image"] ?? "",
              "image_name": img["image_name"] ?? "",
              "sort_order": img["sort_order"] ?? (i + 1),
              "annotation_list": img["annotation_list"] ?? []
            });
          }
        }
      }

      Map<String, dynamic> item = {
        "type": _getDrawingTypeString(obj.type),
        "start": {"dx": obj.start.dx / pWidth, "dy": obj.start.dy / pHeight},
        "end": {"dx": obj.end.dx / pWidth, "dy": obj.end.dy / pHeight},
        if (obj.type == DrawingType.customTool) "toolId": obj.toolId,
        "text": obj.text ?? "",
        "description": obj.description ?? "",
        "strokeWidth": obj.strokeWidth,
        "tagIds": obj.tagIds ?? [],
        "image_list": nestedImageList,
        "color": obj.color.value,
        "fillColor": obj.fillColor.value,
        "borderColor": obj.borderColor.value,
        "opacity": obj.opacity,
        "rotation": obj.rotation,
        "fontSize": obj.fontSize,
        "isBold": obj.isBold,
        "isItalic": obj.isItalic,
        "isUnderline": obj.isUnderline,
        "isStrikethrough": obj.isStrikethrough,
        "isCallout": obj.isCallout,
      };

      if (obj.points != null && obj.points!.isNotEmpty) {
        item["points"] = obj.points!.map((p) => {"dx": p.dx / pWidth, "dy": p.dy / pHeight}).toList();
      }
      itemsList.add(item);
    }
    return itemsList;
  }

  Future<void> _saveAnnotations() async {
    setState(() => _isSaving = true);
    _syncCurrentPageObjects();

    try {
      Map<String, dynamic> masterPayload = Map<String, dynamic>.from(_rawDocumentData);

      masterPayload['project_document_id'] = widget.documentId;
      masterPayload['description'] = _inspectionDescription;
      masterPayload['tag_id_list'] = _inspectionTagIds;
      masterPayload['image_list'] = List.from(_inspectionImages);

      List<dynamic> currentPageList = List.from(masterPayload['page_list'] ?? []);
      for (int i = 0; i < _pages.length; i++) {
        final String pageName = _pages[i];
        final pageData = _pageDataMap[pageName];

        if (pageData != null) {
          final serializedObjects = _serializeObjects(pageData.objects, pageData.width, pageData.height);
          int existingIndex = currentPageList.indexWhere((p) => p['page_id'] == pageData.pageId);

          if (existingIndex != -1) {
            currentPageList[existingIndex]['annotation_list'] = serializedObjects;
          } else {
            currentPageList.add({
              "page_id": pageData.pageId,
              "page_name": pageName,
              "sort_order": i + 1,
              "annotation_list": serializedObjects
            });
          }
        }
      }
      masterPayload['page_list'] = currentPageList;

      final queryParams = {
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId,
        "project_document_id": widget.documentId,
      };

      final queryString = Uri(queryParameters: queryParams).query;
      final presignResponse = await _apiService.get('/canvas/pre-sign/inspection/write?$queryString');
      final presignData = jsonDecode(presignResponse.body);

      if (presignData['success'] == true && presignData['data'] != null) {
        final String signedUrl = presignData['data']['signedUrl'] ?? presignData['data'];

        final putResponse = await http.put(
          Uri.parse(signedUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(masterPayload),
        );

        if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
          _hasUnsavedChanges = false;
          _hasUnsavedImageChanges = false;
          _rawDocumentData = masterPayload;

          if (mounted) ToastService.show(context, message: "Document saved securely to cloud!", type: ToastType.success);
        } else {
          throw Exception("Failed to upload document data to S3. Status: ${putResponse.statusCode}");
        }
      } else {
        throw Exception(presignData['message'] ?? "Failed to get secure upload URL.");
      }

    } catch (e) {
      debugPrint("Save Error: $e");
      if (mounted) ToastService.show(context, message: "Error saving annotations.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==========================================
  // INITIALIZATION
  // ==========================================

  Future<void> _fetchAvailableTags() async {
    try {
      final response = await _apiService.get('/projectTagGroup/${widget.projectId}?includeTags=true');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null && mounted) {
        setState(() {
          // 🚀 Now it's incredibly simple to parse the whole grouped structure!
          _availableTagGroups = (responseData['data'] as List)
              .map((groupJson) => TagGroup.fromJson(groupJson))
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Error fetching tags: $e");
    } finally {
      if (mounted) setState(() => _isLoadingTags = false);
    }
  }

  Future<void> _fetchCustomTools() async {
    try {
      final response = await _apiService.get('/customTool/project/tool/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null && mounted) {
        List<CustomToolGroup> loadedGroups = [];
        for (var groupJson in responseData['data']) {
          List<CustomTool> tools = [];
          if (groupJson['toolds'] != null) {
            for (var toolJson in groupJson['toolds']) {
              List<DrawingObject> parsedObjects = [];
              if (toolJson['imageJsonData'] != null) {
                for (var item in toolJson['imageJsonData']) {
                  parsedObjects.add(DrawingObject.fromJson(item));
                }
              }
              tools.add(CustomTool(
                toolId: toolJson['toolId'] ?? '',
                toolName: toolJson['toolName'] ?? 'Unknown Tool',
                tagIds: List<String>.from(toolJson['tagIds'] ?? []),
                toolObjects: parsedObjects,
              ));
            }
          }
          loadedGroups.add(CustomToolGroup(toolGroup: groupJson['toolGroup'] ?? 'General', tools: tools));
        }
        setState(() => _customToolGroups = loadedGroups);
      }
    } catch (e) {
      debugPrint("Error fetching custom tools: $e");
    } finally {
      if (mounted) setState(() => _isLoadingCustomTools = false);
    }
  }

  Future<void> _initializeCanvas() async {
    setState(() => _isInitializing = true);

    _fetchAvailableTags();
    _fetchCustomTools();

    if (widget.annotateImageKey != null) {
      await _fetchAllDocumentData();
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _isFirstLoadComplete = true;
        });
      }
    } else {
      await _fetchPageList();
      if (_pages.isEmpty) {
        _pages = ['Page 1'];
        _currentPage = 'Page 1';
        _pageDataMap = {'Page 1': PageData(pageId: 'fallback_id')};
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _isPageLoading = true;
        });
      }

      await _fetchPageImage(_currentPage);

      if (mounted) {
        setState(() {
          _isPageLoading = false;
          _isLoadingAnnotations = true;
          _isFirstLoadComplete = true;
        });
      }

      await _fetchAllDocumentData();

      if (mounted) {
        setState(() {
          _canvasKeys.remove(_currentPage);
          _isLoadingAnnotations = false;
        });
      }
    }
  }

  Future<void> _fetchPageList() async {
    try {
      final response = await _apiService.get('/projectDocumentPage/project-document/${widget.documentId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final List pagesData = responseData['data'];
        _pages.clear();
        _pageDataMap.clear();

        for (var page in pagesData) {
          final String pageId = page['id'];
          final String pageName = page['name'] ?? 'Page ${page['page_number']}';
          _pages.add(pageName);
          _pageDataMap[pageName] = PageData(pageId: pageId);
        }

        if (_pages.isNotEmpty) {
          String targetPage = 'Page ${widget.page}';
          _currentPage = _pages.contains(targetPage) ? targetPage : _pages.first;
        }
      }
    } catch (e) { debugPrint("Error loading page list: $e"); }
  }

  Future<void> _fetchPageImage(String pageName) async {
    final pageData = _pageDataMap[pageName];
    if (pageData == null || pageData.backgroundImageBytes != null) return;

    try {
      final response = await _apiService.get('/projectDocumentPage/project-document-page-pre-signed-url/${pageData.pageId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final String preSignedUrl = responseData['data'];
        if (preSignedUrl.isNotEmpty) {
          final imageResponse = await http.get(Uri.parse(preSignedUrl));
          
          if (imageResponse.statusCode == 200) {
            final Uint8List imageBytes = imageResponse.bodyBytes;
            pageData.backgroundImageBytes = imageBytes;
            final ui.Image decodedImage = await _decodeBytesToImage(imageBytes);

            pageData.width = decodedImage.width.toDouble();
            pageData.height = decodedImage.height.toDouble();

            if (_rawDocumentData['page_list'] != null) {
              final pageJson = (_rawDocumentData['page_list'] as List).firstWhere(
                (p) => p['page_id'] == pageData.pageId,
                orElse: () => null
              );
              if (pageJson != null && pageJson['annotation_list'] != null) {
                pageData.objects = _parseAnnotationsList(pageJson['annotation_list'], pageData.width, pageData.height);
              }
            }

            _canvasKeys.remove(pageName);
          } else {
            debugPrint("Failed to download image from presigned URL. Status: ${imageResponse.statusCode}");
          }
        }
      }
    } catch (e) { debugPrint("Error loading page image: $e"); }
  }

  Future<void> _deleteImageForObject(String s3Key) async {
    setState(() {
      if (_selectedCanvasObject != null && _selectedCanvasObject!.imageUrls != null) {
        _selectedCanvasObject!.imageUrls!.removeWhere((img) => img['image_url'] == s3Key || img['key'] == s3Key);
        _getCurrentCanvasKey().currentState?.refreshCanvas();
      }
    });
  }

  DrawingType _parseDrawingType(String? typeStr) {
    switch (typeStr) {
      case 'rectangle': return DrawingType.rect;
      case 'circle': return DrawingType.circle;
      case 'polygon': return DrawingType.polygon;
      case 'line': return DrawingType.line;
      case 'arrow': return DrawingType.arrow;
      case 'text': return DrawingType.text;
      case 'pencil': return DrawingType.pencil;
      case 'pen': return DrawingType.pen;
      case 'pin': return DrawingType.pin;
      case 'customTool': return DrawingType.customTool;
      case 'brick': return DrawingType.brick;
      case 'grid': return DrawingType.grid;
      case 'horizontal': return DrawingType.horizontal;
      case 'vertical': return DrawingType.vertical;
      case 'forwardDiag': return DrawingType.forwardDiag;
      case 'reverseDiag': return DrawingType.reverseDiag;
      case 'diamond': return DrawingType.diamond;
      case 'weave': return DrawingType.weave;
      case 'dots': return DrawingType.dots;
      case 'herringbone': return DrawingType.herringbone;
      case 'concrete': return DrawingType.concrete;
      case 'shingles': return DrawingType.shingles;
      case 'insulation': return DrawingType.insulation;
      case 'rect': return DrawingType.rect;
      case 'customtool': return DrawingType.customTool;
      default: return DrawingType.rect;
    }
  }

  String _getDrawingTypeString(DrawingType type) {
    switch (type) {
      case DrawingType.rect: return 'rectangle';
      case DrawingType.circle: return 'circle';
      case DrawingType.polygon: return 'polygon';
      case DrawingType.line: return 'line';
      case DrawingType.arrow: return 'arrow';
      case DrawingType.text: return 'text';
      case DrawingType.pencil: return 'pencil';
      case DrawingType.pen: return 'pen';
      case DrawingType.pin: return 'pin';
      case DrawingType.customTool: return 'customTool';
      case DrawingType.brick: return 'brick';
      case DrawingType.grid: return 'grid';
      case DrawingType.horizontal: return 'horizontal';
      case DrawingType.vertical: return 'vertical';
      case DrawingType.forwardDiag: return 'forwardDiag';
      case DrawingType.reverseDiag: return 'reverseDiag';
      case DrawingType.diamond: return 'diamond';
      case DrawingType.weave: return 'weave';
      case DrawingType.dots: return 'dots';
      case DrawingType.herringbone: return 'herringbone';
      case DrawingType.concrete: return 'concrete';
      case DrawingType.shingles: return 'shingles';
      case DrawingType.insulation: return 'insulation';
      default: return 'rectangle';
    }
  }

  String _getToolNameFromType(DrawingType type) {
    switch (type) {
      case DrawingType.pencil: return 'Pencil';
      case DrawingType.pen: return 'Pen';
      case DrawingType.rect: return 'Rect';
      case DrawingType.circle: return 'Circle';
      case DrawingType.polygon: return 'Polygon';
      case DrawingType.line: return 'Line';
      case DrawingType.arrow: return 'Arrow';
      case DrawingType.text: return 'Text';
      case DrawingType.brick: return 'Brick';
      case DrawingType.grid: return 'Grid';
      case DrawingType.horizontal: return 'Horizontal';
      case DrawingType.vertical: return 'Vertical';
      case DrawingType.forwardDiag: return 'Forward';
      case DrawingType.reverseDiag: return 'Reverse';
      case DrawingType.weave: return 'Weave';
      case DrawingType.diamond: return 'Diamond';
      case DrawingType.dots: return 'Dots';
      case DrawingType.herringbone: return 'Herringbone';
      case DrawingType.concrete: return 'Concrete';
      case DrawingType.shingles: return 'Shingles';
      case DrawingType.insulation: return 'Insulation';
      case DrawingType.pin: return 'Pin';
      default: return 'CustomTool';
    }
  }

  Widget _buildPageSelector(ThemeData theme) {
    if (_pages.isEmpty) return const SizedBox.shrink();

    if (_pages.length <= 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
        child: Text(_currentPage, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
      );
    }

    int currentIndex = _pages.indexOf(_currentPage);
    bool hasPrevious = currentIndex > 0;
    bool hasNext = currentIndex < _pages.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            iconSize: 20,
            color: hasPrevious ? theme.colorScheme.primary : theme.disabledColor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
            onPressed: hasPrevious ? () => _switchPage(_pages[currentIndex - 1]) : null,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currentPage,
                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: theme.colorScheme.primary),
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                borderRadius: BorderRadius.circular(8),
                items: _pages.map((page) => DropdownMenuItem(value: page, child: Text(page))).toList(),
                onChanged: (v) => v != null ? _switchPage(v) : null,
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            iconSize: 20,
            color: hasNext ? theme.colorScheme.primary : theme.disabledColor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
            onPressed: hasNext ? () => _switchPage(_pages[currentIndex + 1]) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(ThemeData theme) {
    String title = "Loading...";
    String subtitle = "Please wait...";

    if (_isInitializing) {
      title = widget.annotateImageKey != null ? "Initializing Image..." : "Initializing Document...";
      subtitle = "Fetching document structure";
    } else if (_isPageLoading) {
      title = widget.annotateImageKey != null ? "Loading Image..." : "Loading Page...";
      subtitle = "Rendering visual layout";
    } else if (_isLoadingAnnotations) {
      title = "Loading Annotations...";
      subtitle = "Applying drawings and details";
    } else if (_isUploadingImage) {
      title = "Preparing Image...";
      subtitle = "Configuring layouts and compressing layers";
    } else if (_isSaving) {
      title = "Saving Changes...";
      subtitle = "Syncing annotations with the server";
    }

    final double bgOpacity = _isFirstLoadComplete ? 0.7 : 1.0;

    return Container(
      color: theme.scaffoldBackgroundColor.withOpacity(bgOpacity),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)
              ),
            ],
          ),
        ),
      ),
    );
  }

@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool isImageOpen = _overlayImageKey != null || widget.annotateImageKey != null;
    final String activeCanvasKey = _overlayImageKey != null ? 'IMG_$_overlayImageKey' : _currentPage;
    final PageData? activePageData = _pageDataMap[activeCanvasKey];

    return Stack(
      children: [
        custom_canvas.Canvas(
          key: _getCurrentCanvasKey(),
          initialBackgroundImage: activePageData?.backgroundImageBytes,
          initialObjects: activePageData?.objects ?? [],

          width: activePageData?.width ?? 816.0,
          height: activePageData?.height ?? 1056.0,

          onToolChanged: (toolName) {
            if (toolName != 'CustomTool' && _selectedCustomTool != null) {
              setState(() => _selectedCustomTool = null);
            }
          },
          customTabLabel: "Custom Tools",
          customTabContent: CustomToolsPanel(
            groups: _customToolGroups,
            isLoading: _isLoadingCustomTools,
            selectedTool: _selectedCustomTool,
            onToolSelected: (tool) {
              setState(() {
                if (_selectedCustomTool?.toolId == tool.toolId) {
                  _selectedCustomTool = null;
                  _getCurrentCanvasKey().currentState?.applyExternalToolConfig(
                    'Select', 2.0, Colors.black, Colors.transparent, 1.0,
                  );
                } else {
                  _selectedCustomTool = tool;

                  if (tool.toolObjects.length == 1) {
                    final obj = tool.toolObjects.first;
                    final nativeToolName = _getToolNameFromType(obj.type);

                    _getCurrentCanvasKey().currentState?.applyExternalToolConfig(
                      nativeToolName,
                      obj.strokeWidth,
                      obj.color,
                      obj.fillColor ?? Colors.transparent,
                      obj.opacity,
                    );
                  } else {
                    _getCurrentCanvasKey().currentState?.applyExternalToolConfig(
                      'CustomTool', 2.0, Colors.black, Colors.transparent, 1.0,
                      customToolId: tool.toolId,
                      customToolShapes: tool.toolObjects,
                    );
                  }
                }
              });
            },
            onClose: () {
              setState(() => _selectedCustomTool = null);
              _getCurrentCanvasKey().currentState?.applyExternalToolConfig('Select', 2, Colors.black, Colors.transparent, 1);
            },
          ),

          customRightPanel: PropertiesPanel(
            activeObject: _selectedCanvasObject,
            availableTags: _availableTagGroups,
            isLoadingTags: _isLoadingTags,
            inspectionDescription: _inspectionDescription,
            inspectionTagIds: _inspectionTagIds,
            inspectionImageUrls: _inspectionImages,

            isInspectionLevel: !isImageOpen,
            allowImageUpload: !isImageOpen,
            showImageSection: !isImageOpen,

            onInspectionDescriptionChanged: (val) {
              setState(() => _inspectionDescription = val);
              _hasUnsavedChanges = true;
            },
            onInspectionTagsChanged: (val) {
              setState(() => _inspectionTagIds = val);
              _hasUnsavedChanges = true;
            },

            onUpdate: () {
              _hasUnsavedChanges = true;
              _getCurrentCanvasKey().currentState?.refreshCanvas();
            },

            onImageUpload: (fileName, bytes) async {
              await _setupLocalImageOverlay(fileName, bytes, _selectedCanvasObject == null);
            },

            onBulkImageUpload: _executeBulkS3Upload,

            onImageDelete: (s3Key) async {
              if (_selectedCanvasObject != null) {
                await _deleteImageForObject(s3Key);
              } else {
                setState(() {
                  _inspectionImages.removeWhere((img) => img['image_url'] == s3Key || img['key'] == s3Key);
                  _rawDocumentData['image_list'] = List.from(_inspectionImages);
                  _hasUnsavedImageChanges = true;
                  _hasUnsavedChanges = true;
                });
              }
            },

            onImageTap: _handleImageTap,
            onClose: () {
              setState(() => _selectedCanvasObject = null);
              _getCurrentCanvasKey().currentState?.applyExternalToolConfig('Select', 2, Colors.black, Colors.transparent, 1);
            },
          ),

          showCloseButton: false,
          leftActions: const [],
          rightActions: _overlayImageKey != null
              ? [
                  Button(
                    label: "Discard",
                    variant: ButtonVariant.outline,
                    onPressed: _discardImageAnnotations
                  ),
                  const SizedBox(width: 8),
                  Button(
                    label: "Done",
                    onPressed: _saveImageAnnotationsToMemory
                  ),
                ]
              : [
                  _buildPageSelector(theme),
                  const SizedBox(width: 12),
                  PdfExportButton(
                    documentId: widget.documentId,
                    hasUnsavedChanges: _hasUnsavedChanges || _hasUnsavedImageChanges,
                    onExportStart: () => setState(() => _isExporting = true),
                    onExportEnd: () => setState(() => _isExporting = false),
                  ),
                  const SizedBox(width: 8),
                  CanvasToolbarActionButton(
                    tooltip: "Save Annotations",
                    icon: Icons.save_outlined,
                    onTap: _saveAnnotations,
                  ),
                  const SizedBox(width: 8),
                ],

          onSelectionChanged: (selectedObject) {
            setState(() {
              _selectedCanvasObject = selectedObject;
              if (selectedObject != null) _hasUnsavedChanges = true;
            });
          },
        ),

        if (_isInitializing || _isPageLoading || _isLoadingAnnotations || _isSaving || _isUploadingImage || _isExporting)
          _buildLoadingOverlay(theme),
      ],
    );
  }
}
