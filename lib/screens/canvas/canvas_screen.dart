import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

import '../../../core/api_service.dart';
import '../../services/toast_service.dart';

import 'models/canvas_models.dart';
import 'widgets/canvas_painter.dart';
import 'widgets/properties_panel.dart';
import 'widgets/custom_tools_panel.dart';
import 'utils/canvas_export.dart';

class CanvasScreen extends StatefulWidget {
  final String documentId;
  final String projectId;
  final String inspectionId;
  final String page;

  final String? annotateImageUrl; 
  final String? annotateImageKey;

  const CanvasScreen({
    super.key,
    required this.projectId,
    required this.inspectionId,
    required this.documentId,
    this.page = '1',
    this.annotateImageUrl,
    this.annotateImageKey,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final ApiService _apiService = ApiService();

  final FocusNode _canvasFocusNode = FocusNode();
  
  bool _isFullScreen = false;
  // State for our API Loading
  bool _isPageLoading = false;
  bool _isLoadingDocument = true;
  bool _isSaving = false;

  String _selectedTool = 'Select';

  double _pencilStrokeWidth = 2.0;
  double _shapeStrokeWidth = 2.0;
  double _textStrokeWidth = 2.0;
  
  Color _pencilColor = Colors.black;
  Color _penFillColor = Colors.transparent;
  double _pencilOpacity = 1.0; 

  Color _shapeLineColor = Colors.black;
  Color _shapeBorderColor = Colors.black;
  Color _shapeFillColor = Colors.transparent;
  double _shapeOpacity = 1.0;

  Color _textColor = Colors.black;
  Color _textBorderColor = Colors.transparent;
  Color _textFillColor = Colors.transparent;
  double _textOpacity = 1.0;

  double _textSize = 24.0;
  bool _textIsBold = false;
  bool _textIsItalic = false;
  bool _textIsUnderline = false;
  bool _textIsStrikethrough = false;

  DrawingObject? _currentPreview;
  DrawingObject? _activeObject; 
  DrawingObject? _clipboard; 
  
  ResizeHandle _activeHandle = ResizeHandle.none;
  ResizeHandle _hoveredHandle = ResizeHandle.none;
  Offset _dragOffset = Offset.zero;
  double _initialRotationAngle = 0.0;
  DateTime? _lastTapTime;
  
  bool _showShapeToolbar = false;
  bool _showTextToolbar = false; 
  bool _showPencilToolbar = false; 

  bool _showCustomToolsPanel = false;
  List<CustomToolGroup> _customToolGroups = [];
  CustomTool? _selectedCustomTool;

  // 🔽 API-Driven Page Management 🔽
  List<String> _pages = [];
  String _currentPage = ''; 
  Map<String, PageData> _pageDataMap = {};

  List<DrawingObject> get _drawingObjects => _pageDataMap[_currentPage]?.objects ?? [];
  set _drawingObjects(List<DrawingObject> val) {
    if (_pageDataMap.containsKey(_currentPage)) {
      _pageDataMap[_currentPage]!.objects = val;
    }
  }
  List<List<DrawingObject>> get _undoStack => _pageDataMap[_currentPage]?.undoStack ?? [];
  List<List<DrawingObject>> get _redoStack => _pageDataMap[_currentPage]?.redoStack ?? [];

  List<ProjectTag> _availableTags = [];

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); 
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeCanvas();
  }

  void _toggleNativeFullscreen() {
    // Check if the browser is currently in fullscreen mode
    if (html.document.fullscreenElement != null) {
      // Exit fullscreen
      html.document.exitFullscreen();
      setState(() => _isFullScreen = false);
    } else {
      // Request full screen for the entire app body
      html.document.documentElement?.requestFullscreen();
      setState(() => _isFullScreen = true);
    }
  }

  Future<ui.Image> _decodeBase64Image(String base64Str) async {
    String cleanBase64 = base64Str.contains(',') ? base64Str.split(',').last : base64Str;
    final Uint8List bytes = base64Decode(cleanBase64);
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

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
    } catch (e) {
      debugPrint("Error fetching tags: $e");
    }
  }

  Future<void> _initializeCanvas() async {
    setState(() => _isLoadingDocument = true);
    
    await _fetchAvailableTags(); 
    await _fetchCustomTools(); 
    
    // 🚀 SECURE UPLOADED IMAGE ANNOTATION MODE 🚀
    if (widget.annotateImageKey != null) {
      _pages = ['Attached Image'];
      _currentPage = 'Attached Image';
      
      try {
        // ==========================================
        // 1. FETCH SECURE IMAGE BACKGROUND
        // ==========================================
        final imageResponse = await _apiService.get('/customTool/tool/Image?key=${widget.annotateImageKey}');
        
        if (imageResponse.statusCode == 200) {
          final jsonResp = jsonDecode(imageResponse.body);
          if (jsonResp['success'] == true && jsonResp['data'] != null) {
            String b64 = jsonResp['data'];
            // Strip data URI prefix if it exists
            if (b64.contains(',')) b64 = b64.split(',').last;
            
            _pageDataMap = {
              'Attached Image': PageData(
                 pageId: widget.annotateImageKey!,
                 backgroundImageBytes: base64Decode(b64), 
              )
            };
          }
        }

        // ==========================================
        // 2. FETCH SAVED ANNOTATIONS FOR THIS IMAGE
        // ==========================================
        final jsonKey = Uri.encodeComponent('${widget.annotateImageKey}/image.json');
        final annResponse = await _apiService.get('/canvas/imageDataFromS3?imageJsonUrl=$jsonKey');
        
        if (annResponse.statusCode == 200) {
           final annData = jsonDecode(annResponse.body);
           
           if (annData['success'] == true && annData['data'] != null && annData['data'].isNotEmpty) {
             List<DrawingObject> loadedObjects = [];
             
             // 🚀 Extract the nested 'items' array from the first object in 'data' 🚀
             final List items = annData['data'][0]['items'] ?? [];
             
             for (var item in items) {
                DrawingType parsedType = _parseDrawingType(item['type']);
                
                // Re-link custom tools if applicable
                String? savedToolId = item['toolId'];
                ui.Image? decodedToolImg;
                String? toolBase64;
                if (parsedType == DrawingType.customTool && savedToolId != null) {
                  for (var group in _customToolGroups) {
                    try {
                      final matchedTool = group.tools.firstWhere((t) => t.toolId == savedToolId);
                      decodedToolImg = matchedTool.decodedImage;
                      toolBase64 = matchedTool.base64ImageUrl;
                      break;
                    } catch(e) {} 
                  }
                }

                loadedObjects.add(DrawingObject(
                  type: parsedType,
                  toolId: savedToolId,
                  customImage: decodedToolImg,
                  base64Image: toolBase64,
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
             
             setState(() {
               _pageDataMap['Attached Image']?.objects = loadedObjects;
             });
           }
        }
      } catch (e) {
        debugPrint("Failed to load secure image or annotations: $e");
      }
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

  // ==========================================
  // API 1: Gets the list of pages and their unique IDs
  // ==========================================
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
          // Initialize with the ID, but keep the image bytes null for now!
          _pageDataMap[pageName] = PageData(pageId: pageId); 
        }

        // Set the active page based on the URL parameter (e.g., ?page=1)
        if (_pages.isNotEmpty) {
          String targetPage = 'Page ${widget.page}';
          _currentPage = _pages.contains(targetPage) ? targetPage : _pages.first;
        }
      }
    } catch (e) {
      debugPrint("Error loading page list: $e");
    }
  }

  // ==========================================
  // API 2: Gets the Base64 image using the specific page ID
  // ==========================================
  Future<void> _fetchPageImage(String pageName) async {
    final pageData = _pageDataMap[pageName];
    
    // If the page doesn't exist or we already downloaded the image, skip the API call!
    if (pageData == null || pageData.backgroundImageBytes != null) return;

    setState(() => _isPageLoading = true);
    
    try {
      // Pass the specific page ID we saved from API 1
      final response = await _apiService.get('/templateDocumentPage/pdf/${pageData.pageId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final String base64String = responseData['data']['image'] ?? '';
        
        if (base64String.isNotEmpty) {
          // Decode the string and save it to the map
          pageData.backgroundImageBytes = base64Decode(base64String.replaceAll('\n', ''));
        }
      }
    } catch (e) {
      debugPrint("Error loading page image: $e");
    } finally {
      setState(() => _isPageLoading = false);
    }
  }
  
  // ==========================================
  // API 3: GET SAVED ANNOTATIONS
  // ==========================================
  Future<void> _fetchSavedAnnotations(String pageName) async {
    final pageData = _pageDataMap[pageName];
    if (pageData == null || pageData.hasLoadedAnnotations) return;

    try {
      final String url = '/canvas/jsonDataFromS3?project_id=${widget.projectId}&page_name=${Uri.encodeComponent(pageName)}&template_document_id=${widget.documentId}&template_document_page_id=${pageData.pageId}&inspection_id=${widget.inspectionId}';
      
      final response = await _apiService.get(url);
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        final List dataList = responseData['data'];
        
        final pageJson = dataList.firstWhere(
          (p) => p['page_name'] == pageName, 
          orElse: () => null
        );

        if (pageJson != null && pageJson['items'] != null) {
          List<DrawingObject> loadedObjects = [];
          
          for (var item in pageJson['items']) {
            double startX = (item['start']['dx'] ?? 0.0) * 816.0;
            double startY = (item['start']['dy'] ?? 0.0) * 1056.0;
            double endX = (item['end']['dx'] ?? 0.0) * 816.0;
            double endY = (item['end']['dy'] ?? 0.0) * 1056.0;

            DrawingType parsedType = _parseDrawingType(item['type']);

            loadedObjects.add(DrawingObject(
              type: parsedType,
              start: Offset(startX, startY),
              end: Offset(endX, endY),
              strokeWidth: (item['strokeWidth'] ?? 2).toDouble(),
              text: item['text']?.isEmpty == true ? null : item['text'],
              description: item['description'],
              tagIds: List<String>.from(item['tagIds'] ?? []),
              imageUrls: List<String>.from(item['imageUrl'] ?? []),
              
              // 🌟 RESTORE THE UI PROPERTIES (With Fallbacks!) 🌟
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
              
              // Map points array back to 816x1056 scaling
              points: item['points'] != null 
                  ? (item['points'] as List).map((p) => Offset((p['dx'] ?? 0.0) * 816.0, (p['dy'] ?? 0.0) * 1056.0)).toList() 
                  : null,
            ));
          }
          
          setState(() {
            pageData.objects = loadedObjects;
          });
        }
      }
      
      pageData.hasLoadedAnnotations = true;
      
    } catch (e) {
      debugPrint("Error loading saved annotations: $e");
    }
  }
  
  // ==========================================
  // API 4: SAVE ANNOTATIONS TO S3
  // ==========================================
  Future<void> _saveAnnotations() async {
    setState(() => _isSaving = true);
    
    try {
      final pageData = _pageDataMap[_currentPage];
      if (pageData == null) return;

      List<Map<String, dynamic>> itemsList = [];

      for (var obj in pageData.objects) {
        // Pack ALL properties into the JSON
        Map<String, dynamic> item = {
          "type": _getDrawingTypeString(obj.type),
          "start": {"dx": obj.start.dx / 816.0, "dy": obj.start.dy / 1056.0},
          "end": {"dx": obj.end.dx / 816.0, "dy": obj.end.dy / 1056.0},
          
          // 🚀 ADDED FOR CUSTOM TOOLS 🚀
          if (obj.type == DrawingType.customTool) "toolId": obj.toolId, 
          
          "text": obj.text ?? "",
          "description": obj.description ?? "",
          "strokeWidth": obj.strokeWidth,
          "tagIds": obj.tagIds ?? [],
          "imageUrl": obj.imageUrls ?? [],
          
          // 🌟 THE NEW UI PROPERTIES 🌟
          "color": obj.color.value,             // Saves Color as an integer
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

        // Handle arrays of points (for Pen, Pencil, and Callouts)
        if (obj.points != null && obj.points!.isNotEmpty) {
          item["points"] = obj.points!.map((p) => {
            "dx": p.dx / 816.0,
            "dy": p.dy / 1056.0
          }).toList();
        }

        itemsList.add(item);
      }

      // ==========================================
      // 🚀 NEW: IMAGE ANNOTATION SAVE LOGIC 🚀
      // ==========================================
      if (widget.annotateImageKey != null) {
        List<Map<String, dynamic>> wrapperArray = [
          {
            "page_name": "Image Preview",
            "sort_order": 0,
            "items": itemsList
          }
        ];

        Map<String, dynamic> payload = {
          "imageS3": widget.annotateImageKey,
          "imageJsonData": jsonEncode(wrapperArray) // Stringified wrapper
        };

        final response = await _apiService.post('/canvas/image/jsonData', payload);
        
        // Note: Assuming your _apiService handles the jsonEncode of the body internally
        final resData = jsonDecode(response.body);

        if (resData['success'] == true) {
          if (mounted) {
            ToastService.show(context, 
              message: "Image Annotations saved successfully!", 
              type: ToastType.success
            );
          }
        } else {
          throw Exception(resData['message'] ?? 'Failed to save image annotations');
        }
      } 
      // ==========================================
      // 🚀 NORMAL PDF SAVE LOGIC 🚀
      // ==========================================
      else {
        List<Map<String, dynamic>> canvasDataObj = [
          {
            "page_name": _currentPage,
            "sort_order": _pages.indexOf(_currentPage), 
            "items": itemsList
          }
        ];

        String canvasDataString = jsonEncode(canvasDataObj);

        Map<String, dynamic> payload = {
          "project_id": widget.projectId,
          "page_name": _currentPage,
          "canvas_data": canvasDataString,
          "template_document_id": widget.documentId,
          "template_document_page_id": pageData.pageId,
          "inspection_id": widget.inspectionId
        };

        final response = await _apiService.post('/canvas/json/s3', payload);
        final resData = jsonDecode(response.body);

        if (resData['success'] == true) {
          if (mounted) {
            ToastService.show(context, 
              message: "Annotations saved successfully!", 
              type: ToastType.success
            );
          }
        } else {
          throw Exception(resData['message'] ?? 'Failed to save');
        }
      }

    } catch (e) {
      debugPrint("Error saving annotations: $e");
      if (mounted) {
        ToastService.show(context, 
          message: "Error saving annotations.", 
          type: ToastType.error
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==========================================
  // API 5: GET PRESIGNED URL & UPLOAD TO S3
  // ==========================================
  Future<void> _uploadImageForObject(String fileName, Uint8List bytes) async {
    try {
      // 1. Get the Presigned URL
      final payload = {
        "file": fileName,
        "project_id": widget.projectId,
        "inspection_id": widget.inspectionId
      };
      
      final response = await _apiService.post('/customTool/tool/Image/presignedUrl', payload);
      final responseData = jsonDecode(response.body);
      
      if (responseData['signedUrl'] != null && responseData['key'] != null) {
        final String signedUrl = responseData['signedUrl'];
        final String s3Key = responseData['key'];
        
        // 2. Upload the raw file bytes directly to AWS S3
        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          body: bytes,
        );
        
        if (uploadResponse.statusCode == 200) {
           // 3. Success! Attach the key to the currently selected object
           setState((){
              if (_activeObject != null) {
                _activeObject!.imageUrls ??= [];
                _activeObject!.imageUrls!.add(s3Key);
                // (Optional: _saveSnapshot() here if you want undo/redo to track image uploads)
              }
           });
        } else {
           throw Exception("S3 upload failed with status: ${uploadResponse.statusCode}");
        }
      }
    } catch(e) {
      debugPrint("Image upload failed: $e");
      if (mounted) {
        ToastService.show(context, 
          message: "Failed to upload image.", 
          type: ToastType.error
        );
      }
    }
  }

  // ==========================================
  // API 6: DELETE IMAGE FROM S3
  // ==========================================
  Future<void> _deleteImageForObject(String s3Key) async {
    try {
      // Your API structure: /customTool/tool/Image/{S3_KEY}
      final response = await _apiService.delete('/customTool/tool/Image/$s3Key');
      
      // If we are getting a 200/204, it was successful
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          if (_activeObject != null && _activeObject!.imageUrls != null) {
            _activeObject!.imageUrls!.remove(s3Key);
          }
        });
      } else {
        throw Exception("Delete failed with status: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Image deletion failed: $e");
      if (mounted) {
        ToastService.show(context, 
          message: "Failed to delete image.", 
          type: ToastType.error
          );
      }
    }
  }

  // ==========================================
  // API 7: GET CUSTOM TOOLS
  // ==========================================
  Future<void> _fetchCustomTools() async {
    try {
      final response = await _apiService.get('/customTool/project/${widget.projectId}');
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        List<CustomToolGroup> loadedGroups = [];
        
        for (var groupJson in responseData['data']) {
          List<CustomTool> tools = [];
          // Note: using 'toolds' exactly as spelled in your API response!
          if (groupJson['toolds'] != null) {
            for (var toolJson in groupJson['toolds']) {
              // Decode the base64 into a native ui.Image immediately for smooth drawing
              ui.Image decodedImg = await _decodeBase64Image(toolJson['base64ImageUrl']);
              
              tools.add(CustomTool(
                toolId: toolJson['toolId'],
                toolName: toolJson['toolName'],
                base64ImageUrl: toolJson['base64ImageUrl'],
                tagIds: List<String>.from(toolJson['tagIds'] ?? []),
                decodedImage: decodedImg,
              ));
            }
          }
          loadedGroups.add(CustomToolGroup(toolGroup: groupJson['toolGroup'], tools: tools));
        }
        
        setState(() => _customToolGroups = loadedGroups);
      }
    } catch (e) {
      debugPrint("Error fetching custom tools: $e");
    }
  }

  // Tiny helper to map API strings to our Enum
  DrawingType _parseDrawingType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'rectangle': return DrawingType.rect;
      case 'circle': return DrawingType.circle;
      case 'line': return DrawingType.line;
      case 'arrow': return DrawingType.arrow;
      case 'text': return DrawingType.text;
      case 'pencil': return DrawingType.pencil;
      case 'pen': return DrawingType.pen;
      case 'customtool': return DrawingType.customTool;
      default: return DrawingType.rect;
    }
  }
  
  // Converts our enum back to the API's string format
  String _getDrawingTypeString(DrawingType type) {
    switch (type) {
      case DrawingType.rect: return 'rectangle';
      case DrawingType.circle: return 'circle';
      case DrawingType.line: return 'line';
      case DrawingType.arrow: return 'arrow';
      case DrawingType.text: return 'text';
      case DrawingType.pencil: return 'pencil';
      case DrawingType.pen: return 'pen';
      case DrawingType.pin: return 'pin';
      case DrawingType.customTool: return 'customTool';
    }
  }

  // ==========================================
  // DRAWING LOGIC (Unchanged)
  // ==========================================
  
  Future<void> _showTextDialog({required Offset position, DrawingObject? existingObject, bool isCallout = false}) async {
    final TextEditingController controller = TextEditingController(text: existingObject?.text ?? "");
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingObject == null ? "Enter Text" : "Edit Text"),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: "Type your text here...",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _saveSnapshot();
                setState(() {
                  final textPainter = TextPainter(
                    text: TextSpan(text: controller.text, style: TextStyle(fontSize: _textStrokeWidth * 10)),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: 500);

                  final calculatedSize = Offset(textPainter.width + 20, textPainter.height + 20);

                  Color initialFill = _textFillColor;
                  Color initialBorder = _textBorderColor;
                  Color initialText = _textColor;
                  
                  if (isCallout) {
                    if (initialFill == Colors.transparent) initialFill = const Color(0xFF7F4A46);
                    if (initialBorder == Colors.transparent) initialBorder = Colors.redAccent;
                    if (initialText == Colors.black) initialText = Colors.white;
                  }

                  if (existingObject != null) {
                    existingObject.text = controller.text;
                    existingObject.end = existingObject.start + calculatedSize;
                  } else {
                    final textObj = DrawingObject(
                      start: position, end: position + calculatedSize, type: DrawingType.text, text: controller.text,
                      color: initialText, fillColor: initialFill, borderColor: initialBorder, opacity: _textOpacity,
                      isSelected: true, strokeWidth: _textStrokeWidth, fontSize: _textSize,
                      isBold: _textIsBold, isItalic: _textIsItalic, isUnderline: _textIsUnderline, isStrikethrough: _textIsStrikethrough,
                      isCallout: isCallout, 
                      points: isCallout ? [position + Offset(calculatedSize.dx / 2, calculatedSize.dy + 30), position + Offset(calculatedSize.dx / 2 + 40, calculatedSize.dy + 70)] : null,
                    );
                    for (var obj in _drawingObjects) obj.isSelected = false;
                    _drawingObjects.add(textObj);
                    _activeObject = textObj;
                    _selectedTool = 'Select';
                  }
                });
              }
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _switchPage(String newPage) async {
    setState(() {
      for (var obj in _drawingObjects) obj.isSelected = false;
      _activeObject = null;
      _activeHandle = ResizeHandle.none;
      _currentPreview = null; 
      _currentPage = newPage;
      _selectedTool = 'Select'; 
    });
    
    // Fetch the image
    await _fetchPageImage(newPage);
    // 🔽 FETCH ANNOTATIONS ON PAGE SWITCH
    await _fetchSavedAnnotations(newPage); 
  }

  void _saveSnapshot() {
    _undoStack.add(_drawingObjects.map((e) => e.copy()).toList());
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear(); 
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        _redoStack.add(_drawingObjects.map((e) => e.copy()).toList());
        _drawingObjects = _undoStack.removeLast();
        _activeObject = null;
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        _undoStack.add(_drawingObjects.map((e) => e.copy()).toList());
        _drawingObjects = _redoStack.removeLast();
        _activeObject = null;
      });
    }
  }

  void _deleteSelected() {
    if (_drawingObjects.any((o) => o.isSelected)) {
      _saveSnapshot();
      setState(() {
        _drawingObjects.removeWhere((o) => o.isSelected);
        _activeObject = null;
      });
    }
  }

  void _copySelected() {
    if (_activeObject != null) {
      setState(() => _clipboard = _activeObject!.copy());
    }
  }

  void _pasteFromClipboard() {
    if (_clipboard != null) {
      _saveSnapshot(); 
      setState(() {
        for (var obj in _drawingObjects) obj.isSelected = false;
        DrawingObject pastedObj = _clipboard!.copy();
        const Offset shift = Offset(20, 20);
        pastedObj.start += shift;
        pastedObj.end += shift;
        
        if (pastedObj.points != null) pastedObj.points = pastedObj.points!.map((p) => p + shift).toList();
        pastedObj.isSelected = true; 
        _drawingObjects.add(pastedObj);
        _activeObject = pastedObj;
        _selectedTool = 'Select'; 
      });
    }
  }

  Offset _toLocalSpace(Offset point, DrawingObject obj) {
    final double cos = math.cos(-obj.rotation);
    final double sin = math.sin(-obj.rotation);
    final double dx = point.dx - obj.center.dx;
    final double dy = point.dy - obj.center.dy;
    return Offset(cos * dx - sin * dy + obj.center.dx, sin * dx + cos * dy + obj.center.dy);
  }

  MouseCursor _getCursor(ResizeHandle handle) {
    if (_selectedTool == 'Eraser') return SystemMouseCursors.none;
    if (_selectedTool == 'Text') return SystemMouseCursors.text;
    switch (handle) {
      case ResizeHandle.topLeft: case ResizeHandle.bottomRight: return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeHandle.topRight: case ResizeHandle.bottomLeft: return SystemMouseCursors.resizeUpRightDownLeft;
      case ResizeHandle.topCenter: case ResizeHandle.bottomCenter: return SystemMouseCursors.resizeUpDown;
      case ResizeHandle.centerLeft: case ResizeHandle.centerRight: return SystemMouseCursors.resizeLeftRight;
      case ResizeHandle.rotation: return SystemMouseCursors.grab;
      case ResizeHandle.body: return SystemMouseCursors.move;
      case ResizeHandle.calloutKnee: case ResizeHandle.calloutTip: return SystemMouseCursors.move;
      default: return SystemMouseCursors.basic;
    }
  }

  ResizeHandle _getHitHandle(Offset p, DrawingObject obj) {
    const double hSize = 25.0; 
    final localP = _toLocalSpace(p, obj);
    final r = obj.rect;

    if (obj.isSelected) {
      if (obj.type == DrawingType.text && obj.isCallout && obj.points != null && obj.points!.length >= 2) {
        if ((localP - obj.points![0]).distance < hSize) return ResizeHandle.calloutKnee;
        if ((localP - obj.points![1]).distance < hSize) return ResizeHandle.calloutTip;
      }
      Offset rotPos = Offset(r.topCenter.dx, r.topCenter.dy - 40);
      if ((localP - rotPos).distance < hSize) return ResizeHandle.rotation;

      if (obj.type != DrawingType.pencil && obj.type != DrawingType.pen) {
        if ((localP - r.topLeft).distance < hSize) return ResizeHandle.topLeft;
        if ((localP - r.topCenter).distance < hSize) return ResizeHandle.topCenter;
        if ((localP - r.topRight).distance < hSize) return ResizeHandle.topRight;
        if ((localP - r.centerLeft).distance < hSize) return ResizeHandle.centerLeft;
        if ((localP - r.centerRight).distance < hSize) return ResizeHandle.centerRight;
        if ((localP - r.bottomLeft).distance < hSize) return ResizeHandle.bottomLeft;
        if ((localP - r.bottomCenter).distance < hSize) return ResizeHandle.bottomCenter;
        if ((localP - r.bottomRight).distance < hSize) return ResizeHandle.bottomRight;
      }
    }
    
    if (obj.type == DrawingType.line) {
      if (_distToSegment(localP, obj.start, obj.end) < 15) return ResizeHandle.body;
    } else if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null) {
      for (int i = 0; i < obj.points!.length - 1; i++) {
        if (_distToSegment(localP, obj.points![i], obj.points![i+1]) < 15) return ResizeHandle.body;
      }
      if (obj.fillColor != Colors.transparent && r.contains(localP)) return ResizeHandle.body;
    } else {
      if (r.inflate(5).contains(localP)) return ResizeHandle.body;
    }
    return ResizeHandle.none;
  }

  void _handlePointerDown(PointerDownEvent details) {
    if (!_canvasFocusNode.hasFocus) {
      _canvasFocusNode.requestFocus();
    }
    
    final pos = _clampToCanvas(details.localPosition); 
    final now = DateTime.now();

    setState(() {
      // 🚀 Intercept the Custom Tool click 🚀
      if (_selectedTool == 'CustomTool') {
        if (_selectedCustomTool != null) {
          
          final initialSize = const Offset(100, 100); 
          
          final toolObj = DrawingObject(
            start: pos, 
            end: pos + initialSize, 
            type: DrawingType.customTool,
            base64Image: _selectedCustomTool!.base64ImageUrl,
            customImage: _selectedCustomTool!.decodedImage,
            tagIds: List.from(_selectedCustomTool!.tagIds),
            isSelected: true,
          );
          
          setState(() {
            for (var obj in _drawingObjects) { obj.isSelected = false; }
            _drawingObjects.add(toolObj);
            _activeObject = toolObj;
            _activeHandle = ResizeHandle.bottomRight; 
            
            // 🔽 THE NEW UX MAGIC: Instantly revert to Select Mode 🔽
            _selectedTool = 'Select';
            _selectedCustomTool = null; // Disarms the custom stamp
          });
        } else {
          ToastService.show(context, 
            message: "Please select a tool from the left panel first!", 
            type: ToastType.warning
          );
        }
        return; 
      }

      if (_selectedTool == 'Text' || _selectedTool == 'Callout') {
        _showTextDialog(position: pos, isCallout: _selectedTool == 'Callout');
      } else if (_selectedTool == 'Eraser') {
        _saveSnapshot();
        _drawingObjects.removeWhere((obj) => _getHitHandle(pos, obj) != ResizeHandle.none);
      } else if (_selectedTool == 'Pen') {
        if (_currentPreview == null) {
          _currentPreview = DrawingObject(
            start: pos, end: pos, type: DrawingType.pen, points: [pos, pos], 
            strokeWidth: _pencilStrokeWidth, color: _pencilColor, fillColor: _penFillColor, opacity: _pencilOpacity, 
          );
        } else {
          if (_currentPreview!.points!.length > 2 && (pos - _currentPreview!.points!.first).distance < 15) {
            _currentPreview!.points!.last = _currentPreview!.points!.first;
            _finalizeCurrentPreview();
          } else {
            _currentPreview!.points!.last = pos;
            _currentPreview!.points!.add(pos);
          }
        }
      } else if (_selectedTool != 'Select') {
        _saveSnapshot();
        for (var obj in _drawingObjects) obj.isSelected = false;
        
        DrawingType type = (_selectedTool == 'Pencil') ? DrawingType.pencil : 
                           (_selectedTool == 'Rect') ? DrawingType.rect : 
                           (_selectedTool == 'Circle') ? DrawingType.circle : 
                           (_selectedTool == 'Arrow') ? DrawingType.arrow : 
                           (_selectedTool == 'Pin') ? DrawingType.pin : DrawingType.line;
        
        List<Offset>? pts = (type == DrawingType.pencil) ? [pos] : null;
        
        Color objColor = Colors.black; Color objFill = Colors.transparent; double objOpacity = 1.0; double objStroke = 2.0; 

        if (type == DrawingType.pencil) {
          objColor = _pencilColor; objFill = _penFillColor; objOpacity = _pencilOpacity; objStroke = _pencilStrokeWidth; 
        } else if (type == DrawingType.pin) {
          objColor = Colors.red[800]!; objFill = Colors.red; objOpacity = 1.0; objStroke = 2.0;
        } else if (type == DrawingType.line || type == DrawingType.arrow) {
          objColor = _shapeLineColor; objOpacity = _shapeOpacity; objStroke = _shapeStrokeWidth;  
        } else if (type == DrawingType.rect || type == DrawingType.circle) { 
          objColor = _shapeBorderColor; objFill = _shapeFillColor; objOpacity = _shapeOpacity; objStroke = _shapeStrokeWidth;  
        }

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type, points: pts, strokeWidth: objStroke, color: objColor, fillColor: objFill, opacity: objOpacity,
        );
      } else if (_selectedTool == 'CustomTool' && _selectedCustomTool != null) {
        final toolObj = DrawingObject(
          start: pos, end: pos, // Starts as a dot, resizes as they drag
          type: DrawingType.customTool,
          base64Image: _selectedCustomTool!.base64ImageUrl,
          customImage: _selectedCustomTool!.decodedImage,
          tagIds: List.from(_selectedCustomTool!.tagIds), // Inherit tool tags!
          isSelected: true,
        );
        
        for (var obj in _drawingObjects) { obj.isSelected = false; }
        setState(() {
          _drawingObjects.add(toolObj);
          _activeObject = toolObj;
          _activeHandle = ResizeHandle.bottomRight; // Auto-grab corner to resize instantly
        });
      } else {
        _activeHandle = ResizeHandle.none;
        DrawingObject? hitObj; ResizeHandle hitHandle = ResizeHandle.none;

        for (var obj in _drawingObjects.reversed) {
          hitHandle = _getHitHandle(pos, obj);
          if (hitHandle != ResizeHandle.none) { hitObj = obj; break; }
        }

        if (hitObj != null) {
          if (hitObj.type == DrawingType.text && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
            _showTextDialog(position: pos, existingObject: hitObj); return;
          }
          _lastTapTime = now;
          if (!hitObj.isSelected) _saveSnapshot();
          for (var obj in _drawingObjects) obj.isSelected = false;
          hitObj.isSelected = true;
          _activeObject = hitObj; _activeHandle = hitHandle;
          if (hitHandle == ResizeHandle.rotation) _initialRotationAngle = math.atan2(pos.dy - hitObj.center.dy, pos.dx - hitObj.center.dx) - hitObj.rotation;
          else if (hitHandle == ResizeHandle.body) _dragOffset = pos - hitObj.start;
        } else {
          for (var obj in _drawingObjects) obj.isSelected = false;
          _activeObject = null;
        }
      }
    });
  }
  
  void _handlePointerMove(PointerMoveEvent details, BoxConstraints constraints) {
    final pos = _clampToCanvas(details.localPosition);
    setState(() {
      if (_selectedTool == 'Eraser') {
        _drawingObjects.removeWhere((obj) => _getHitHandle(pos, obj) != ResizeHandle.none);
      } else if (_currentPreview != null) {
        if (_currentPreview!.type == DrawingType.pencil) {
          _currentPreview!.points!.add(pos);
        } else {
          _currentPreview!.end = pos;
        }
      } else if (_activeObject != null && _activeHandle != ResizeHandle.none) {
        if (_activeHandle == ResizeHandle.rotation) {
          _activeObject!.rotation = math.atan2(pos.dy - _activeObject!.center.dy, pos.dx - _activeObject!.center.dx) - _initialRotationAngle;
        } else if (_activeHandle == ResizeHandle.calloutKnee) {
          _activeObject!.points![0] = pos; 
        } else if (_activeHandle == ResizeHandle.calloutTip) {
          _activeObject!.points![1] = pos; 
        } else if (_activeHandle == ResizeHandle.body) {
          Offset delta = _activeObject!.end - _activeObject!.start;
          Offset moveDelta = (pos - _dragOffset) - _activeObject!.start;
          _activeObject!.start = pos - _dragOffset;
          _activeObject!.end = _activeObject!.start + delta;
          
          if (_activeObject!.type == DrawingType.pencil || _activeObject!.type == DrawingType.pen) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + moveDelta).toList();
          }
          if (_activeObject!.type == DrawingType.text && _activeObject!.isCallout && _activeObject!.points != null) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + moveDelta).toList();
          }
        } else {
          final localP = _toLocalSpace(pos, _activeObject!);
          Rect r = _activeObject!.rect;
          double left = r.left, top = r.top, right = r.right, bottom = r.bottom;
          switch (_activeHandle) {
            case ResizeHandle.topLeft: left = localP.dx; top = localP.dy; break;
            case ResizeHandle.topCenter: top = localP.dy; break;
            case ResizeHandle.topRight: right = localP.dx; top = localP.dy; break;
            case ResizeHandle.centerLeft: left = localP.dx; break;
            case ResizeHandle.centerRight: right = localP.dx; break;
            case ResizeHandle.bottomLeft: left = localP.dx; bottom = localP.dy; break;
            case ResizeHandle.bottomCenter: bottom = localP.dy; break;
            case ResizeHandle.bottomRight: right = localP.dx; bottom = localP.dy; break;
            default: break;
          }
          _activeObject!.start = Offset(left, top);
          _activeObject!.end = Offset(right, bottom);
        }
      }
    });
  }

  void _handlePointerUp(PointerUpEvent details) {
    setState(() {
      if (_currentPreview != null && _currentPreview!.type != DrawingType.pen) {
        for (var obj in _drawingObjects) obj.isSelected = false;
        _currentPreview!.isSelected = true;
        _drawingObjects.add(_currentPreview!);
        _activeObject = _currentPreview;
        _selectedTool = 'Select'; 
        _currentPreview = null;
      }
      _activeHandle = ResizeHandle.none;
    });
  }

  Offset _clampToCanvas(Offset pos) {
    return Offset(
      pos.dx.clamp(0.0, 816.0),
      pos.dy.clamp(0.0, 1056.0),
    );
  }

  double _distToSegment(Offset p, Offset v, Offset w) {
    double l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distance;
    double t = ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy))).distance;
  }

  void _finalizeCurrentPreview() {
    if (_currentPreview != null) {
      _saveSnapshot();
      for (var obj in _drawingObjects) obj.isSelected = false;
      _currentPreview!.isSelected = true;

      if (_currentPreview!.type == DrawingType.pen && _currentPreview!.points!.length < 3) {
        _currentPreview = null;
        return;
      }
      if (_currentPreview!.type == DrawingType.pen) _currentPreview!.points!.removeLast();

      _drawingObjects.add(_currentPreview!);
      _activeObject = _currentPreview;
      _selectedTool = 'Select';
      _currentPreview = null;
    }
  }

  void _showColorPicker(int mode) {
    _saveSnapshot(); 
    final List<Color> pickerPresets = [
      const Color(0xFFFF5252), const Color(0xFFFF9800), const Color(0xFFFFEB3B), const Color(0xFFCDDC39), 
      const Color(0xFF4CAF50), const Color(0xFF009688), const Color(0xFF00BCD4), const Color(0xFF03A9F4), 
      const Color(0xFF2196F3), const Color(0xFF3F51B5), const Color(0xFF9C27B0), const Color(0xFFE91E63), 
      const Color(0xFF795548), const Color(0xFF9E9E9E), const Color(0xFF000000), const Color(0xFFFFFFFF),
    ];

    Color currentColor;
    double currentOpacity = 1.0;

    switch(mode) {
      case 0: currentColor = _pencilColor; currentOpacity = _pencilOpacity; break;
      case 1: currentColor = _shapeLineColor; currentOpacity = _shapeOpacity; break;
      case 2: currentColor = _shapeBorderColor; currentOpacity = _shapeOpacity; break;
      case 3: currentColor = _shapeFillColor; currentOpacity = _shapeOpacity; break;
      case 4: currentColor = _textColor; currentOpacity = _textOpacity; break;
      case 5: currentColor = _textBorderColor; currentOpacity = _textOpacity; break;
      case 6: currentColor = _textFillColor; currentOpacity = _textOpacity; break;
      case 7: currentColor = _penFillColor; currentOpacity = _pencilOpacity; break;
      default: currentColor = Colors.black;
    }
    
    HSVColor hsvColor = HSVColor.fromColor(currentColor == Colors.transparent ? Colors.red : currentColor);
    double localOpacity = currentOpacity; 

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateColor(Color newColor) {
              setDialogState(() => hsvColor = HSVColor.fromColor(newColor));
              setState(() {
                if (mode == 0) { _pencilColor = newColor; if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) _activeObject!.color = newColor; } 
                else if (mode == 1) { _shapeLineColor = newColor; if (_activeObject?.type == DrawingType.line || _activeObject?.type == DrawingType.arrow) _activeObject!.color = newColor; } 
                else if (mode == 2) { _shapeBorderColor = newColor; if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) _activeObject!.color = newColor; } 
                else if (mode == 3) { _shapeFillColor = newColor; if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) _activeObject!.fillColor = newColor; } 
                else if (mode == 4) { _textColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.color = newColor; } 
                else if (mode == 5) { _textBorderColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.borderColor = newColor; } 
                else if (mode == 6) { _textFillColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.fillColor = newColor; } 
                else if (mode == 7) { _penFillColor = newColor; if (_activeObject?.type == DrawingType.pen || _activeObject?.type == DrawingType.pencil) _activeObject!.fillColor = newColor; }
              });
            }

            String colorToHex(Color c) => c == Colors.transparent ? "NONE" : '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
            const double squareWidth = 240.0; const double squareHeight = 200.0;
            bool showOpacity = (mode == 3 || mode == 6 || mode == 7); 
            bool showNone = (mode == 2 || mode == 3 || mode == 5 || mode == 6 || mode == 7); 

            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: showOpacity ? hsvColor.toColor().withOpacity(localOpacity) : hsvColor.toColor(), shape: BoxShape.circle, border: Border.all(color: Colors.grey.withOpacity(0.3)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                        child: hsvColor.toColor() == Colors.transparent ? const Icon(Icons.block, color: Colors.red) : null,
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Selected Color", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          Text(colorToHex(hsvColor.toColor()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'monospace')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onPanDown: (details) {
                      double s = (details.localPosition.dx / squareWidth).clamp(0.0, 1.0);
                      double v = (1.0 - (details.localPosition.dy / squareHeight)).clamp(0.0, 1.0);
                      updateColor(hsvColor.withSaturation(s).withValue(v).toColor());
                    },
                    onPanUpdate: (details) {
                      double s = (details.localPosition.dx / squareWidth).clamp(0.0, 1.0);
                      double v = (1.0 - (details.localPosition.dy / squareHeight)).clamp(0.0, 1.0);
                      updateColor(hsvColor.withSaturation(s).withValue(v).toColor());
                    },
                    child: Stack(
                      children: [
                        Container(
                          width: squareWidth, height: squareHeight,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: [Colors.white, hsvColor.withSaturation(1).withValue(1).toColor()])),
                          child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                        ),
                        Positioned(
                          left: (hsvColor.saturation * squareWidth) - 8, top: ((1 - hsvColor.value) * squareHeight) - 8,
                          child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)])),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 240, height: 12,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: const LinearGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red])),
                    child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 12, activeTrackColor: Colors.transparent, inactiveTrackColor: Colors.transparent, thumbColor: Colors.white), child: Slider(value: hsvColor.hue, min: 0, max: 360, onChanged: (v) => updateColor(hsvColor.withHue(v).toColor()))),
                  ),
                  const SizedBox(height: 16),
                  if (showOpacity) ...[
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Opacity", style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)), Text("${(localOpacity * 100).toInt()}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 6),
                    Container(
                      width: 240, height: 12,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.withOpacity(0.3)), gradient: LinearGradient(colors: [Colors.transparent, hsvColor.toColor()])),
                      child: Slider(
                        value: localOpacity, min: 0.0, max: 1.0,
                        onChanged: (v) {
                          setDialogState(() => localOpacity = v);
                          setState(() { 
                            if (mode == 3) { _shapeOpacity = v; if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) _activeObject!.opacity = v; } 
                            else if (mode == 6) { _textOpacity = v; if (_activeObject?.type == DrawingType.text) _activeObject!.opacity = v; } 
                            else if (mode == 7) { _pencilOpacity = v; if (_activeObject?.type == DrawingType.pen || _activeObject?.type == DrawingType.pencil) _activeObject!.opacity = v; }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const Text("Preset Colors", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 260,
                    child: Wrap(
                      alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
                      children: [
                        if (showNone)
                          GestureDetector(onTap: () => updateColor(Colors.transparent), child: CircleAvatar(radius: 14, backgroundColor: Colors.grey[200], child: const Icon(Icons.block, size: 16, color: Colors.red))),
                        ...pickerPresets.map((color) => GestureDetector(
                          onTap: () => updateColor(color),
                          child: Container(width: 28, height: 28, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: hsvColor.toColor() == color ? Colors.blue : (color == Colors.white ? Colors.grey[300]! : Colors.transparent), width: 2))),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)))],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // UI BUILDING HELPERS
  // ==========================================

  Widget _buildTopNav(ThemeData theme) {
    return Container(
      height: 64, padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)))),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back), 
          onPressed: () => Navigator.of(context).pop()
        ), 
        const SizedBox(width: 15),
        Text("Canvas", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        _buildPageSelector(theme), 
        const SizedBox(width: 20), 

        if (_isSaving)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
          )
        else
          IconButton(
            tooltip: "Save Annotations",
            icon: const Icon(Icons.save_outlined),
            color: theme.colorScheme.primary,
            onPressed: _saveAnnotations,
          ),
        
        const SizedBox(width: 8),
        
        PopupMenuButton<String>(
          tooltip: "Export PDF",
          icon: const Icon(Icons.picture_as_pdf_outlined), 
          offset: const Offset(0, 45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) => exportCanvasToPdf(
            context: context, 
            exportAll: val == 'all', 
            pages: _pages, 
            currentPage: _currentPage, 
            pageDataMap: _pageDataMap
          ),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'current', child: ListTile(leading: Icon(Icons.insert_drive_file_outlined, size: 18), title: Text("Export Current Page"), dense: true)),
            const PopupMenuItem(value: 'all', child: ListTile(leading: Icon(Icons.copy_all_rounded, size: 18), title: Text("Export All Pages"), dense: true)),
          ],
        ),
      ]),
    );
  }

  bool _isShapeSelected(String tool) => ['Rect', 'Circle', 'Line', 'Arrow'].contains(tool);

  IconData _getShapeIcon(String tool) {
    switch (tool) {
      case 'Rect': return Icons.crop_square;
      case 'Circle': return Icons.panorama_fish_eye;
      case 'Line': return Icons.show_chart;
      case 'Arrow': return Icons.arrow_outward;
      default: return Icons.crop_square; 
    }
  }

  Widget _mainMenuToggle({required IconData icon, required String label, required bool isActive, required bool hasDropdown, required VoidCallback onTap, required ThemeData theme}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainer,
                  child: Icon(icon, color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, size: 16),
                ),
                if (hasDropdown) ...[
                  const SizedBox(width: 2), Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                ] else ...[
                  const SizedBox(width: 5), 
                ]
              ],
            ),
            const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _toolIcon(IconData icon, String label, ThemeData theme) {
    bool isActive = _selectedTool == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedTool = label),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: [
        CircleAvatar(radius: 18, backgroundColor: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainer, child: Icon(icon, color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, size: 16)),
        const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 9)),
      ])),
    );
  }

  Widget _colorButton(String label, Color color, int mode) {
    return GestureDetector(
      onTap: () => _showColorPicker(mode),
      child: Column(children: [
        CircleAvatar(radius: 16, backgroundColor: color == Colors.transparent ? Colors.grey[200] : color, child: color == Colors.transparent ? const Icon(Icons.block, size: 12, color: Colors.red) : null),
        const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8)),
      ]),
    );
  }

  Widget _formatToggle(IconData icon, bool isActive, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: isActive ? theme.colorScheme.primary.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, size: 18, color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface),
      ),
    );
  }

  Widget _buildTextSizeSlider(ThemeData theme) {
    return SizedBox(
      width: 160,
      child: Row(children: [
        const Text("Size: ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        SizedBox(width: 28, child: Text("${_textSize.toInt()}", style: theme.textTheme.labelSmall)),
        Expanded(child: Slider(value: _textSize, min: 10, max: 120, onChanged: (v) => setState(() { _textSize = v; if (_activeObject?.type == DrawingType.text) _activeObject!.fontSize = v; }))),
      ]),
    );
  }

  Widget _buildStrokeSlider(ThemeData theme, int mode) {
    double currentWidth;
    switch (mode) { case 0: currentWidth = _pencilStrokeWidth; break; case 1: currentWidth = _shapeStrokeWidth; break; case 2: currentWidth = _textStrokeWidth; break; default: currentWidth = 2.0; }
    return SizedBox(
      width: 170, 
      child: Row(children: [
        const Text("Border: ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        SizedBox(width: 28, child: Text("${currentWidth.toInt()}px", style: theme.textTheme.labelSmall)),
        Expanded(child: Slider(value: currentWidth, min: 1, max: 20, onChanged: (v) => setState(() {
          if (mode == 0) { _pencilStrokeWidth = v; if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) _activeObject!.strokeWidth = v; } 
          else if (mode == 1) { _shapeStrokeWidth = v; if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle || _activeObject?.type == DrawingType.line || _activeObject?.type == DrawingType.arrow) _activeObject!.strokeWidth = v; } 
          else if (mode == 2) { _textStrokeWidth = v; if (_activeObject?.type == DrawingType.text) _activeObject!.strokeWidth = v; }
        }))),
      ]),
    );
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

  Widget _utilityIcon(IconData icon, String msg, ThemeData theme, VoidCallback onTap, {bool isDestructive = false, bool isEnabled = true}) {
    return IconButton(onPressed: isEnabled ? onTap : null, icon: Icon(icon, color: isEnabled ? (isDestructive ? Colors.red : theme.colorScheme.onSurface) : theme.disabledColor));
  }

  Widget _vDiv(ThemeData theme) => VerticalDivider(width: 32, indent: 10, endIndent: 10, color: theme.colorScheme.outlineVariant);

  Widget _buildFloatingPencilMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DRAW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _toolIcon(Icons.edit, "Pencil", theme), _toolIcon(Icons.polyline, "Pen", theme), _vDiv(theme),
            const Text("PROPERTIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _colorButton("Color", _pencilColor, 0), const SizedBox(width: 12), _colorButton("Fill", _penFillColor, 7), _vDiv(theme), _buildStrokeSlider(theme, 0), 
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingTextMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("TOOLS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _toolIcon(Icons.title, "Text", theme), _toolIcon(Icons.chat_bubble_outline, "Callout", theme), _vDiv(theme),
            const Text("FORMAT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _formatToggle(Icons.format_bold, _textIsBold, () => setState(() { _textIsBold = !_textIsBold; if (_activeObject?.type == DrawingType.text) _activeObject!.isBold = _textIsBold; }), theme),
            _formatToggle(Icons.format_italic, _textIsItalic, () => setState(() { _textIsItalic = !_textIsItalic; if (_activeObject?.type == DrawingType.text) _activeObject!.isItalic = _textIsItalic; }), theme),
            _formatToggle(Icons.format_underlined, _textIsUnderline, () => setState(() { _textIsUnderline = !_textIsUnderline; if (_activeObject?.type == DrawingType.text) _activeObject!.isUnderline = _textIsUnderline; }), theme),
            _formatToggle(Icons.format_strikethrough, _textIsStrikethrough, () => setState(() { _textIsStrikethrough = !_textIsStrikethrough; if (_activeObject?.type == DrawingType.text) _activeObject!.isStrikethrough = _textIsStrikethrough; }), theme),
            _vDiv(theme), _buildTextSizeSlider(theme), _vDiv(theme),
            _colorButton("Text", _textColor, 4), const SizedBox(width: 12), _colorButton("Border", _textBorderColor, 5), const SizedBox(width: 12), _colorButton("Fill", _textFillColor, 6), _vDiv(theme), _buildStrokeSlider(theme, 2), 
          ],
        ),
      ),
    );
  }
  
  Widget _buildFloatingShapeMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("SHAPES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _toolIcon(Icons.crop_square, "Rect", theme), _toolIcon(Icons.panorama_fish_eye, "Circle", theme), _toolIcon(Icons.show_chart, "Line", theme), _toolIcon(Icons.arrow_outward, "Arrow", theme), _vDiv(theme),
            const Text("PROPERTIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _colorButton("Color", _shapeLineColor, 1), const SizedBox(width: 12), _colorButton("Border", _shapeBorderColor, 2), const SizedBox(width: 12), _colorButton("Fill", _shapeFillColor, 3), _vDiv(theme), _buildStrokeSlider(theme, 1), 
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthToolbar(ThemeData theme) {
    return Container(
      width: double.infinity, 
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          // 1. LEFT SIDE: Drawing Tools
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _mainMenuToggle(icon: Icons.near_me, label: "Select", isActive: _selectedTool == 'Select' && !_showPencilToolbar && !_showShapeToolbar && !_showTextToolbar, hasDropdown: false, theme: theme, onTap: () => setState(() { _selectedTool = 'Select'; _showPencilToolbar = false; _showShapeToolbar = false; _showTextToolbar = false; })),
                  _mainMenuToggle(icon: _selectedTool == 'Pen' ? Icons.polyline : Icons.edit, label: _selectedTool == 'Pen' ? "Pen" : "Pencil", isActive: _showPencilToolbar || _selectedTool == 'Pencil' || _selectedTool == 'Pen', hasDropdown: true, theme: theme, onTap: () => setState(() { _showPencilToolbar = !_showPencilToolbar; if (_showPencilToolbar) { _showShapeToolbar = false; _showTextToolbar = false; if (_selectedTool != 'Pencil' && _selectedTool != 'Pen') _selectedTool = 'Pencil'; } else { _selectedTool = 'Select'; } })),
                  _mainMenuToggle(icon: _getShapeIcon(_selectedTool), label: "Shapes", isActive: _showShapeToolbar || _isShapeSelected(_selectedTool), hasDropdown: true, theme: theme, onTap: () => setState(() { _showShapeToolbar = !_showShapeToolbar; if (_showShapeToolbar) { _showPencilToolbar = false; _showTextToolbar = false; if (!_isShapeSelected(_selectedTool)) _selectedTool = 'Rect'; } else { _selectedTool = 'Select'; } })),
                  _mainMenuToggle(icon: _selectedTool == 'Callout' ? Icons.chat_bubble_outline : Icons.title, label: _selectedTool == 'Callout' ? "Callout" : "Text", isActive: _showTextToolbar || _selectedTool == 'Text' || _selectedTool == 'Callout', hasDropdown: true, theme: theme, onTap: () => setState(() { _showTextToolbar = !_showTextToolbar; if (_showTextToolbar) { _showPencilToolbar = false; _showShapeToolbar = false; if (_selectedTool != 'Text' && _selectedTool != 'Callout') { _selectedTool = 'Text'; } } else { _selectedTool = 'Select'; } })),
                  _mainMenuToggle(icon: Icons.place, label: "Pin", isActive: _selectedTool == 'Pin', hasDropdown: false, theme: theme, onTap: () => setState(() { _showPencilToolbar = false; _showShapeToolbar = false; _showTextToolbar = false; _selectedTool = 'Pin'; })),
                  _mainMenuToggle(icon: Icons.handyman_outlined, label: "Tools", isActive: _showCustomToolsPanel, hasDropdown: false, theme: theme, onTap: () => setState(() { _showCustomToolsPanel = !_showCustomToolsPanel; if (_showCustomToolsPanel) { _selectedTool = 'CustomTool'; _showPencilToolbar = false; _showShapeToolbar = false; _showTextToolbar = false; } else { _selectedTool = 'Select'; _selectedCustomTool = null; } })),
                  _vDiv(theme),
                  _utilityIcon(Icons.copy, "Copy", theme, _copySelected, isEnabled: _activeObject != null),
                  _utilityIcon(Icons.paste, "Paste", theme, _pasteFromClipboard, isEnabled: _clipboard != null),
                  _vDiv(theme),
                  _utilityIcon(Icons.undo, "Undo", theme, _undo, isEnabled: _undoStack.isNotEmpty),
                  _utilityIcon(Icons.redo, "Redo", theme, _redo, isEnabled: _redoStack.isNotEmpty),
                  _utilityIcon(Icons.delete_outline, "Delete", theme, _deleteSelected, isDestructive: true, isEnabled: _activeObject != null),
                ],
              ),
            ),
          ),
          
          // 2. RIGHT SIDE: Document Controls
          Container(width: 1, height: 32, color: theme.colorScheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 16)),
          
          if (widget.annotateImageKey == null) ...[
            _buildPageSelector(theme),
            const SizedBox(width: 12),
          ],

          // Save Button
          if (_isSaving)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
            )
          else
            IconButton(
              tooltip: "Save Annotations",
              icon: const Icon(Icons.save_outlined),
              color: theme.colorScheme.primary,
              onPressed: _saveAnnotations,
            ),
            
          const SizedBox(width: 8),

          // Close Canvas Button
          IconButton(
            tooltip: "Close Canvas",
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingDocument) {
      return Scaffold(
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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelected,
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copySelected, 
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteFromClipboard, 
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
          const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
          const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
          const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
            if (_selectedTool == 'Pen') _finalizeCurrentPreview();
          }),
        },
        child: Focus(
          focusNode: _canvasFocusNode,
          autofocus: true,
          child: Column(
            children: [
                _buildFullWidthToolbar(theme),
              
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 🌟 2. THE CANVAS AREA 🌟
                    Positioned.fill(
                      child: Container(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        child: InteractiveViewer(
                          panEnabled: _selectedTool == 'Select' && _activeHandle == ResizeHandle.none,
                          scaleEnabled: true, 
                          minScale: 0.4,     
                          maxScale: 3.5,     
                          boundaryMargin: const EdgeInsets.all(double.infinity), 
                          child: Center(
                            child: MouseRegion(
                              cursor: _getCursor(_hoveredHandle),
                              onHover: (d) {
                                if (_selectedTool == 'Pen' && _currentPreview != null) {
                                  setState(() => _currentPreview!.points!.last = d.localPosition);
                                  return;
                                }
                                if (_selectedTool != 'Select') return;
                                ResizeHandle hit = ResizeHandle.none;
                                for (var obj in _drawingObjects.reversed) {
                                  hit = _getHitHandle(d.localPosition, obj);
                                  if (hit != ResizeHandle.none) break;
                                }
                                if (_hoveredHandle != hit) setState(() => _hoveredHandle = hit);
                              },
                              child: Listener(
                                onPointerDown: _handlePointerDown,
                                onPointerMove: (details) => _handlePointerMove(details, const BoxConstraints()),
                                onPointerUp: _handlePointerUp,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 816,  
                                      height: 1056, 
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, 10))
                                        ],
                                      ),
                                      child: CanvasPaper(
                                        objects: _drawingObjects, 
                                        preview: _currentPreview,
                                        backgroundImageBytes: _pageDataMap[_currentPage]?.backgroundImageBytes,                                            
                                      ),
                                    ),
                                    if (_isPageLoading)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.white.withOpacity(0.7),
                                          child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
                                        )
                                      )
                                  ]
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Floating Menus (Kept visible so they can draw in fullscreen!)
                    if (_showPencilToolbar) Positioned(top: 8, left: 80, child: _buildFloatingPencilMenu(theme)),
                    if (_showShapeToolbar) Positioned(top: 8, left: 140, child: _buildFloatingShapeMenu(theme)),
                    if (_showTextToolbar) Positioned(top: 8, left: 210, child: _buildFloatingTextMenu(theme)),

                    // 🌟 3. THE FLOATING PROPERTIES DRAWER (Hides in Fullscreen) 🌟
                    if (_activeObject != null) 
                      Positioned(
                        top: 0, right: 0, bottom: 0,
                        child: Material(
                          elevation: 16, 
                          child: PropertiesPanel(
                            activeObject: _activeObject,
                            availableTags: _availableTags,
                            onUpdate: () => setState(() {}),
                            onImageUpload: _uploadImageForObject,
                            onImageDelete: _deleteImageForObject,
                            allowImageUpload: widget.annotateImageKey == null, 
                            onImageTap: (s3Key, url) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CanvasScreen(
                                    documentId: widget.documentId,
                                    projectId: widget.projectId,
                                    inspectionId: widget.inspectionId,
                                    annotateImageUrl: url,
                                    annotateImageKey: s3Key,
                                  ),
                                ),
                              );
                            },
                            onClose: () {
                              setState(() {
                                for (var obj in _drawingObjects) { obj.isSelected = false; }
                                _activeObject = null;
                                _selectedTool = 'Select';
                              });
                            },
                          ),
                        ),
                      ),

                      // 🌟 4. THE LEFT CUSTOM TOOLS DRAWER (Hides in Fullscreen) 🌟
                    if (_showCustomToolsPanel)
                      Positioned(
                        top: 0, left: 0, bottom: 0,
                        child: Material(
                          elevation: 16,
                          child: CustomToolsPanel(
                            groups: _customToolGroups,
                            selectedTool: _selectedCustomTool,
                            onToolSelected: (tool) {
                              setState(() {
                                _selectedCustomTool = tool;
                                _selectedTool = 'CustomTool'; // Arm the tool!
                              });
                            },
                            onClose: () => setState(() { 
                              _showCustomToolsPanel = false; 
                              _selectedTool = 'Select'; 
                              _selectedCustomTool = null;
                            }),
                          ),
                        ),
                      ),

                    // 🌟 5. NATIVE FULLSCREEN TOGGLE BUTTON 🌟
                    Positioned(
                      bottom: 24,
                      right: 24,
                      child: FloatingActionButton.small(
                        heroTag: 'fullscreen_fab',
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.colorScheme.primary,
                        elevation: 4,
                        onPressed: _toggleNativeFullscreen,
                        child: Icon(
                          _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        ),
                      ),
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

  // @override
  // Widget build(BuildContext context) {
  //   final theme = Theme.of(context);

  //   if (_isLoadingDocument) {
  //     return Scaffold(
  //       backgroundColor: theme.scaffoldBackgroundColor,
  //       body: Center(
  //         child: Column(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             CircularProgressIndicator(color: theme.colorScheme.primary),
  //             const SizedBox(height: 16),
  //             Text(widget.annotateImageKey == null ? "Loading Document..." : "Loading Image...", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
  //           ],
  //         ),
  //       ),
  //     );
  //   }

  //   return Scaffold(
  //     backgroundColor: theme.scaffoldBackgroundColor,
  //     body: CallbackShortcuts(
  //       bindings: <ShortcutActivator, VoidCallback>{
  //         const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelected,
  //         const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copySelected, 
  //         const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteFromClipboard,
  //         const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteFromClipboard, 
  //         const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
  //         const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
  //         const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
  //         const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
  //         const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
  //         const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
  //           if (_selectedTool == 'Pen') _finalizeCurrentPreview();
  //         }),
  //       },
  //       child: Focus(
  //         focusNode: _canvasFocusNode,
  //         autofocus: true,
  //         child: Column(
  //           children: [
  //             // 🌟 1. THE UNIFIED TOOLBAR 🌟
  //             _buildFullWidthToolbar(theme),
              
  //             Expanded(
  //               child: Stack(
  //                 clipBehavior: Clip.none,
  //                 children: [
  //                   // 🌟 2. THE CANVAS AREA 🌟
  //                   Positioned.fill(
  //                     child: Container(
  //                       color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
  //                       child: InteractiveViewer(
  //                         panEnabled: _selectedTool == 'Select' && _activeHandle == ResizeHandle.none,
  //                         scaleEnabled: true, 
  //                         minScale: 0.4,     
  //                         maxScale: 3.5,     
  //                         boundaryMargin: const EdgeInsets.all(double.infinity), 
  //                         child: Center(
  //                           child: MouseRegion(
  //                             cursor: _getCursor(_hoveredHandle),
  //                             onHover: (d) {
  //                               if (_selectedTool == 'Pen' && _currentPreview != null) {
  //                                 setState(() => _currentPreview!.points!.last = d.localPosition);
  //                                 return;
  //                               }
  //                               if (_selectedTool != 'Select') return;
  //                               ResizeHandle hit = ResizeHandle.none;
  //                               for (var obj in _drawingObjects.reversed) {
  //                                 hit = _getHitHandle(d.localPosition, obj);
  //                                 if (hit != ResizeHandle.none) break;
  //                               }
  //                               if (_hoveredHandle != hit) setState(() => _hoveredHandle = hit);
  //                             },
  //                             child: Listener(
  //                               onPointerDown: _handlePointerDown,
  //                               onPointerMove: (details) => _handlePointerMove(details, const BoxConstraints()),
  //                               onPointerUp: _handlePointerUp,
  //                               child: Stack(
  //                                 alignment: Alignment.center,
  //                                 children: [
  //                                   Container(
  //                                     width: 816,  
  //                                     height: 1056, 
  //                                     decoration: BoxDecoration(
  //                                       color: Colors.white,
  //                                       boxShadow: [
  //                                         BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, 10))
  //                                       ],
  //                                     ),
  //                                     child: CanvasPaper(
  //                                       objects: _drawingObjects, 
  //                                       preview: _currentPreview,
  //                                       backgroundImageBytes: _pageDataMap[_currentPage]?.backgroundImageBytes,                                            
  //                                     ),
  //                                   ),
  //                                   if (_isPageLoading)
  //                                     Positioned.fill(
  //                                       child: Container(
  //                                         color: Colors.white.withOpacity(0.7),
  //                                         child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
  //                                       )
  //                                     )
  //                                 ]
  //                               ),
  //                             ),
  //                           ),
  //                         ),
  //                       ),
  //                     ),
  //                   ),
                    
  //                   // Floating Menus
  //                   if (_showPencilToolbar) Positioned(top: 8, left: 80, child: _buildFloatingPencilMenu(theme)),
  //                   if (_showShapeToolbar) Positioned(top: 8, left: 140, child: _buildFloatingShapeMenu(theme)),
  //                   if (_showTextToolbar) Positioned(top: 8, left: 210, child: _buildFloatingTextMenu(theme)),

  //                   // 🌟 3. THE FLOATING PROPERTIES DRAWER 🌟
  //                   if (_activeObject != null) 
  //                     Positioned(
  //                       top: 0, right: 0, bottom: 0,
  //                       child: Material(
  //                         elevation: 16, 
  //                         child: PropertiesPanel(
  //                           activeObject: _activeObject,
  //                           availableTags: _availableTags,
  //                           onUpdate: () => setState(() {}),
  //                           onImageUpload: _uploadImageForObject,
  //                           onImageDelete: _deleteImageForObject,
  //                           allowImageUpload: widget.annotateImageKey == null, 
                            
  //                           // 🚀 THE NEW CLICK HANDLER 🚀
  //                           onImageTap: (s3Key, url) {
  //                             Navigator.push(
  //                               context,
  //                               MaterialPageRoute(
  //                                 builder: (context) => CanvasScreen(
  //                                   documentId: widget.documentId,
  //                                   projectId: widget.projectId,
  //                                   inspectionId: widget.inspectionId,
  //                                   annotateImageUrl: url,
  //                                   annotateImageKey: s3Key,
  //                                 ),
  //                               ),
  //                             );
  //                           },
                            
  //                           onClose: () {
  //                             setState(() {
  //                               for (var obj in _drawingObjects) { obj.isSelected = false; }
  //                               _activeObject = null;
  //                               _selectedTool = 'Select';
  //                             });
  //                           },
  //                         ),
  //                       ),
  //                     ),

  //                     // 🌟 4. THE LEFT CUSTOM TOOLS DRAWER 🌟
  //                   if (_showCustomToolsPanel)
  //                     Positioned(
  //                       top: 0, left: 0, bottom: 0,
  //                       child: Material(
  //                         elevation: 16,
  //                         child: CustomToolsPanel(
  //                           groups: _customToolGroups,
  //                           selectedTool: _selectedCustomTool,
  //                           onToolSelected: (tool) {
  //                             setState(() {
  //                               _selectedCustomTool = tool;
  //                               _selectedTool = 'CustomTool'; // Arm the tool!
  //                             });
  //                           },
  //                           onClose: () => setState(() { 
  //                             _showCustomToolsPanel = false; 
  //                             _selectedTool = 'Select'; 
  //                             _selectedCustomTool = null;
  //                           }),
  //                         ),
  //                       ),
  //                     ),
  //                 ],
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }
}