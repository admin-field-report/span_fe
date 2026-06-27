import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import 'models/canvas_models.dart';
import 'widgets/canvas_painter.dart';
import '../../utils/app_responsive.dart'; 

// Helper class for the left sidebar tools
class _ToolItem {
  final String name;
  final IconData icon;
  _ToolItem(this.name, this.icon);
}

class Canvas extends StatefulWidget {
  // 🚀 STATE & SYNC PROPS
  final GlobalKey<CanvasState>? canvasKey;
  final Uint8List? initialBackgroundImage;
  final List<DrawingObject> initialObjects;
  final ValueChanged<DrawingObject?>? onSelectionChanged;
  final ValueChanged<String>? onToolChanged;
  
  // 🚀 NEW: Accept dynamic dimensions
  final double width;
  final double height;

  final List<Widget>? leftActions;
  final List<Widget>? rightActions;

  // 🚀 INJECTION SLOTS
  final String? customTabLabel;
  final Widget? customTabContent;
  final Widget? customRightPanel;

  final bool showCloseButton;
  final VoidCallback? onClosePressed;

  const Canvas({
    super.key,
    this.canvasKey,
    this.initialBackgroundImage,
    this.initialObjects = const [],
    this.width = 816.0,  // Fallback default
    this.height = 1056.0, // Fallback default
    this.onSelectionChanged,
    this.onToolChanged,
    this.leftActions,
    this.rightActions,
    this.customTabLabel,
    this.customTabContent,
    this.customRightPanel,
    this.showCloseButton = false, 
    this.onClosePressed,
  });

  @override
  State<Canvas> createState() => CanvasState();
}

class CanvasState extends State<Canvas> {
  final FocusNode _canvasFocusNode = FocusNode();

  final TransformationController _transformationController = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();
  
  bool _isFullScreen = false;
  bool _showLeftPanel = true; // 🚀 OPTIMIZATION: Open by default

  double _minScale = 0.1;
  double _maxScale = 5.0;

  // 🚀 OPTIMIZATION: Slimmed down default panel widths
  double _leftPanelWidth = 220.0; 
  double _rightPanelWidth = 260.0;

  String _selectedTool = 'Select';

  String? _selectedCustomToolId;
  List<DrawingObject>? _selectedCustomToolShapes;

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
  
  double _patternDensity = 20.0; 

  late List<DrawingObject> _drawingObjects;
  final List<List<DrawingObject>> _undoStack = [];
  final List<List<DrawingObject>> _redoStack = [];

  List<DrawingObject> get objects => _drawingObjects;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    _drawingObjects = List.from(widget.initialObjects);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerDocument();
    });
  }

  void refreshCanvas() {
    if (mounted) setState(() {});
  }

  void _centerDocument() {
    if (_viewerKey.currentContext == null) return;
    
    final RenderBox renderBox = _viewerKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;

    double initialScale = 1.0;
    
    if (size.width < widget.width || size.height < widget.height) {
      final scaleX = (size.width - 40) / widget.width;
      final scaleY = (size.height - 40) / widget.height;
      initialScale = math.min(scaleX, scaleY);
    }

    final double dx = (size.width - (widget.width * initialScale)) / 2;
    final double dy = (size.height - (widget.height * initialScale)) / 2;

    setState(() {
      _minScale = initialScale * 0.5; 
      _maxScale = math.max(5.0, initialScale * 20.0); 
    });

    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(initialScale);
  }

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    _transformationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); 
    super.dispose();
  }
  
  void applyExternalToolConfig(String tool, double stroke, Color color, Color fill, double opacity, {String? customToolId, List<DrawingObject>? customToolShapes}) {
    setState(() {
      _selectedTool = tool;
      _selectedCustomToolId = customToolId;          
      _selectedCustomToolShapes = customToolShapes;  
      
      for (var obj in _drawingObjects) {
        obj.isSelected = false;
      }
      _activeObject = null;
      widget.onSelectionChanged?.call(null); 
      
      _pencilStrokeWidth = stroke;
      _pencilColor = color;
      _penFillColor = fill;
      _pencilOpacity = opacity;

      _shapeStrokeWidth = stroke;
      _shapeLineColor = color;
      _shapeBorderColor = color;
      _shapeFillColor = fill;
      _shapeOpacity = opacity;

      _textStrokeWidth = stroke;
      _textColor = color;
      _textFillColor = fill;
      _textOpacity = opacity;
    });
  }

  void _toggleNativeFullscreen() {
    if (html.document.fullscreenElement != null) {
      html.document.exitFullscreen();
      setState(() => _isFullScreen = false);
    } else {
      html.document.documentElement?.requestFullscreen();
      setState(() => _isFullScreen = true);
    }
  }

  // ==========================================
  // DRAWING LOGIC
  // ==========================================
  
  Future<void> _showTextDialog({required Offset position, DrawingObject? existingObject, bool isCallout = false, bool isNote = false}) async {
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
                  } else if (isNote) { 
                    if (initialFill == Colors.transparent) initialFill = const Color(0xFFFFF59D);
                    if (initialBorder == Colors.transparent) initialBorder = Colors.transparent;
                    if (initialText == Colors.black) initialText = Colors.black87;
                  }

                  if (existingObject != null) {
                    existingObject.text = controller.text;
                    existingObject.end = existingObject.start + calculatedSize;
                    widget.onSelectionChanged?.call(existingObject); 
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
                    widget.onSelectionChanged?.call(textObj); 
                  }

                  if (_selectedTool != 'Pencil' && _selectedTool != 'Pen' && _selectedTool != 'Eraser') {
                    _selectedTool = 'Select';
                    widget.onToolChanged?.call('Select');
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
        widget.onSelectionChanged?.call(null); 
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        _undoStack.add(_drawingObjects.map((e) => e.copy()).toList());
        _drawingObjects = _redoStack.removeLast();
        _activeObject = null;
        widget.onSelectionChanged?.call(null); 
      });
    }
  }

  void _deleteSelected() {
    if (_drawingObjects.any((o) => o.isSelected)) {
      _saveSnapshot();
      setState(() {
        _drawingObjects.removeWhere((o) => o.isSelected);
        _activeObject = null;
        widget.onSelectionChanged?.call(null); 
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
        widget.onSelectionChanged?.call(pastedObj); 
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
    if (_selectedTool == 'Text' || _selectedTool == 'Callout' || _selectedTool == 'Note') return SystemMouseCursors.text;
    
    if (handle == ResizeHandle.none) {
      return _selectedTool == 'Select' 
          ? SystemMouseCursors.basic 
          : SystemMouseCursors.precise;
    }

    if (handle == ResizeHandle.body) return SystemMouseCursors.move;
    if (handle == ResizeHandle.rotation) return SystemMouseCursors.grab;
    if (handle == ResizeHandle.calloutKnee || handle == ResizeHandle.calloutTip) return SystemMouseCursors.move;

    double rotation = _activeObject?.rotation ?? 0.0;
    double baseAngle = 0.0;

    switch (handle) {
      case ResizeHandle.centerLeft:
      case ResizeHandle.centerRight:
        baseAngle = 0.0; 
        break;
      case ResizeHandle.topLeft:
      case ResizeHandle.bottomRight:
        baseAngle = math.pi / 4; 
        break;
      case ResizeHandle.topCenter:
      case ResizeHandle.bottomCenter:
        baseAngle = math.pi / 2; 
        break;
      case ResizeHandle.topRight:
      case ResizeHandle.bottomLeft:
        baseAngle = 3 * math.pi / 4; 
        break;
      default:
        return SystemMouseCursors.basic;
    }

    double effectiveAngle = (baseAngle + rotation) % math.pi;
    if (effectiveAngle < 0) effectiveAngle += math.pi;

    double degrees = effectiveAngle * 180 / math.pi;
    
    int snapped = ((degrees + 22.5) / 45).floor() * 45;
    snapped = snapped % 180;

    switch (snapped) {
      case 0:
        return SystemMouseCursors.resizeLeftRight;
      case 45:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case 90:
        return SystemMouseCursors.resizeUpDown;
      case 135:
        return SystemMouseCursors.resizeUpRightDownLeft;
      default:
        return SystemMouseCursors.basic;
    }
  }
  
  ResizeHandle _getHitHandle(Offset p, DrawingObject obj) {
    double scaleFactor = math.max(widget.width, widget.height) / 1056.0;
    if (scaleFactor < 1.0) scaleFactor = 1.0;

    final double hSize = 25.0 * scaleFactor; 
    
    // 🚀 THE FIX: Push the resize handles 20px away from the shape
    final double handlePadding = 20.0 * scaleFactor;
    
    final localP = _toLocalSpace(p, obj);
    final r = obj.rect;

    if (obj.isSelected) {
      // Create a padded bounding box exclusively for the resize handles
      final Rect paddedRect = r.inflate(handlePadding);

      if (obj.type == DrawingType.text && obj.isCallout && obj.points != null && obj.points!.length >= 2) {
        if ((localP - obj.points![0]).distance < hSize) return ResizeHandle.calloutKnee;
        if ((localP - obj.points![1]).distance < hSize) return ResizeHandle.calloutTip;
      }
      
      if (obj.type == DrawingType.line || obj.type == DrawingType.arrow) {
        if ((localP - obj.start).distance < hSize) return ResizeHandle.topLeft; 
        if ((localP - obj.end).distance < hSize) return ResizeHandle.bottomRight; 
      } else {
        // 🚀 We use paddedRect here so the handles sit further outside!
        Offset rotPos = Offset(paddedRect.topCenter.dx, paddedRect.topCenter.dy - (40 * scaleFactor));
        if ((localP - rotPos).distance < hSize) return ResizeHandle.rotation;

        if (obj.type != DrawingType.pencil && obj.type != DrawingType.pen) {
          if ((localP - paddedRect.topLeft).distance < hSize) return ResizeHandle.topLeft;
          if ((localP - paddedRect.topCenter).distance < hSize) return ResizeHandle.topCenter;
          if ((localP - paddedRect.topRight).distance < hSize) return ResizeHandle.topRight;
          if ((localP - paddedRect.centerLeft).distance < hSize) return ResizeHandle.centerLeft;
          if ((localP - paddedRect.centerRight).distance < hSize) return ResizeHandle.centerRight;
          if ((localP - paddedRect.bottomLeft).distance < hSize) return ResizeHandle.bottomLeft;
          if ((localP - paddedRect.bottomCenter).distance < hSize) return ResizeHandle.bottomCenter;
          if ((localP - paddedRect.bottomRight).distance < hSize) return ResizeHandle.bottomRight;
        }
      }
      
      // 🚀 MOVE GRAB: Strictly inside the actual un-padded object body bounds.
      if (r.contains(localP)) return ResizeHandle.body;
    }
    
    // --- Unselected Hit Tests ---
    if (obj.type == DrawingType.line || obj.type == DrawingType.arrow) {
      if (_distToSegment(localP, obj.start, obj.end) < (15 * scaleFactor)) return ResizeHandle.body;
    } else if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null) {
      for (int i = 0; i < obj.points!.length - 1; i++) {
        if (_distToSegment(localP, obj.points![i], obj.points![i+1]) < (15 * scaleFactor)) return ResizeHandle.body;
      }
      if (obj.fillColor != Colors.transparent && r.contains(localP)) return ResizeHandle.body;
    } else {
      if (r.inflate(5 * scaleFactor).contains(localP)) return ResizeHandle.body;
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
      if (_selectedTool == 'Text' || _selectedTool == 'Callout' || _selectedTool == 'Note') {
        _showTextDialog(position: pos, isCallout: _selectedTool == 'Callout', isNote: _selectedTool == 'Note');
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
          if (_currentPreview!.points!.length > 2 && (pos - _currentPreview!.points!.first).distance < 20) {
            _currentPreview!.points!.last = _currentPreview!.points!.first;
            _currentPreview!.points!.add(_currentPreview!.points!.first); 
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
                           (_selectedTool == 'Polygon') ? DrawingType.polygon : 
                           (_selectedTool == 'Brick') ? DrawingType.brick : 
                           (_selectedTool == 'Grid') ? DrawingType.grid : 
                           (_selectedTool == 'Horizontal') ? DrawingType.horizontal : 
                           (_selectedTool == 'Vertical') ? DrawingType.vertical : 
                           (_selectedTool == 'Forward') ? DrawingType.forwardDiag : 
                           (_selectedTool == 'Reverse') ? DrawingType.reverseDiag :
                           (_selectedTool == 'Weave') ? DrawingType.weave :
                           (_selectedTool == 'Diamond') ? DrawingType.diamond : 
                           (_selectedTool == 'Dots') ? DrawingType.dots :
                           (_selectedTool == 'Herringbone') ? DrawingType.herringbone :
                           (_selectedTool == 'Concrete') ? DrawingType.concrete :
                           (_selectedTool == 'Shingles') ? DrawingType.shingles :
                           (_selectedTool == 'Insulation') ? DrawingType.insulation :
                           (_selectedTool == 'Arrow') ? DrawingType.arrow : 
                           (_selectedTool == 'Pin') ? DrawingType.pin : 
                           (_selectedTool == 'CustomTool') ? DrawingType.customTool : DrawingType.line;
        
        List<Offset>? pts = (type == DrawingType.pencil) ? [pos] : null;
        Color objColor = Colors.black; Color objFill = Colors.transparent; double objOpacity = 1.0; double objStroke = 2.0; 

        if (type == DrawingType.pencil) {
          objColor = _pencilColor; objFill = _penFillColor; objOpacity = _pencilOpacity; objStroke = _pencilStrokeWidth; 
        } else if (type == DrawingType.pin) {
          objColor = Colors.red[800]!; objFill = Colors.red; objOpacity = 1.0; objStroke = 2.0;
        } else if (type == DrawingType.line || type == DrawingType.arrow) {
          objColor = _shapeLineColor; objOpacity = _shapeOpacity; objStroke = _shapeStrokeWidth;  
        } else if ([DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.reverseDiag, DrawingType.diamond, DrawingType.weave, DrawingType.dots, DrawingType.herringbone, DrawingType.concrete, DrawingType.shingles, DrawingType.insulation].contains(type)) {         
          objColor = _shapeBorderColor; 
          objFill = _shapeFillColor; 
          objOpacity = _shapeOpacity; 
          objStroke = _shapeStrokeWidth;  
        }

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type, points: pts, strokeWidth: objStroke, color: objColor, fillColor: objFill, opacity: objOpacity,
          toolId: type == DrawingType.customTool ? _selectedCustomToolId : null,
          internalShapes: type == DrawingType.customTool ? _selectedCustomToolShapes : null,
        );
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
          
          widget.onSelectionChanged?.call(_activeObject);

          if (hitHandle == ResizeHandle.rotation) _initialRotationAngle = math.atan2(pos.dy - hitObj.center.dy, pos.dx - hitObj.center.dx) - hitObj.rotation;
          else if (hitHandle == ResizeHandle.body) _dragOffset = pos - hitObj.start;
        } else {
          for (var obj in _drawingObjects) obj.isSelected = false;
          _activeObject = null;
          widget.onSelectionChanged?.call(null); 
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
          
          Offset rawMoveDelta = (pos - _dragOffset) - _activeObject!.start;
          
          Rect r = _activeObject!.rect;
          double dx = rawMoveDelta.dx;
          double dy = rawMoveDelta.dy;

          if (r.left + dx < 0) dx = -r.left;
          else if (r.right + dx > widget.width) dx = widget.width - r.right;

          if (r.top + dy < 0) dy = -r.top;
          else if (r.bottom + dy > widget.height) dy = widget.height - r.bottom;

          Offset clampedDelta = Offset(dx, dy);

          _activeObject!.start += clampedDelta;
          _activeObject!.end += clampedDelta;
          
          if (_activeObject!.type == DrawingType.pencil || _activeObject!.type == DrawingType.pen) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + clampedDelta).toList();
          }
          if (_activeObject!.type == DrawingType.text && _activeObject!.isCallout && _activeObject!.points != null) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + clampedDelta).toList();
          }

        } else if (_activeObject!.type == DrawingType.line || _activeObject!.type == DrawingType.arrow) {
          final oldCenter = _activeObject!.center;
          final localP = _toLocalSpace(pos, _activeObject!);
          
          Offset newStart = _activeObject!.start;
          Offset newEnd = _activeObject!.end;
          
          if (_activeHandle == ResizeHandle.topLeft) newStart = localP;
          else if (_activeHandle == ResizeHandle.bottomRight) newEnd = localP;
          
          Offset newLocalCenter = Offset((newStart.dx + newEnd.dx) / 2, (newStart.dy + newEnd.dy) / 2);
          
          final double cosA = math.cos(_activeObject!.rotation);
          final double sinA = math.sin(_activeObject!.rotation);
          final double dcx = newLocalCenter.dx - oldCenter.dx;
          final double dcy = newLocalCenter.dy - oldCenter.dy;
          
          Offset newGlobalCenter = Offset(
            oldCenter.dx + (cosA * dcx - sinA * dcy),
            oldCenter.dy + (sinA * dcx + cosA * dcy)
          );
          
          Offset halfSize = Offset((newEnd.dx - newStart.dx) / 2, (newEnd.dy - newStart.dy) / 2);
          
          _activeObject!.start = newGlobalCenter - halfSize;
          _activeObject!.end = newGlobalCenter + halfSize;
          
        } else {
          final oldCenter = _activeObject!.center;
          final localP = _toLocalSpace(pos, _activeObject!);
          
          Rect r = _activeObject!.rect;
          double left = r.left, top = r.top, right = r.right, bottom = r.bottom;
          
          // 🚀 MUST match the padding used in _getHitHandle to calculate math correctly
          double scaleFactor = math.max(widget.width, widget.height) / 1056.0;
          if (scaleFactor < 1.0) scaleFactor = 1.0;
          final double padding = 20.0 * scaleFactor;
          
          // Reverse the padding from the pointer's location to find the true shape edge
          switch (_activeHandle) {
            case ResizeHandle.topLeft: left = localP.dx + padding; top = localP.dy + padding; break;
            case ResizeHandle.topCenter: top = localP.dy + padding; break;
            case ResizeHandle.topRight: right = localP.dx - padding; top = localP.dy + padding; break;
            case ResizeHandle.centerLeft: left = localP.dx + padding; break;
            case ResizeHandle.centerRight: right = localP.dx - padding; break;
            case ResizeHandle.bottomLeft: left = localP.dx + padding; bottom = localP.dy - padding; break;
            case ResizeHandle.bottomCenter: bottom = localP.dy - padding; break;
            case ResizeHandle.bottomRight: right = localP.dx - padding; bottom = localP.dy - padding; break;
            default: break;
          }

          double newWidth = right - left;
          double newHeight = bottom - top;

          if (newWidth < 10) {
            newWidth = 10;
            if (_activeHandle == ResizeHandle.topLeft || _activeHandle == ResizeHandle.bottomLeft || _activeHandle == ResizeHandle.centerLeft) left = right - 10;
            else right = left + 10;
          }
          if (newHeight < 10) {
            newHeight = 10;
            if (_activeHandle == ResizeHandle.topLeft || _activeHandle == ResizeHandle.topRight || _activeHandle == ResizeHandle.topCenter) top = bottom - 10;
            else bottom = top + 10;
          }

          Offset newLocalCenter = Offset(left + newWidth / 2, top + newHeight / 2);

          final double cosA = math.cos(_activeObject!.rotation);
          final double sinA = math.sin(_activeObject!.rotation);
          final double dcx = newLocalCenter.dx - oldCenter.dx;
          final double dcy = newLocalCenter.dy - oldCenter.dy;
          
          Offset newGlobalCenter = Offset(
            oldCenter.dx + (cosA * dcx - sinA * dcy),
            oldCenter.dy + (sinA * dcx + cosA * dcy)
          );

          _activeObject!.start = newGlobalCenter - Offset(newWidth / 2, newHeight / 2);
          _activeObject!.end = newGlobalCenter + Offset(newWidth / 2, newHeight / 2);
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
        _currentPreview = null;
        widget.onSelectionChanged?.call(_activeObject); 

        if (_selectedTool != 'Pencil' && _selectedTool != 'Pen' && _selectedTool != 'Eraser') {
          _selectedTool = 'Select';
          widget.onToolChanged?.call('Select');
        }
      }
      _activeHandle = ResizeHandle.none;
    });
  }

  Offset _clampToCanvas(Offset pos) {
    return Offset(
      pos.dx.clamp(0.0, widget.width),
      pos.dy.clamp(0.0, widget.height),
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
      _currentPreview = null;
      widget.onSelectionChanged?.call(_activeObject); 
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
                else if (mode == 2) { 
                  _shapeBorderColor = newColor; 
                  if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.reverseDiag, DrawingType.diamond, DrawingType.weave, DrawingType.dots, DrawingType.herringbone, DrawingType.concrete, DrawingType.shingles, DrawingType.insulation].contains(_activeObject!.type)) {
                    _activeObject!.color = newColor; 
                  }
                } 
                else if (mode == 3) { 
                  _shapeFillColor = newColor; 
                  if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.reverseDiag, DrawingType.diamond, DrawingType.weave, DrawingType.dots, DrawingType.herringbone, DrawingType.concrete, DrawingType.shingles, DrawingType.insulation].contains(_activeObject!.type)) {
                    _activeObject!.fillColor = newColor; 
                  }
                }
                else if (mode == 4) { _textColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.color = newColor; } 
                else if (mode == 5) { _textBorderColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.borderColor = newColor; } 
                else if (mode == 6) { _textFillColor = newColor; if (_activeObject?.type == DrawingType.text) _activeObject!.fillColor = newColor; } 
                else if (mode == 7) { _penFillColor = newColor; if (_activeObject?.type == DrawingType.pen || _activeObject?.type == DrawingType.pencil) _activeObject!.fillColor = newColor; }
              });
            }

            String colorToHex(Color c) => c == Colors.transparent ? "NONE" : '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
            const double squareWidth = 240.0; const double squareHeight = 200.0;
            final bool showOpacity = (mode == 3 || mode == 6 || mode == 7);
            final bool showNone = showOpacity;

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
                            if (mode == 3) {
                              _shapeOpacity = v;
                              if (_activeObject != null && _isStyledShapeType(_activeObject!.type)) {
                                _activeObject!.opacity = v;
                              }
                            } else if (mode == 6) {
                              _textOpacity = v;
                              if (_activeObject?.type == DrawingType.text) {
                                _activeObject!.opacity = v;
                              }
                            } else if (mode == 7) {
                              _pencilOpacity = v;
                              if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) {
                                _activeObject!.opacity = v;
                              }
                            }
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

  Widget _buildResizer({required bool isLeft, required Function(double) onPanUpdate}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) => onPanUpdate(details.delta.dx),
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              left: isLeft ? BorderSide.none : BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
              right: isLeft ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1) : BorderSide.none,
            ),
          ),
          child: Center(
            child: Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2)
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isShapeSelected(String tool) => ['Rect', 'Circle', 'Line', 'Arrow', 'Polygon'].contains(tool);
  bool _isPatternSelected(String tool) => ['Brick', 'Grid', 'Horizontal', 'Vertical', 'Forward', 'Reverse', 'Diamond', 'Weave', 'Dots', 'Herringbone', 'Concrete', 'Shingles', 'Insulation'].contains(tool);

  Widget _topToolbarGroup(ThemeData theme, List<Widget> children) {
    final isMobile = AppResponsive.isMobileScreen(context);
    return Container(
      height: isMobile ? 30 : 34,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _topToolbarButton({
    required ThemeData theme,
    required IconData icon,
    Color? iconColor,
    required String tooltip,
    required VoidCallback? onTap,
    bool isSelected = false,
    bool isDestructive = false,
    bool isGrouped = false,
  }) {
    final isMobile = AppResponsive.isMobileScreen(context);
    final double size = isMobile ? 26 : 30;
    final bool isEnabled = onTap != null;
    final Color foregroundColor = !isEnabled
        ? theme.disabledColor.withOpacity(0.55)
        : isDestructive
            ? theme.colorScheme.error
            : isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant;

    final Color backgroundColor = isSelected
        ? theme.colorScheme.primary.withOpacity(0.14)
        : isGrouped
            ? Colors.transparent
            : theme.colorScheme.surfaceVariant.withOpacity(isEnabled ? 0.18 : 0.10);

    final Border? border = isGrouped
        ? (isSelected ? Border.all(color: theme.colorScheme.primary.withOpacity(0.22)) : null)
        : Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.26)
                : theme.colorScheme.outlineVariant.withOpacity(isEnabled ? 0.45 : 0.25),
          );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            margin: isGrouped ? const EdgeInsets.symmetric(horizontal: 1) : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: border,
            ),
            child: Icon(icon, size: isMobile ? 15 : 17, color: iconColor ?? foregroundColor),
          ),
        ),
      ),
    );
  }

  Widget _compactExternalActions(ThemeData theme, List<Widget>? actions) {
    if (actions == null || actions.isEmpty) return const SizedBox.shrink();

    final isMobile = AppResponsive.isMobileScreen(context);
    final double size = isMobile ? 28 : 32;
    final double gap = isMobile ? 4 : 6;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.45)),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: actions[i],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // 🚀 OPTIMIZATION: Slimmer, denser folder structure for tools
  Widget _buildToolCategory(ThemeData theme, String title, List<_ToolItem> tools, {bool initiallyExpanded = false}) {
    final isMobile = AppResponsive.isMobileScreen(context);
    
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12)),
        initiallyExpanded: initiallyExpanded,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0.0),
        childrenPadding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, // 🚀 Tighter 4-column layout
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1.0,
              ),
              itemCount: tools.length,
              itemBuilder: (context, index) {
                final tool = tools[index];
                final isSelected = _selectedTool == tool.name;
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedTool == tool.name) {
                        _selectedTool = 'Select';
                      } else {
                        _selectedTool = tool.name;
                      }
                      
                      for (var obj in _drawingObjects) obj.isSelected = false;
                      _activeObject = null;
                      widget.onSelectionChanged?.call(null); 
                    });
                    
                    widget.onToolChanged?.call(_selectedTool); 
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5), 
                        width: isSelected ? 1.5 : 1
                      ),
                      borderRadius: BorderRadius.circular(6),
                      color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : Colors.transparent,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tool.icon, 
                          size: isMobile ? 14 : 16, 
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7)
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tool.name, 
                          style: TextStyle(
                            fontSize: 8, 
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface
                          ), 
                          textAlign: TextAlign.center, 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLeftToolsPanel(ThemeData theme) {
    final bool hasCustomTab = widget.customTabContent != null;

    return Container(
      width: _leftPanelWidth, 
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: DefaultTabController(
        length: hasCustomTab ? 2 : 1,
        child: Column(
          children: [
            TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                const Tab(text: "Tools"),
                if (hasCustomTab) Tab(text: widget.customTabLabel ?? "Custom"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildToolCategory(theme, "Draw", [
                        _ToolItem("Pencil", Icons.edit),
                        _ToolItem("Pen", Icons.polyline),
                      ], initiallyExpanded: true),
                      
                      _buildToolCategory(theme, "Shapes", [
                        _ToolItem("Rect", Icons.crop_square),
                        _ToolItem("Circle", Icons.panorama_fish_eye),
                        _ToolItem("Polygon", Icons.change_history),
                        _ToolItem("Line", Icons.show_chart),
                        _ToolItem("Arrow", Icons.arrow_outward),
                      ], initiallyExpanded: true),
                      
                      _buildToolCategory(theme, "Text", [
                        _ToolItem("Text", Icons.title),
                        _ToolItem("Callout", Icons.chat_bubble_outline),
                        _ToolItem("Note", Icons.sticky_note_2),
                      ], initiallyExpanded: true),
                      
                      _buildToolCategory(theme, "Patterns", [
                        _ToolItem("Brick", Icons.view_module),
                        _ToolItem("Grid", Icons.grid_on),
                        _ToolItem("Horizontal", Icons.notes),
                        _ToolItem("Vertical", Icons.view_column),
                        _ToolItem("Forward", Icons.trending_up),
                        _ToolItem("Reverse", Icons.trending_down),
                        _ToolItem("Weave", Icons.grid_goldenratio),
                        _ToolItem("Diamond", Icons.grid_4x4),
                        _ToolItem("Herringbone", Icons.view_quilt),
                        _ToolItem("Concrete", Icons.grain),
                        _ToolItem("Shingles", Icons.roofing),
                        _ToolItem("Insulation", Icons.waves),
                        _ToolItem("Dots", Icons.scatter_plot),
                      ], initiallyExpanded: true),

                      _buildToolCategory(theme, "Additional Tools", [
                        _ToolItem("Pin", Icons.place),
                      ], initiallyExpanded: true),
                    ],
                  ),
                  if (hasCustomTab) widget.customTabContent!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    final isMobile = AppResponsive.isMobileScreen(context);
    final double toolbarHeight = isMobile ? 38 : 42;
    final double itemGap = isMobile ? 4 : 6;
    final bool hasLeftActions = widget.leftActions != null && widget.leftActions!.isNotEmpty;
    final bool hasRightActions = widget.rightActions != null && widget.rightActions!.isNotEmpty;

    void activateSelectTool() {
      setState(() {
        _selectedTool = 'Select';
        for (var obj in _drawingObjects) obj.isSelected = false;
        _activeObject = null;
        widget.onSelectionChanged?.call(null);
      });
      widget.onToolChanged?.call('Select');
    }

    final leftGroup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _topToolbarButton(
          theme: theme,
          icon: _showLeftPanel ? Icons.handyman : Icons.handyman_outlined,
          tooltip: _showLeftPanel ? 'Hide tools' : 'Show tools',
          isSelected: _showLeftPanel,
          onTap: () => setState(() => _showLeftPanel = !_showLeftPanel),
        ),
        SizedBox(width: itemGap),
        _topToolbarButton(
          theme: theme,
          icon: Icons.near_me_outlined,
          tooltip: 'Select tool',
          isSelected: _selectedTool == 'Select',
          onTap: activateSelectTool,
        ),
        if (hasLeftActions) ...[
          SizedBox(width: itemGap),
          _compactExternalActions(theme, widget.leftActions),
        ],
        SizedBox(width: itemGap),
        _topToolbarGroup(
          theme,
          [
            _topToolbarButton(
              theme: theme,
              icon: Icons.undo_rounded,
              tooltip: 'Undo',
              onTap: _undoStack.isNotEmpty ? _undo : null,
              isGrouped: true,
            ),
            _topToolbarButton(
              theme: theme,
              icon: Icons.redo_rounded,
              tooltip: 'Redo',
              onTap: _redoStack.isNotEmpty ? _redo : null,
              isGrouped: true,
            ),
          ],
        ),
        SizedBox(width: itemGap),
        _topToolbarButton(
          theme: theme,
          icon: Icons.delete_outline_rounded,
          iconColor: Colors.redAccent,
          tooltip: 'Delete selected',
          isDestructive: true,
          onTap: _activeObject != null ? _deleteSelected : null,
        ),
      ],
    );

    final rightGroup = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasRightActions) ...widget.rightActions!,
        
        if (widget.showCloseButton && !_isFullScreen) ...[
          if (hasRightActions) SizedBox(width: itemGap),
          _topToolbarButton(
            theme: theme,
            icon: Icons.close_rounded,
            tooltip: 'Close canvas',
            onTap: widget.onClosePressed,
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      height: toolbarHeight,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6.0 : 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.96),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.45))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  leftGroup,
                  if (hasRightActions || (widget.showCloseButton && !_isFullScreen)) ...[
                    SizedBox(width: isMobile ? 12 : 18),
                    rightGroup,
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isFreehandType(DrawingType type) => type == DrawingType.pencil || type == DrawingType.pen;

  bool _isLineType(DrawingType type) => type == DrawingType.line || type == DrawingType.arrow;

  bool _isStyledShapeType(DrawingType type) => [
    DrawingType.rect,
    DrawingType.circle,
    DrawingType.polygon,
    DrawingType.brick,
    DrawingType.grid,
    DrawingType.horizontal,
    DrawingType.vertical,
    DrawingType.forwardDiag,
    DrawingType.reverseDiag,
    DrawingType.diamond,
    DrawingType.weave,
    DrawingType.dots,
    DrawingType.herringbone,
    DrawingType.concrete,
    DrawingType.shingles,
    DrawingType.insulation,
  ].contains(type);

  bool _usesShapeStyle(DrawingType type) => _isStyledShapeType(type) || _isLineType(type);

  String _selectedObjectLabel(DrawingType type) {
    switch (type) {
      case DrawingType.pencil:
        return 'Pencil';
      case DrawingType.pen:
        return 'Pen';
      case DrawingType.rect:
        return 'Rect';
      case DrawingType.circle:
        return 'Circle';
      case DrawingType.polygon:
        return 'Polygon';
      case DrawingType.line:
        return 'Line';
      case DrawingType.arrow:
        return 'Arrow';
      case DrawingType.text:
        return _activeObject?.isCallout == true ? 'Callout' : 'Text';
      case DrawingType.pin:
        return 'Pin';
      case DrawingType.customTool:
        return 'Custom';
      default:
        return 'Shape';
    }
  }

  IconData _selectedObjectIcon(DrawingType type) {
    switch (type) {
      case DrawingType.pencil:
        return Icons.edit;
      case DrawingType.pen:
        return Icons.polyline;
      case DrawingType.rect:
        return Icons.crop_square;
      case DrawingType.circle:
        return Icons.panorama_fish_eye;
      case DrawingType.polygon:
        return Icons.change_history;
      case DrawingType.line:
        return Icons.show_chart;
      case DrawingType.arrow:
        return Icons.arrow_outward;
      case DrawingType.text:
        return Icons.title;
      case DrawingType.pin:
        return Icons.place;
      case DrawingType.customTool:
        return Icons.widgets_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  double _currentStrokeWidth(int mode) {
    final value = _activeObject?.strokeWidth ?? (mode == 0 ? _pencilStrokeWidth : mode == 2 ? _textStrokeWidth : _shapeStrokeWidth);
    return value.clamp(1.0, 20.0).toDouble();
  }

  void _setStrokeWidthForMode(int mode, double value) {
    setState(() {
      if (mode == 0) {
        _pencilStrokeWidth = value;
        if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) {
          _activeObject!.strokeWidth = value;
        }
      } else if (mode == 1) {
        _shapeStrokeWidth = value;
        if (_activeObject != null && _usesShapeStyle(_activeObject!.type)) {
          _activeObject!.strokeWidth = value;
        }
      } else if (mode == 2) {
        _textStrokeWidth = value;
        if (_activeObject?.type == DrawingType.text) {
          _activeObject!.strokeWidth = value;
        }
      }
    });
  }

  double _currentTextSize() {
    final value = _activeObject?.fontSize ?? _textSize;
    return value.clamp(10.0, 120.0).toDouble();
  }

  void _setTextSize(double value) {
    setState(() {
      _textSize = value;
      if (_activeObject?.type == DrawingType.text) {
        _activeObject!.fontSize = value;
      }
    });
  }

  double _currentDensity() {
    final value = _activeObject?.type == DrawingType.dots ? _activeObject!.patternDensity : _patternDensity;
    return value.clamp(5.0, 100.0).toDouble();
  }

  void _setDensity(double value) {
    setState(() {
      _patternDensity = value;
      if (_activeObject?.type == DrawingType.dots) {
        _activeObject!.patternDensity = value;
      }
    });
  }

  void _setTextBold(bool value) {
    setState(() {
      _textIsBold = value;
      if (_activeObject?.type == DrawingType.text) _activeObject!.isBold = value;
    });
  }

  void _setTextItalic(bool value) {
    setState(() {
      _textIsItalic = value;
      if (_activeObject?.type == DrawingType.text) _activeObject!.isItalic = value;
    });
  }

  void _setTextUnderline(bool value) {
    setState(() {
      _textIsUnderline = value;
      if (_activeObject?.type == DrawingType.text) _activeObject!.isUnderline = value;
    });
  }

  void _setTextStrikethrough(bool value) {
    setState(() {
      _textIsStrikethrough = value;
      if (_activeObject?.type == DrawingType.text) _activeObject!.isStrikethrough = value;
    });
  }

  void _duplicateSelected() {
    if (_activeObject == null) return;
    _saveSnapshot();
    setState(() {
      final duplicated = _activeObject!.copy();
      const shift = Offset(20, 20);
      duplicated.start += shift;
      duplicated.end += shift;
      if (duplicated.points != null) {
        duplicated.points = duplicated.points!.map((point) => point + shift).toList();
      }
      for (final obj in _drawingObjects) {
        obj.isSelected = false;
      }
      duplicated.isSelected = true;
      _drawingObjects.add(duplicated);
      _activeObject = duplicated;
      widget.onSelectionChanged?.call(duplicated);
    });
  }

  Future<void> _showToolbarPopover({
    required GlobalKey anchorKey,
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Widget Function(StateSetter setPopoverState) builder,
    double width = 232,
  }) async {
    if (_activeObject != null) _saveSnapshot();

    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null || !mounted) return;

    final renderObject = anchorContext.findRenderObject();
    final overlayState = Overlay.of(context, rootOverlay: true);
    final overlayObject = overlayState.context.findRenderObject();
    if (renderObject is! RenderBox || overlayObject is! RenderBox) return;

    final overlaySize = overlayObject.size;
    final targetOffset = renderObject.localToGlobal(Offset.zero, ancestor: overlayObject);
    final targetSize = renderObject.size;
    final targetCenterX = targetOffset.dx + targetSize.width / 2;

    final popoverWidth = math.min(width, math.max(180.0, overlaySize.width - 16.0)).toDouble();
    final maxLeft = math.max(8.0, overlaySize.width - popoverWidth - 8.0);
    final left = (targetCenterX - popoverWidth / 2).clamp(8.0, maxLeft).toDouble();
    final arrowLeft = (targetCenterX - left - 6).clamp(18.0, popoverWidth - 18.0).toDouble();

    final bottom = (overlaySize.height - targetOffset.dy + 8)
        .clamp(8.0, math.max(8.0, overlaySize.height - 8.0))
        .toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left,
              bottom: bottom,
              child: Material(
                type: MaterialType.transparency,
                child: StatefulBuilder(
                  builder: (context, setPopoverState) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: popoverWidth,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.7)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.16),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: Icon(Icons.close, size: 15, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              builder(setPopoverState),
                            ],
                          ),
                        ),
                        Positioned(
                          left: arrowLeft,
                          bottom: -5,
                          child: Transform.rotate(
                            angle: math.pi / 4,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                border: Border(
                                  right: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.7)),
                                  bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.7)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildPopoverSlider({
    required ThemeData theme,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Value', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            Text(valueLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _showStrokePopover(GlobalKey anchorKey, ThemeData theme, int mode) {
    _showToolbarPopover(
      anchorKey: anchorKey,
      theme: theme,
      title: mode == 2 ? 'Outline width' : 'Thickness',
      icon: Icons.line_weight,
      builder: (setPopoverState) {
        final value = _currentStrokeWidth(mode);
        return _buildPopoverSlider(
          theme: theme,
          value: value,
          min: 1,
          max: 20,
          divisions: 19,
          valueLabel: '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} px',
          onChanged: (newValue) {
            _setStrokeWidthForMode(mode, newValue);
            setPopoverState(() {});
          },
        );
      },
    );
  }

  void _showTextSizePopover(GlobalKey anchorKey, ThemeData theme) {
    _showToolbarPopover(
      anchorKey: anchorKey,
      theme: theme,
      title: 'Text size',
      icon: Icons.format_size,
      builder: (setPopoverState) {
        final value = _currentTextSize();
        return _buildPopoverSlider(
          theme: theme,
          value: value,
          min: 10,
          max: 120,
          divisions: 110,
          valueLabel: '${value.toInt()} px',
          onChanged: (newValue) {
            _setTextSize(newValue);
            setPopoverState(() {});
          },
        );
      },
    );
  }

  void _showDensityPopover(GlobalKey anchorKey, ThemeData theme) {
    _showToolbarPopover(
      anchorKey: anchorKey,
      theme: theme,
      title: 'Dot density',
      icon: Icons.blur_on,
      builder: (setPopoverState) {
        final value = _currentDensity();
        return _buildPopoverSlider(
          theme: theme,
          value: value,
          min: 5,
          max: 100,
          divisions: 19,
          valueLabel: '${value.toInt()}%',
          onChanged: (newValue) {
            _setDensity(newValue);
            setPopoverState(() {});
          },
        );
      },
    );
  }

  Widget _textStyleToggleButton({
    required ThemeData theme,
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 34,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer.withOpacity(0.8) : theme.colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? theme.colorScheme.primary.withOpacity(0.55) : theme.colorScheme.outlineVariant.withOpacity(0.45),
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _showTextStylePopover(GlobalKey anchorKey, ThemeData theme) {
    _showToolbarPopover(
      anchorKey: anchorKey,
      theme: theme,
      title: 'Text style',
      icon: Icons.text_format,
      width: 214,
      builder: (setPopoverState) {
        final isBold = _activeObject?.isBold ?? _textIsBold;
        final isItalic = _activeObject?.isItalic ?? _textIsItalic;
        final isUnderline = _activeObject?.isUnderline ?? _textIsUnderline;
        final isStrikethrough = _activeObject?.isStrikethrough ?? _textIsStrikethrough;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _textStyleToggleButton(
              theme: theme,
              icon: Icons.format_bold,
              tooltip: 'Bold',
              selected: isBold,
              onTap: () {
                _setTextBold(!isBold);
                setPopoverState(() {});
              },
            ),
            _textStyleToggleButton(
              theme: theme,
              icon: Icons.format_italic,
              tooltip: 'Italic',
              selected: isItalic,
              onTap: () {
                _setTextItalic(!isItalic);
                setPopoverState(() {});
              },
            ),
            _textStyleToggleButton(
              theme: theme,
              icon: Icons.format_underlined,
              tooltip: 'Underline',
              selected: isUnderline,
              onTap: () {
                _setTextUnderline(!isUnderline);
                setPopoverState(() {});
              },
            ),
            _textStyleToggleButton(
              theme: theme,
              icon: Icons.format_strikethrough,
              tooltip: 'Strikethrough',
              selected: isStrikethrough,
              onTap: () {
                _setTextStrikethrough(!isStrikethrough);
                setPopoverState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  bool _isFreehandToolName(String tool) => tool == 'Pencil' || tool == 'Pen';

  bool _isLineToolName(String tool) => tool == 'Line' || tool == 'Arrow';

  bool _isTextToolName(String tool) => tool == 'Text' || tool == 'Callout' || tool == 'Note';

  bool _isFilledShapeToolName(String tool) =>
      (tool == 'Rect' || tool == 'Circle' || tool == 'Polygon') || _isPatternSelected(tool);

  bool _hasSelectedToolOptions() =>
      _isFreehandToolName(_selectedTool) ||
      _isLineToolName(_selectedTool) ||
      _isFilledShapeToolName(_selectedTool) ||
      _isTextToolName(_selectedTool);

  String _contextToolbarLabel() {
    if (_activeObject != null) return _selectedObjectLabel(_activeObject!.type);
    return _selectedTool;
  }

  IconData _contextToolbarIcon() {
    if (_activeObject != null) return _selectedObjectIcon(_activeObject!.type);
    switch (_selectedTool) {
      case 'Pencil':
        return Icons.edit;
      case 'Pen':
        return Icons.polyline;
      case 'Rect':
        return Icons.crop_square;
      case 'Circle':
        return Icons.panorama_fish_eye;
      case 'Polygon':
        return Icons.change_history;
      case 'Line':
        return Icons.show_chart;
      case 'Arrow':
        return Icons.arrow_outward;
      case 'Text':
        return Icons.title;
      case 'Callout':
        return Icons.chat_bubble_outline;
      case 'Note':
        return Icons.sticky_note_2;
      case 'Dots':
        return Icons.scatter_plot;
      case 'Grid':
        return Icons.grid_on;
      case 'Brick':
        return Icons.view_module;
      case 'Horizontal':
        return Icons.notes;
      case 'Vertical':
        return Icons.view_column;
      case 'Forward':
        return Icons.trending_up;
      case 'Reverse':
        return Icons.trending_down;
      case 'Diamond':
        return Icons.grid_4x4;
      case 'Weave':
        return Icons.grid_goldenratio;
      case 'Herringbone':
        return Icons.view_quilt;
      case 'Concrete':
        return Icons.grain;
      case 'Shingles':
        return Icons.roofing;
      case 'Insulation':
        return Icons.waves;
      default:
        return Icons.tune;
    }
  }

  Widget _toolbarDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: theme.colorScheme.outlineVariant.withOpacity(0.65),
    );
  }

  Widget _toolbarAction({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required void Function(GlobalKey anchorKey) onTap,
    Color? swatch,
    bool destructive = false,
  }) {
    final isMobile = AppResponsive.isMobileScreen(context);
    final actionKey = GlobalKey();
    final size = isMobile ? 32.0 : 34.0;
    final iconSize = isMobile ? 16.0 : 17.0;
    final baseColor = destructive ? Colors.red : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(actionKey),
          child: Container(
            key: actionKey,
            width: size,
            height: size,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: iconSize, color: baseColor),
                if (swatch != null)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: swatch == Colors.transparent ? theme.colorScheme.surfaceVariant : swatch,
                        border: Border.all(color: theme.colorScheme.surface, width: 1.4),
                      ),
                      child: swatch == Colors.transparent
                          ? const Icon(Icons.block, size: 6, color: Colors.red)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contextBadge(ThemeData theme) {
    final isMobile = AppResponsive.isMobileScreen(context);
    final label = _contextToolbarLabel();
    final size = isMobile ? 32.0 : 34.0;

    return Tooltip(
      message: label,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.72),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.20)),
        ),
        child: Icon(_contextToolbarIcon(), size: isMobile ? 16 : 17, color: theme.colorScheme.primary),
      ),
    );
  }

  List<Widget> _buildToolbarActionsForContext(ThemeData theme) {
    final actions = <Widget>[];
    final object = _activeObject;

    if (object != null) {
      if (_isFreehandType(object.type)) {
        actions.addAll([
          _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 0)),
          _toolbarAction(theme: theme, icon: Icons.edit, label: 'Stroke color', swatch: object.color, onTap: (_) => _showColorPicker(0)),
          if (object.type == DrawingType.pen)
            _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: object.fillColor, onTap: (_) => _showColorPicker(7)),
        ]);
      } else if (_isLineType(object.type)) {
        actions.addAll([
          _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 1)),
          _toolbarAction(theme: theme, icon: Icons.palette_outlined, label: 'Line color', swatch: object.color, onTap: (_) => _showColorPicker(1)),
        ]);
      } else if (_isStyledShapeType(object.type)) {
        actions.addAll([
          _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 1)),
          _toolbarAction(theme: theme, icon: Icons.border_color, label: 'Border color', swatch: object.color, onTap: (_) => _showColorPicker(2)),
          _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: object.fillColor, onTap: (_) => _showColorPicker(3)),
          if (object.type == DrawingType.dots)
            _toolbarAction(theme: theme, icon: Icons.blur_on, label: 'Dot density', onTap: (anchor) => _showDensityPopover(anchor, theme)),
        ]);
      } else if (object.type == DrawingType.text) {
        actions.addAll([
          _toolbarAction(theme: theme, icon: Icons.text_format, label: 'Text style', onTap: (anchor) => _showTextStylePopover(anchor, theme)),
          _toolbarAction(theme: theme, icon: Icons.format_size, label: 'Text size', onTap: (anchor) => _showTextSizePopover(anchor, theme)),
          _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Outline width', onTap: (anchor) => _showStrokePopover(anchor, theme, 2)),
          _toolbarAction(theme: theme, icon: Icons.format_color_text, label: 'Text color', swatch: object.color, onTap: (_) => _showColorPicker(4)),
          _toolbarAction(theme: theme, icon: Icons.border_color, label: 'Border color', swatch: object.borderColor, onTap: (_) => _showColorPicker(5)),
          _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: object.fillColor, onTap: (_) => _showColorPicker(6)),
        ]);
      }

      if (actions.isNotEmpty) actions.add(_toolbarDivider(theme));
      actions.addAll([
        _toolbarAction(theme: theme, icon: Icons.copy_all_outlined, label: 'Duplicate', onTap: (_) => _duplicateSelected()),
        _toolbarAction(theme: theme, icon: Icons.delete_outline, label: 'Delete', destructive: true, onTap: (_) => _deleteSelected()),
      ]);

      return actions;
    }

    if (_isFreehandToolName(_selectedTool)) {
      actions.addAll([
        _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 0)),
        _toolbarAction(theme: theme, icon: Icons.edit, label: 'Stroke color', swatch: _pencilColor, onTap: (_) => _showColorPicker(0)),
        if (_selectedTool == 'Pen')
          _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: _penFillColor, onTap: (_) => _showColorPicker(7)),
      ]);
    } else if (_isLineToolName(_selectedTool)) {
      actions.addAll([
        _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 1)),
        _toolbarAction(theme: theme, icon: Icons.palette_outlined, label: 'Line color', swatch: _shapeLineColor, onTap: (_) => _showColorPicker(1)),
      ]);
    } else if (_isFilledShapeToolName(_selectedTool)) {
      actions.addAll([
        _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Thickness', onTap: (anchor) => _showStrokePopover(anchor, theme, 1)),
        _toolbarAction(theme: theme, icon: Icons.border_color, label: 'Border color', swatch: _shapeBorderColor, onTap: (_) => _showColorPicker(2)),
        _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: _shapeFillColor, onTap: (_) => _showColorPicker(3)),
        if (_selectedTool == 'Dots')
          _toolbarAction(theme: theme, icon: Icons.blur_on, label: 'Dot density', onTap: (anchor) => _showDensityPopover(anchor, theme)),
      ]);
    } else if (_isTextToolName(_selectedTool)) {
      actions.addAll([
        _toolbarAction(theme: theme, icon: Icons.text_format, label: 'Text style', onTap: (anchor) => _showTextStylePopover(anchor, theme)),
        _toolbarAction(theme: theme, icon: Icons.format_size, label: 'Text size', onTap: (anchor) => _showTextSizePopover(anchor, theme)),
        _toolbarAction(theme: theme, icon: Icons.line_weight, label: 'Outline width', onTap: (anchor) => _showStrokePopover(anchor, theme, 2)),
        _toolbarAction(theme: theme, icon: Icons.format_color_text, label: 'Text color', swatch: _textColor, onTap: (_) => _showColorPicker(4)),
        _toolbarAction(theme: theme, icon: Icons.border_color, label: 'Border color', swatch: _textBorderColor, onTap: (_) => _showColorPicker(5)),
        _toolbarAction(theme: theme, icon: Icons.format_color_fill, label: 'Fill color', swatch: _textFillColor, onTap: (_) => _showColorPicker(6)),
      ]);
    }

    return actions;
  }

  Widget _buildContextualToolbar(ThemeData theme) {
    if (_activeObject == null && !_hasSelectedToolOptions()) return const SizedBox.shrink();

    final isMobile = AppResponsive.isMobileScreen(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = math.max(160.0, screenWidth - 24.0);
    final maxToolbarWidth = isMobile ? availableWidth : math.min(availableWidth, 560.0);
    final actions = _buildToolbarActionsForContext(theme);
    if (actions.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxToolbarWidth),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.62)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _contextBadge(theme),
                _toolbarDivider(theme),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobileDevice = AppResponsive.isAndroid || AppResponsive.isIOS;
    
    // Safety clamp logic to prevent crashing on tiny screens
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxPanelWidth = math.max(200.0, screenWidth * 0.5);
    final double toolbarLeftInset = (_showLeftPanel && screenWidth > 720) ? _leftPanelWidth + 20 : 12;
    final double toolbarRightInset = (widget.customRightPanel != null && screenWidth > 720) ? _rightPanelWidth + 20 : 12;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
          const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
            if (_selectedTool == 'Pen') _finalizeCurrentPreview();
          }),
        },
        child: Focus(
          focusNode: _canvasFocusNode,
          autofocus: true,
          child: Column(
            children: [
              _buildTopToolbar(theme),
              
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Container(
                                  key: _viewerKey,
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                  child: InteractiveViewer(
                                    transformationController: _transformationController,
                                    panEnabled: _selectedTool == 'Select' && _activeHandle == ResizeHandle.none,
                                    scaleEnabled: true, 
                                    minScale: _minScale,     
                                    maxScale: _maxScale, 
                                    boundaryMargin: const EdgeInsets.all(double.infinity),
                                    constrained: false, 
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
                                          
                                          child: Container(
                                            width: widget.width,  
                                            height: widget.height, 
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              boxShadow: [
                                                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, spreadRadius: 5, offset: const Offset(0, 10))
                                              ],
                                            ),
                                            child: CanvasPaper(
                                              objects: _drawingObjects, 
                                              preview: _currentPreview,
                                              backgroundImageBytes: widget.initialBackgroundImage,
                                              width: widget.width,
                                              height: widget.height,                                         
                                            ),
                                          ),
                                        ),
                                      ),
                                  ),
                                ),
                              ),

                              if (!isMobileDevice)
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

                              if (_showLeftPanel)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  bottom: 0,
                                  child: Row(
                                    children: [
                                      _buildLeftToolsPanel(theme),
                                      // 🚀 DRAG HANDLE (LEFT)
                                      _buildResizer(
                                        isLeft: true,
                                        onPanUpdate: (dx) => setState(() => _leftPanelWidth = (_leftPanelWidth + dx).clamp(200.0, maxPanelWidth))
                                      )
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // CUSTOM DATA PANEL (Sits permanently on the right, under overlays)
                        if (widget.customRightPanel != null)
                          Row(
                            children: [
                              // 🚀 DRAG HANDLE (RIGHT)
                              _buildResizer(
                                isLeft: false,
                                onPanUpdate: (dx) => setState(() => _rightPanelWidth = (_rightPanelWidth - dx).clamp(200.0, maxPanelWidth))
                              ),
                              Container(
                                width: _rightPanelWidth, 
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                ),
                                child: widget.customRightPanel!,
                              ),
                            ],
                          )
                      ],
                    ),

                    if (_activeObject != null || _hasSelectedToolOptions())
                      Positioned(
                        left: toolbarLeftInset,
                        right: toolbarRightInset,
                        bottom: 10,
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.only(bottom: 4),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _buildContextualToolbar(theme),
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
}