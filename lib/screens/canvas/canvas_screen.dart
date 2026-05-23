import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

import '../../../core/api_service.dart';
import '../../services/toast_service.dart';

import '../../../widgets/canvas/canvas.dart' as custom_canvas;
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/confirmation/confirmation_remove.dart';
import 'widgets/properties_panel.dart';
import 'widgets/custom_tools_panel.dart';
import 'utils/canvas_export.dart';

class CanvasScreen extends StatefulWidget {
  final String documentId;
  final String projectDocumentId;
  final String projectId;
  final String inspectionId;
  final String page;

  final String? annotateImageUrl; 
  final String? annotateImageKey;

  final bool isInspectionImage;

  const CanvasScreen({
    super.key,
    required this.projectId,
    required this.inspectionId,
    required this.documentId,
    required this.projectDocumentId,
    this.page = '1',
    this.annotateImageUrl,
    this.annotateImageKey,
    this.isInspectionImage = false,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final ApiService _apiService = ApiService();
  final Map<String, GlobalKey<custom_canvas.CanvasState>> _canvasKeys = {};

  bool _isPageLoading = false;
  bool _isLoadingDocument = true;
  bool _isSaving = false;

  bool _hasUnsavedChanges = false;

  DrawingObject? _selectedCanvasObject;
  List<CustomToolGroup> _customToolGroups = [];
  CustomTool? _selectedCustomTool;

  List<String> _pages = [];
  String _currentPage = ''; 
  Map<String, PageData> _pageDataMap = {};
  List<ProjectTag> _availableTags = [];

  // 🌟 NEW: INSPECTION LEVEL STATE 🌟
  String _inspectionDescription = "";
  List<String> _inspectionTagIds = [];
  List<String> _inspectionImageUrls = [];

  @override
  void initState() {
    super.initState();
    _initializeCanvas();
  }

  GlobalKey<custom_canvas.CanvasState> _getCurrentCanvasKey() {
    if (_currentPage.isEmpty) return GlobalKey<custom_canvas.CanvasState>();
    _canvasKeys.putIfAbsent(_currentPage, () => GlobalKey<custom_canvas.CanvasState>());
    return _canvasKeys[_currentPage]!;
  }

  void _syncCurrentPageObjects() {
    if (_currentPage.isEmpty) return;
    final key = _getCurrentCanvasKey();
    if (key.currentState != null && _pageDataMap.containsKey(_currentPage)) {
      _pageDataMap[_currentPage]!.objects = key.currentState!.objects;
    }
  }

  void _switchPage(String newPage) async {
    _syncCurrentPageObjects(); 
    setState(() {
      _currentPage = newPage;
      _selectedCanvasObject = null;
    });
    await _fetchPageImage(newPage);
    await _fetchSavedAnnotations(newPage); 
  }

  Future<ui.Image> _decodeBase64Image(String base64Str) async {
    String cleanBase64 = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
    final Uint8List bytes = base64Decode(cleanBase64);
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  // ==========================================
  // 🌟 NEW: INSPECTION LEVEL API METHODS 🌟
  // ==========================================
  
  Future<void> _fetchInspectionAnnotation() async {
    try {
      // final response = await _apiService.get('/inspection/annotation/${widget.inspectionId}'); // TODO
      final response = await _apiService.get('/inspection/document/annotation/${widget.projectDocumentId}');
      final resData = jsonDecode(response.body);

      if (resData['success'] == true && resData['data'] != null) {
        final List dataList = resData['data']; 
        
        if (dataList.isNotEmpty) {
          final data = dataList[0];
          setState(() {
            _inspectionDescription = data['description'] ?? "";
            _inspectionTagIds = List<String>.from(data['tag_id_list'] ?? []);
            _inspectionImageUrls = List<String>.from(data['image_url_list'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching inspection data: $e");
    }
  }

  Future<void> _saveInspectionLevelAnnotation() async {
    try {
      final payload = {
        "json_data": [
          {
            "description": _inspectionDescription,
            "tag_id_list": _inspectionTagIds,
            "image_url_list": _inspectionImageUrls
          }
        ],
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId,
        "project_document_id": widget.projectDocumentId,
      };
      // await _apiService.post('/inspection/add-annotation/${widget.inspectionId}', payload); // TODO
      await _apiService.post('/inspection/document/add-annotation', payload);
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Error saving inspection details.", type: ToastType.error);
    }
  }

  Future<void> _uploadInspectionImage(String fileName, Uint8List bytes) async {
    try {
      final payload = {
        "file": fileName,
        "content_type": "image/jpeg", 
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId,
        "project_document_id": widget.projectDocumentId,
      };
      
      // final response = await _apiService.post('/inspection/project-inspection-images/presigned-url', payload); // TODO
      final response = await _apiService.post('/inspection/document/image/presigned-url', payload);
      final responseData = jsonDecode(response.body);
      
      if (responseData['signedUrl'] != null && responseData['key'] != null) {
        final String signedUrl = responseData['signedUrl'];
        final String s3Key = responseData['key'];
        
        final uploadResponse = await http.put(Uri.parse(signedUrl), body: bytes);
        
        if (uploadResponse.statusCode == 200) {
           setState(() {
              _inspectionImageUrls.add(s3Key);
           });
          //  await _saveInspectionLevelAnnotation(); // Sync with API immediately
        } else {
           throw Exception("Inspection image S3 upload failed");
        }
      }
    } catch(e) {
      if (mounted) ToastService.show(context, message: "Failed to upload inspection image.", type: ToastType.error);
    }
  }

  // ==========================================
  // EXISTING API METHODS
  // ==========================================

  Future<void> _fetchAvailableTags() async {
    try {
      final response = await _apiService.get('/project/tags/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        setState(() {
          _availableTags = (responseData['data'] as List)
              .map((tagJson) => ProjectTag.fromJson(tagJson))
              .toList();
        });
      }
    } catch (e) { debugPrint("Error fetching tags: $e"); }
  }

  Future<void> _initializeCanvas() async {
    setState(() => _isLoadingDocument = true);
    
    await _fetchAvailableTags(); 
    await _fetchCustomTools(); 
    await _fetchInspectionAnnotation(); 
    
    if (widget.annotateImageKey != null) {
      _pages = ['Attached Image'];
      _currentPage = 'Attached Image';
      
      try {
        http.Response imageResponse;
        http.Response annResponse;

        // 🔀 BRANCH 1: FETCHING INSPECTION IMAGES
        if (widget.isInspectionImage) {
          // 1. Fetch the image using the new Inspection API
          final String encodedKey = Uri.encodeComponent(widget.annotateImageKey!);
          // imageResponse = await _apiService.get('/inspection/annotation/image?key=$encodedKey'); // TODO
          imageResponse = await _apiService.get('/inspection/document/image?key=$encodedKey');
          
          // 2. Fetch the JSON data (⚠️ REPLACE WITH YOUR ACTUAL INSPECTION GET-JSON API)
          final jsonKey = Uri.encodeComponent('${widget.annotateImageKey}/image.json');
          // annResponse = await _apiService.get('/inspection/annotationImage/image_json?InspectionImageJsonUrl=$jsonKey'); // TODO
          annResponse = await _apiService.get('/inspection/document/annotationImage/image_json?InspectionDocumentImageJsonUrl=$jsonKey');
        } 
        // 🔀 BRANCH 2: FETCHING OBJECT IMAGES (Your existing code)
        else {
          imageResponse = await _apiService.get('/customTool/tool/Image?key=${widget.annotateImageKey}');
          
          final jsonKey = Uri.encodeComponent('${widget.annotateImageKey}/image.json');
          annResponse = await _apiService.get('/canvas/imageDataFromS3?imageJsonUrl=$jsonKey');
        }
        
        if (imageResponse.statusCode == 200) {
          final jsonResp = jsonDecode(imageResponse.body);
          if (jsonResp['success'] == true && jsonResp['data'] != null) {
            String b64 = jsonResp['data'];
            if (b64.contains(',')) b64 = b64.split(',').last;
            
            _pageDataMap = {
              'Attached Image': PageData(pageId: widget.annotateImageKey!, backgroundImageBytes: base64Decode(b64))
            };
          }
        }

        // final jsonKey = Uri.encodeComponent('${widget.annotateImageKey}/image.json');
        // final annResponse = await _apiService.get('/canvas/imageDataFromS3?imageJsonUrl=$jsonKey');
        
        if (annResponse.statusCode == 200) {
           final annData = jsonDecode(annResponse.body);
           if (annData['success'] == true && annData['data'] != null && annData['data'].isNotEmpty) {
             List<DrawingObject> loadedObjects = [];
             final List items = annData['data'][0]['items'] ?? [];
             
             for (var item in items) {
                DrawingType parsedType = _parseDrawingType(item['type']);
                String? savedToolId = item['toolId'];
                
                // 🚀 NEW: We extract the JSON shapes instead of the image
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
                  internalShapes: matchedInternalShapes, // 🚀 Inject the JSON objects here!
                  start: Offset(item['start']['dx'] * 816.0, item['start']['dy'] * 1056.0),
                  end: Offset(item['end']['dx'] * 816.0, item['end']['dy'] * 1056.0),
                  text: item['text'],
                  description: item['description'],
                  strokeWidth: (item['strokeWidth'] ?? 2.0).toDouble(),
                  tagIds: item['tagIds'] != null ? List<String>.from(item['tagIds']) : null,
                  imageUrls: item['imageUrl'] != null ? List<String>.from(item['imageUrl']) : null,
                  points: (item['points'] as List?)?.map((p) => Offset(p['dx'] * 816.0, p['dy'] * 1056.0)).toList(),
                  color: item['color'] != null ? Color(item['color']) : Colors.red,
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
                ));
             }
             setState(() { _pageDataMap['Attached Image']?.objects = loadedObjects; });
           }
        }
      } catch (e) { debugPrint("Failed to load secure image: $e"); }
    } 
    else {
      await _fetchPageList();
      if (_pages.isEmpty) {
        _pages = ['Page 1'];
        _currentPage = 'Page 1';
        _pageDataMap = {'Page 1': PageData(pageId: 'fallback_id')};
      }
      if (_pages.isNotEmpty) {
        await _fetchPageImage(_currentPage);
        await _fetchSavedAnnotations(_currentPage);
      }
    }
    setState(() => _isLoadingDocument = false);
  }
  
  Future<void> _fetchPageList() async {
    try {
      final response = await _apiService.get('/templateDocumentPage/template-document/${widget.documentId}');
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

    setState(() => _isPageLoading = true);
    try {
      final response = await _apiService.get('/templateDocumentPage/pdf/${pageData.pageId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final String base64String = responseData['data']['image'] ?? '';
        if (base64String.isNotEmpty) {
          pageData.backgroundImageBytes = base64Decode(base64String.replaceAll('\n', ''));
        }
      }
    } catch (e) { debugPrint("Error loading page image: $e"); } 
    finally { setState(() => _isPageLoading = false); }
  }
  
  Future<void> _fetchSavedAnnotations(String pageName) async {
    final pageData = _pageDataMap[pageName];
    if (pageData == null || pageData.hasLoadedAnnotations) return;

    try {
      final String url = '/canvas/jsonDataFromS3?project_id=${widget.projectId}&page_name=${Uri.encodeComponent(pageName)}&template_document_id=${widget.documentId}&template_document_page_id=${pageData.pageId}&inspection_id=${widget.inspectionId}';
      final response = await _apiService.get(url);
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final List dataList = responseData['data'];
        final pageJson = dataList.firstWhere((p) => p['page_name'] == pageName, orElse: () => null);

        if (pageJson != null && pageJson['items'] != null) {
          List<DrawingObject> loadedObjects = [];
          for (var item in pageJson['items']) {
            DrawingType parsedType = _parseDrawingType(item['type']);
            String? savedToolId = item['toolId'];
            
            // 🚀 NEW: Extract JSON shapes for multi-page documents
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
              internalShapes: matchedInternalShapes, // 🚀 Inject shapes here!
              start: Offset((item['start']['dx'] ?? 0.0) * 816.0, (item['start']['dy'] ?? 0.0) * 1056.0),
              end: Offset((item['end']['dx'] ?? 0.0) * 816.0, (item['end']['dy'] ?? 0.0) * 1056.0),
              strokeWidth: (item['strokeWidth'] ?? 2).toDouble(),
              text: item['text']?.isEmpty == true ? null : item['text'],
              description: item['description'],
              tagIds: List<String>.from(item['tagIds'] ?? []),
              imageUrls: List<String>.from(item['imageUrl'] ?? []),
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
              points: item['points'] != null ? (item['points'] as List).map((p) => Offset((p['dx'] ?? 0.0) * 816.0, (p['dy'] ?? 0.0) * 1056.0)).toList() : null,
            ));
          }
          setState(() { pageData.objects = loadedObjects; });
        }
      }
      pageData.hasLoadedAnnotations = true;
    } catch (e) { debugPrint("Error loading saved annotations: $e"); }
  }

  List<Map<String, dynamic>> _serializeObjects(List<DrawingObject> objects) {
    List<Map<String, dynamic>> itemsList = [];
    
    for (var obj in objects) {
      Map<String, dynamic> item = {
        "type": _getDrawingTypeString(obj.type),
        "start": {"dx": obj.start.dx / 816.0, "dy": obj.start.dy / 1056.0},
        "end": {"dx": obj.end.dx / 816.0, "dy": obj.end.dy / 1056.0},
        if (obj.type == DrawingType.customTool) "toolId": obj.toolId, 
        "text": obj.text ?? "",
        "description": obj.description ?? "",
        "strokeWidth": obj.strokeWidth,
        "tagIds": obj.tagIds ?? [],
        "imageUrl": obj.imageUrls ?? [],
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
        item["points"] = obj.points!.map((p) => {"dx": p.dx / 816.0, "dy": p.dy / 1056.0}).toList();
      }
      itemsList.add(item);
    }
    return itemsList;
  }
  
  Future<void> _saveAnnotations() async {
    setState(() => _isSaving = true);
    _syncCurrentPageObjects(); 
    
    // Also explicitly save the inspection level metadata just in case
    await _saveInspectionLevelAnnotation();

    try {
      if (widget.annotateImageKey != null) {
        final pageData = _pageDataMap['Attached Image'];
        if (pageData == null) return;

        final itemsList = _serializeObjects(pageData.objects);
        List<Map<String, dynamic>> wrapperArray = [{"page_name": "Image Preview", "sort_order": 0, "items": itemsList}];
        Map<String, dynamic> payload = {"imageS3": widget.annotateImageKey, "imageJsonData": jsonEncode(wrapperArray)};
        
        http.Response response;

        // 🔀 BRANCH 1: SAVING INSPECTION IMAGES
        if (widget.isInspectionImage) {
          //  response = await _apiService.post('/inspection/annotationImage/image_json', payload); // TODO
           response = await _apiService.post('/inspection/document/annotationImage/image_json', payload);
        } 
        // 🔀 BRANCH 2: SAVING OBJECT IMAGES
        else {
           response = await _apiService.post('/canvas/image/jsonData', payload);
        }

        final resData = jsonDecode(response.body);

        if (resData['success'] == true) {
          _hasUnsavedChanges = false; // 🚀 Reset on save!
          if (mounted) ToastService.show(context, message: "Image Annotations saved successfully!", type: ToastType.success);
        } else {
          throw Exception(resData['message'] ?? 'Failed to save image annotations');
        }
      } 
      else {
        List<Future<http.Response>> saveTasks = [];

        for (String pageName in _pages) {
          final pageData = _pageDataMap[pageName];
          if (pageData != null && pageData.hasLoadedAnnotations) {
            final itemsList = _serializeObjects(pageData.objects);
            List<Map<String, dynamic>> canvasDataObj = [
              {"page_name": pageName, "sort_order": _pages.indexOf(pageName), "items": itemsList}
            ];

            Map<String, dynamic> payload = {
              "project_id": widget.projectId,
              "page_name": pageName,
              "canvas_data": jsonEncode(canvasDataObj),
              "template_document_id": widget.documentId,
              "template_document_page_id": pageData.pageId,
              "inspection_id": widget.inspectionId
            };

            saveTasks.add(_apiService.post('/canvas/json/s3', payload));
          }
        }

        if (saveTasks.isNotEmpty) {
          final responses = await Future.wait(saveTasks);
          for (var response in responses) {
            final resData = jsonDecode(response.body);
            if (resData['success'] != true) {
              throw Exception(resData['message'] ?? 'Failed to save a page');
            }
          }
        }
        _hasUnsavedChanges = false;
        if (mounted) ToastService.show(context, message: "All Annotations saved successfully!", type: ToastType.success);
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Error saving annotations.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _uploadImageForObject(String fileName, Uint8List bytes) async {
    try {
      final payload = {"file": fileName, "project_id": widget.projectId, "inspection_id": widget.inspectionId};
      final response = await _apiService.post('/customTool/tool/Image/presignedUrl', payload);
      final responseData = jsonDecode(response.body);
      
      if (responseData['signedUrl'] != null && responseData['key'] != null) {
        final String signedUrl = responseData['signedUrl'];
        final String s3Key = responseData['key'];
        
        final uploadResponse = await http.put(Uri.parse(signedUrl), body: bytes);
        
        if (uploadResponse.statusCode == 200) {
           setState((){
              if (_selectedCanvasObject != null) {
                _selectedCanvasObject!.imageUrls ??= [];
                _selectedCanvasObject!.imageUrls!.add(s3Key);
                _getCurrentCanvasKey().currentState?.refreshCanvas(); 
              }
           });
        } else {
           throw Exception("Object S3 upload failed with status: ${uploadResponse.statusCode}");
        }
      }
    } catch(e) {
      if (mounted) ToastService.show(context, message: "Failed to upload image.", type: ToastType.error);
    }
  }

  Future<void> _deleteImageForObject(String s3Key) async {
    try {
      final response = await _apiService.delete('/customTool/tool/Image/$s3Key');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          if (_selectedCanvasObject != null && _selectedCanvasObject!.imageUrls != null) {
            _selectedCanvasObject!.imageUrls!.remove(s3Key);
            _getCurrentCanvasKey().currentState?.refreshCanvas(); 
          }
        });
      } else {
        throw Exception("Object Delete failed with status: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Failed to delete image.", type: ToastType.error);
    }
  }

  Future<void> _fetchCustomTools() async {
    try {
      final response = await _apiService.get('/customTool/project/tool/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        List<CustomToolGroup> loadedGroups = [];
        
        for (var groupJson in responseData['data']) {
          List<CustomTool> tools = [];
          
          // Using the exact key 'toolds' from your API response
          if (groupJson['toolds'] != null) {
            for (var toolJson in groupJson['toolds']) {
              List<DrawingObject> parsedObjects = [];
              
              // 🚀 Using 'imageJsonData' from the API to parse the vector shapes
              if (toolJson['imageJsonData'] != null) {
                for (var item in toolJson['imageJsonData']) {
                  parsedObjects.add(DrawingObject.fromJson(item));
                }
              }

              tools.add(CustomTool(
                toolId: toolJson['toolId'] ?? '', 
                toolName: toolJson['toolName'] ?? 'Unknown Tool',
                tagIds: List<String>.from(toolJson['tagIds'] ?? []),
                toolObjects: parsedObjects, // The parsed JSON shapes!
              ));
            }
          }
          loadedGroups.add(CustomToolGroup(
            toolGroup: groupJson['toolGroup'] ?? 'General', 
            tools: tools
          ));
        }
        setState(() => _customToolGroups = loadedGroups);
      }
    } catch (e) { 
      debugPrint("Error fetching custom tools: $e"); 
    }
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

  Widget _buildPageSelector(ThemeData theme) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    if (_pages.length <= 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
        child: Text(_currentPage, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
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
    );
  }

  Future<void> _handleClose() async {
    if (!_hasUnsavedChanges) {
      _executeRefreshAndClose();
      return;
    }
    
    bool shouldClose = false;

    await showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Exit Without Saving?",
        description: "Are you sure you want to exit? Any unsaved changes will be permanently lost.",
        confirmLabel: "Exit",
        cancelLabel: "Cancel",
        confirmColor: Colors.red,
        onConfirm: () async {
          shouldClose = true;
        },
      ),
    );

    if (shouldClose && mounted) {
      // 🚀 FIX 1: Call the helper method here instead of a raw pop!
      _executeRefreshAndClose();
    }
  }

  void _executeRefreshAndClose() {
    // 🚀 FIX 2: Check if this is the NESTED image canvas
    // If annotateImageKey is not null, we know this is a sub-canvas opened via Navigator.push
    if (widget.annotateImageKey != null) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); 
      }
      return; // Stop here! Don't mess with go_router for nested screens.
    }

    // --- BELOW IS ONLY FOR THE MAIN DOCUMENT CANVAS ---

    // 1. Grab the extra data passed from the go_router
    final extra = GoRouterState.of(context).extra;
    
    // 2. Safely execute the refresh function depending on how you passed it
    if (extra is Function) {
      extra(); 
    } else if (extra is Map<String, dynamic> && extra['onRefresh'] is Function) {
      extra['onRefresh']();
    }

    // 3. Safely pop or route back
    if (extra is Map<String, dynamic> && extra['returnUrl'] != null) {
       context.go(extra['returnUrl']);
    } else if (Navigator.of(context).canPop()) {
       Navigator.of(context).pop();
    } else {
       context.go('/'); // Ultimate fallback so they never get stuck
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingDocument) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(widget.annotateImageKey == null ? "Loading Document..." : "Loading Image...", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: custom_canvas.Canvas(
        key: _getCurrentCanvasKey(),
        initialBackgroundImage: _pageDataMap[_currentPage]?.backgroundImageBytes,
        initialObjects: _pageDataMap[_currentPage]?.objects ?? [],
        onToolChanged: (toolName) {
          if (toolName != 'CustomTool' && _selectedCustomTool != null) {
            setState(() => _selectedCustomTool = null);
          }
        },
        customTabLabel: "Custom Tools",
        customTabContent: CustomToolsPanel(
          groups: _customToolGroups,
          selectedTool: _selectedCustomTool,
          onToolSelected: (tool) {
            setState(() {
              _selectedCustomTool = tool;
              _getCurrentCanvasKey().currentState?.applyExternalToolConfig(
                'CustomTool', 2, Colors.black, Colors.transparent, 1,
                customToolId: tool.toolId,
                customToolShapes: tool.toolObjects, 
              );
            });
          },
          onClose: () {
             setState(() => _selectedCustomTool = null);
             _getCurrentCanvasKey().currentState?.applyExternalToolConfig('Select', 2, Colors.black, Colors.transparent, 1);
          },
        ),

        // 🌟 CONDITIONAL PROPERTIES PANEL 🌟
        customRightPanel: PropertiesPanel(
          activeObject: _selectedCanvasObject, 
          availableTags: _availableTags,
          
          // 🚀 SEND DOWN THE INSPECTION STATE
          inspectionDescription: _inspectionDescription,
          inspectionTagIds: _inspectionTagIds,
          inspectionImageUrls: _inspectionImageUrls,
          
          // 🚀 FIX: Removed the API calls here! Now it just updates local state.
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
          
          // 🚀 ROUTE UPLOAD LOGIC
          onImageUpload: (fileName, bytes) async {
            if (_selectedCanvasObject != null) {
              await _uploadImageForObject(fileName, bytes);
            } else {
              await _uploadInspectionImage(fileName, bytes);
            }
          },
          
          // 🚀 ROUTE DELETE LOGIC
          onImageDelete: (s3Key) async {
            if (_selectedCanvasObject != null) {
              await _deleteImageForObject(s3Key);
            } else {
              setState(() {
                _inspectionImageUrls.remove(s3Key);
              });
              await _saveInspectionLevelAnnotation(); // Auto-save DB removal
            }
          },
          
          allowImageUpload: widget.annotateImageKey == null,
          
          // 🚀 (Optional) If you want the API to fetch the image view, you can do it here, 
          // but if your S3 links are public, the direct URL routing below works perfectly!
          onImageTap: (s3Key, url) {
            Navigator.push(context, MaterialPageRoute(
                builder: (context) => CanvasScreen(
                  projectDocumentId: widget.projectDocumentId,
                  documentId: widget.documentId, 
                  projectId: widget.projectId,
                  inspectionId: widget.inspectionId, 
                  annotateImageUrl: url, 
                  annotateImageKey: s3Key,
                  isInspectionImage: _selectedCanvasObject == null, 
                ),
            ));
          },
          onClose: () {
            setState(() => _selectedCanvasObject = null);
            _getCurrentCanvasKey().currentState?.applyExternalToolConfig('Select', 2, Colors.black, Colors.transparent, 1);
          },
        ),

        showCloseButton: true,
        onClosePressed: _handleClose,
        leftActions: [],
        rightActions: [
          if (widget.annotateImageKey == null) _buildPageSelector(theme),
          const SizedBox(width: 12),
          
          if (_isSaving)
            Container(margin: const EdgeInsets.symmetric(horizontal: 12), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary))
          else
            IconButton(tooltip: "Save Annotations", icon: const Icon(Icons.save_outlined), color: theme.colorScheme.primary, onPressed: _saveAnnotations),
          
          const SizedBox(width: 8),
          
          // PopupMenuButton<String>(
          //   tooltip: "Export PDF",
          //   icon: const Icon(Icons.picture_as_pdf_outlined), 
          //   offset: const Offset(0, 45),
          //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          //   onSelected: (val) {
          //     _syncCurrentPageObjects(); 
          //     exportCanvasToPdf(
          //       context: context, exportAll: val == 'all', pages: _pages, 
          //       currentPage: _currentPage, pageDataMap: _pageDataMap
          //     );
          //   },
          //   itemBuilder: (context) => [
          //     const PopupMenuItem(value: 'current', child: ListTile(leading: Icon(Icons.insert_drive_file_outlined, size: 18), title: Text("Export Current Page"), dense: true)),
          //     const PopupMenuItem(value: 'all', child: ListTile(leading: Icon(Icons.copy_all_rounded, size: 18), title: Text("Export All Pages"), dense: true)),
          //   ],
          // ),
        ],

        onSelectionChanged: (selectedObject) {
          setState(() {
            _selectedCanvasObject = selectedObject;
            if (selectedObject != null) _hasUnsavedChanges = true;
          });
        },
      ),
    );
  }
}