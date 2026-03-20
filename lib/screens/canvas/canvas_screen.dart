import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- MODELS ---
enum DrawingType { line, rect, circle, pencil, text, arrow, pen, pin }
enum ResizeHandle { none, topLeft, topCenter, topRight, centerLeft, centerRight, bottomLeft, bottomCenter, bottomRight, rotation, body, calloutKnee, calloutTip }

class DrawingObject {
  Offset start;
  Offset end;
  List<Offset>? points; 
  String? text; 
  double strokeWidth;
  Color color;      
  Color fillColor;  
  Color borderColor; // 👈 NEW: Added dedicated border color
  double opacity;   
  bool isSelected;
  DrawingType type;
  double rotation; 
  // 🔽 NEW TEXT FORMATTING PROPERTIES 🔽
  double fontSize;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrikethrough;
  bool isCallout; // 👈 NEW: Flags if this text box has a leader line

  DrawingObject({
    required this.start,
    required this.end,
    required this.type,
    this.points,
    this.text,
    this.strokeWidth = 2.0,
    this.color = Colors.black,
    this.fillColor = Colors.transparent,
    this.borderColor = Colors.transparent, // 👈 NEW: Default to transparent
    this.opacity = 1.0,
    this.isSelected = false,
    this.rotation = 0.0,// 🔽 NEW DEFAULTS 🔽
    this.fontSize = 24.0,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.isCallout = false, // 👈 NEW: Default to false
  });

  Rect get rect {
    // 🔽 ADDED DrawingType.pen HERE 🔽
    if ((type == DrawingType.pencil || type == DrawingType.pen) && points != null && points!.isNotEmpty) {
      double minX = points![0].dx;
      double maxX = points![0].dx;
      double minY = points![0].dy;
      double maxY = points![0].dy;
      for (var p in points!) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.fromPoints(start, end);
  }

  Offset get center => rect.center;

  DrawingObject copy() => DrawingObject(
        start: start,
        end: end,
        type: type,
        points: points != null ? List.from(points!) : null,
        text: text,
        strokeWidth: strokeWidth,
        color: color,
        fillColor: fillColor,
        borderColor: borderColor, // 👈 NEW: Don't forget to copy it!
        opacity: opacity,
        isSelected: isSelected,
        rotation: rotation,
        // 🔽 NEW COPY FIELDS 🔽
        fontSize: fontSize,
        isBold: isBold,
        isItalic: isItalic,
        isUnderline: isUnderline,
        isStrikethrough: isStrikethrough,
        isCallout: isCallout, // 👈 NEW: Don't forget to copy it!
      );
}

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});
  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  String _selectedTool = 'Select';

  double _pencilStrokeWidth = 2.0;
  double _shapeStrokeWidth = 2.0;
  double _textStrokeWidth = 2.0;
  
  // 1. Pencil & Pen State
  Color _pencilColor = Colors.black;
  Color _penFillColor = Colors.transparent;
  double _pencilOpacity = 1.0; 

  // 2. Shapes State (Rect, Circle, Line, Arrow)
  Color _shapeLineColor = Colors.black;
  Color _shapeBorderColor = Colors.black;
  Color _shapeFillColor = Colors.transparent;
  double _shapeOpacity = 1.0;

  // 3. Text State
  Color _textColor = Colors.black;
  Color _textBorderColor = Colors.transparent;
  Color _textFillColor = Colors.transparent;
  double _textOpacity = 1.0;

  // Text Formatting State
  double _textSize = 24.0;
  bool _textIsBold = false;
  bool _textIsItalic = false;
  bool _textIsUnderline = false;
  bool _textIsStrikethrough = false;
  bool _textIsCallout = false; // 👈 NEW: Callout mode state   
  
  List<String> _pages = ['Page 1'];
  late String _currentPage;

  List<DrawingObject> _drawingObjects = [];
  List<List<DrawingObject>> _undoStack = [];
  List<List<DrawingObject>> _redoStack = []; 

  DrawingObject? _currentPreview;
  DrawingObject? _activeObject; 
  
  ResizeHandle _activeHandle = ResizeHandle.none;
  ResizeHandle _hoveredHandle = ResizeHandle.none;
  Offset _dragOffset = Offset.zero;
  double _initialRotationAngle = 0.0;
  DateTime? _lastTapTime;
  bool _showShapeToolbar = false;
  bool _showTextToolbar = false; 
  bool _showPencilToolbar = false; // 👈 Add this new line!


  @override
  void initState() {
    super.initState();
    _currentPage = _pages.first;
  }

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
                    text: TextSpan(
                      text: controller.text,
                      style: TextStyle(fontSize: _textStrokeWidth * 10),
                    ),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: 500);

                  final calculatedSize = Offset(textPainter.width + 20, textPainter.height + 20);

                  Color initialFill = _textFillColor;
                  Color initialBorder = _textBorderColor;
                  
                  if (isCallout) {
                    if (initialFill == Colors.transparent) initialFill = const Color(0xFF7F4A46);
                    if (initialBorder == Colors.transparent) initialBorder = Colors.redAccent;
                  }

                  if (existingObject != null) {
                    existingObject.text = controller.text;
                    existingObject.end = existingObject.start + calculatedSize;
                  } else {
                    final textObj = DrawingObject(
                      start: position,
                      end: position + calculatedSize,
                      type: DrawingType.text,
                      text: controller.text,
                      color: _textColor,         
                      fillColor: initialFill,   
                      borderColor: initialBorder, 
                      opacity: _textOpacity,
                      isSelected: true,
                      strokeWidth: _textStrokeWidth,
                      fontSize: _textSize,
                      isBold: _textIsBold,
                      isItalic: _textIsItalic,
                      isUnderline: _textIsUnderline,
                      isStrikethrough: _textIsStrikethrough,
                      isCallout: isCallout, // 👈 Uses the passed parameter
                      points: isCallout ? [
                        position + Offset(calculatedSize.dx / 2, calculatedSize.dy + 30), 
                        position + Offset(calculatedSize.dx / 2 + 40, calculatedSize.dy + 70) 
                      ] : null,
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
      case ResizeHandle.topLeft:
      case ResizeHandle.bottomRight: return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeHandle.topRight:
      case ResizeHandle.bottomLeft: return SystemMouseCursors.resizeUpRightDownLeft;
      case ResizeHandle.topCenter:
      case ResizeHandle.bottomCenter: return SystemMouseCursors.resizeUpDown;
      case ResizeHandle.centerLeft:
      case ResizeHandle.centerRight: return SystemMouseCursors.resizeLeftRight;
      case ResizeHandle.rotation: return SystemMouseCursors.grab;
      case ResizeHandle.body: return SystemMouseCursors.move;
      case ResizeHandle.calloutKnee:
      case ResizeHandle.calloutTip: return SystemMouseCursors.move;
      default: return SystemMouseCursors.basic;
    }
  }

  ResizeHandle _getHitHandle(Offset p, DrawingObject obj) {
    const double hSize = 25.0; // Tip: Increase this to 40.0 for better touch device support!
    final localP = _toLocalSpace(p, obj);
    final r = obj.rect;

    if (obj.isSelected) {
      // 🔽 NEW: Allow grabbing the Callout Arrow handles 🔽
      if (obj.type == DrawingType.text && obj.isCallout && obj.points != null && obj.points!.length >= 2) {
        if ((localP - obj.points![0]).distance < hSize) return ResizeHandle.calloutKnee;
        if ((localP - obj.points![1]).distance < hSize) return ResizeHandle.calloutTip;
      }
      
      Offset rotPos = Offset(r.topCenter.dx, r.topCenter.dy - 40);
      if ((localP - rotPos).distance < hSize) return ResizeHandle.rotation;

      // 🔽 EXCLUDE PEN AND PENCIL FROM RESIZE HANDLES 🔽
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
    
    // 🔽 LINE-BASED HIT DETECTION 🔽
    if (obj.type == DrawingType.line) {
      if (_distToSegment(localP, obj.start, obj.end) < 15) return ResizeHandle.body;
    } 
    // Both Pencil and Pen use line-segment distance for selection!
    else if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null) {
      for (int i = 0; i < obj.points!.length - 1; i++) {
        // Distance check threshold is 15px. Click within 15px of any line to select.
        if (_distToSegment(localP, obj.points![i], obj.points![i+1]) < 15) return ResizeHandle.body;
      }
      // Optional: If the pen shape has a solid fill, also allow clicking inside it
      if (obj.fillColor != Colors.transparent && r.contains(localP)) return ResizeHandle.body;
    } else {
      if (r.inflate(5).contains(localP)) return ResizeHandle.body;
    }
    return ResizeHandle.none;
  }

  void _handlePointerDown(PointerDownEvent details) {
    final pos = details.localPosition;
    final now = DateTime.now();

    setState(() {
      if (_selectedTool == 'Text' || _selectedTool == 'Callout') {
        _showTextDialog(position: pos, isCallout: _selectedTool == 'Callout');
      } else if (_selectedTool == 'Eraser') {
        _saveSnapshot();
        _drawingObjects.removeWhere((obj) => _getHitHandle(pos, obj) != ResizeHandle.none);
      } else if (_selectedTool == 'Pen') {
        if (_currentPreview == null) {
          // 1st Click: Start a new Pen shape
          _currentPreview = DrawingObject(
            start: pos, end: pos, type: DrawingType.pen,
            points: [pos, pos], 
            strokeWidth: _pencilStrokeWidth, 
            color: _pencilColor,
            fillColor: _penFillColor, 
            opacity: _pencilOpacity, // 👈 Dedicated Pen Opacity
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
                           (_selectedTool == 'Pin') ? DrawingType.pin : DrawingType.line; // 👈 Added Pin routing
        
        List<Offset>? pts = (type == DrawingType.pencil) ? [pos] : null;
        
        Color objColor = Colors.black;
        Color objFill = Colors.transparent;
        double objOpacity = 1.0; 
        double objStroke = 2.0; 

        if (type == DrawingType.pencil) {
          objColor = _pencilColor; objFill = _penFillColor; objOpacity = _pencilOpacity; objStroke = _pencilStrokeWidth; 
        } else if (type == DrawingType.pin) {
          // 🔽 FORCE CLASSIC MAP PIN COLORS 🔽
          objColor = Colors.red[800]!; // Dark red outline
          objFill = Colors.red;        // Bright red fill
          objOpacity = 1.0;  
          objStroke = 2.0;
        } else if (type == DrawingType.line || type == DrawingType.arrow) {
          objColor = _shapeLineColor; objOpacity = _shapeOpacity; objStroke = _shapeStrokeWidth;  
        } else if (type == DrawingType.rect || type == DrawingType.circle) { 
          objColor = _shapeBorderColor; objFill = _shapeFillColor; objOpacity = _shapeOpacity; objStroke = _shapeStrokeWidth;  
        }

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type, points: pts,
          strokeWidth: objStroke, color: objColor, fillColor: objFill, opacity: objOpacity,
        );
      } else {
        // ... (Keep your existing Select Tool resizing/hit-testing logic here) ...
        _activeHandle = ResizeHandle.none;
        DrawingObject? hitObj;
        ResizeHandle hitHandle = ResizeHandle.none;

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
    final pos = details.localPosition;
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
          _activeObject!.points![0] = pos; // Move the knee independently
        } else if (_activeHandle == ResizeHandle.calloutTip) {
          _activeObject!.points![1] = pos; // Move the tip independently
        } else if (_activeHandle == ResizeHandle.body) {
          Offset delta = _activeObject!.end - _activeObject!.start;
          Offset moveDelta = (pos - _dragOffset) - _activeObject!.start;
          _activeObject!.start = pos - _dragOffset;
          _activeObject!.end = _activeObject!.start + delta;
          
          if (_activeObject!.type == DrawingType.pencil || _activeObject!.type == DrawingType.pen) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + moveDelta).toList();
          }
          // 🔽 NEW: Move the arrow points when dragging the whole Text box 🔽
          if (_activeObject!.type == DrawingType.text && _activeObject!.isCallout && _activeObject!.points != null) {
            _activeObject!.points = _activeObject!.points!.map((p) => p + moveDelta).toList();
          }
        } else {
          // Resize logic - only reachable if not Pencil
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
      // 🔽 Block Pen from finishing when releasing the mouse! 🔽
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

  double _distToSegment(Offset p, Offset v, Offset w) {
    double l2 = (v - w).distanceSquared;
    if (l2 == 0) return (p - v).distance;
    double t = ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    return (p - Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy))).distance;
  }

  void _showColorPicker(int mode) {
    _saveSnapshot(); 

    final List<Color> pickerPresets = [
      const Color(0xFFFF5252), const Color(0xFFFF9800), const Color(0xFFFFEB3B), 
      const Color(0xFFCDDC39), const Color(0xFF4CAF50), const Color(0xFF009688), 
      const Color(0xFF00BCD4), const Color(0xFF03A9F4), const Color(0xFF2196F3), 
      const Color(0xFF3F51B5), const Color(0xFF9C27B0), const Color(0xFFE91E63), 
      const Color(0xFF795548), const Color(0xFF9E9E9E), const Color(0xFF000000), 
      const Color(0xFFFFFFFF),
    ];

    Color currentColor;
    double currentOpacity = 1.0;

    // Route the Colors AND the Opacities based on the mode
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
    double localOpacity = currentOpacity; // 👈 Set the slider to the correct tool's opacity

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            void updateColor(Color newColor) {
              setDialogState(() => hsvColor = HSVColor.fromColor(newColor));
              setState(() {
                if (mode == 0) {
                  _pencilColor = newColor;
                  if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) _activeObject!.color = newColor;
                } else if (mode == 1) {
                  _shapeLineColor = newColor;
                  if (_activeObject?.type == DrawingType.line || _activeObject?.type == DrawingType.arrow) _activeObject!.color = newColor;
                } else if (mode == 2) {
                  _shapeBorderColor = newColor;
                  if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) _activeObject!.color = newColor;
                } else if (mode == 3) {
                  _shapeFillColor = newColor;
                  // ONLY applies to Rect and Circle
                  if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) {
                    _activeObject!.fillColor = newColor;
                  }
                } else if (mode == 4) {
                  _textColor = newColor;
                  if (_activeObject?.type == DrawingType.text) _activeObject!.color = newColor;
                } else if (mode == 5) {
                  _textBorderColor = newColor;
                  if (_activeObject?.type == DrawingType.text) _activeObject!.borderColor = newColor;
                } else if (mode == 6) {
                  _textFillColor = newColor;
                  if (_activeObject?.type == DrawingType.text) _activeObject!.fillColor = newColor;
                } else if (mode == 7) {
                  _penFillColor = newColor;
                  // ONLY applies to Pen and Pencil
                  if (_activeObject?.type == DrawingType.pen || _activeObject?.type == DrawingType.pencil) {
                    _activeObject!.fillColor = newColor;
                  }
                }
              });
            }

            String colorToHex(Color c) => c == Colors.transparent ? "NONE" : '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

            const double squareWidth = 240.0;
            const double squareHeight = 200.0;
            
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
                        decoration: BoxDecoration(
                          color: showOpacity ? hsvColor.toColor().withOpacity(localOpacity) : hsvColor.toColor(), 
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
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
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(colors: [Colors.white, hsvColor.withSaturation(1).withValue(1).toColor()]),
                          ),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Colors.transparent, Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                            ),
                          ),
                        ),
                        Positioned(
                          left: (hsvColor.saturation * squareWidth) - 8,
                          top: ((1 - hsvColor.value) * squareHeight) - 8,
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    width: 240, height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red]),
                    ),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 12, activeTrackColor: Colors.transparent, inactiveTrackColor: Colors.transparent, thumbColor: Colors.white),
                      child: Slider(value: hsvColor.hue, min: 0, max: 360, onChanged: (v) => updateColor(hsvColor.withHue(v).toColor())),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (showOpacity) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Opacity", style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                        Text("${(localOpacity * 100).toInt()}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 240, height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        gradient: LinearGradient(colors: [Colors.transparent, hsvColor.toColor()]),
                      ),
                      child: Slider(
                        value: localOpacity, min: 0.0, max: 1.0,
                        onChanged: (v) {
                          setDialogState(() => localOpacity = v);
                          setState(() { 
                            if (mode == 3) {
                              _shapeOpacity = v;
                              if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle) _activeObject!.opacity = v;
                            } else if (mode == 6) {
                              _textOpacity = v;
                              if (_activeObject?.type == DrawingType.text) _activeObject!.opacity = v;
                            } else if (mode == 7) {
                              _pencilOpacity = v;
                              if (_activeObject?.type == DrawingType.pen || _activeObject?.type == DrawingType.pencil) _activeObject!.opacity = v;
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
                          GestureDetector(
                            onTap: () => updateColor(Colors.transparent),
                            child: CircleAvatar(radius: 14, backgroundColor: Colors.grey[200], child: const Icon(Icons.block, size: 16, color: Colors.red)),
                          ),
                        ...pickerPresets.map((color) => GestureDetector(
                          onTap: () => updateColor(color),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle,
                              border: Border.all(color: hsvColor.toColor() == color ? Colors.blue : (color == Colors.white ? Colors.grey[300]! : Colors.transparent), width: 2),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            );
          },
        );
      },
    );
  }
  
Widget _mainMenuToggle({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool hasDropdown,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
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
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                ] else ...[
                  // Adds a tiny bit of invisible spacing so the "Select" icon aligns perfectly with dropdowns
                  const SizedBox(width: 5), 
                ]
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): _deleteSelected,
        // 🔽 Press ESC to finalize the Pen tool instantly 🔽
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
          if (_selectedTool == 'Pen') _finalizeCurrentPreview();
        }),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Column(
            children: [
              _buildTopNav(theme),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _buildFullWidthToolbar(theme),
                          Expanded(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return MouseRegion(
                                        cursor: _getCursor(_hoveredHandle),
                                        onHover: (d) {
                                          // 🔽 Live Preview Line for the Pen Tool 🔽
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
                                          onPointerMove: (details) => _handlePointerMove(details, constraints),
                                          onPointerUp: _handlePointerUp,
                                          child: Container(
                                            width: constraints.maxWidth, 
                                            height: constraints.maxHeight,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
                                            ),
                                            child: CanvasPaper(objects: _drawingObjects, preview: _currentPreview),
                                          ),
                                        ),
                                      );
                                    }
                                  ),
                                ),

                                // 1. The Floating Pencil Menu 🎈
                                if (_showPencilToolbar)
                                  Positioned(
                                    top: 8,     
                                    left: 80,  // Aligns roughly under the Pencil toggle
                                    child: _buildFloatingPencilMenu(theme),
                                  ),
                                
                                // 2. The Floating Shape Menu 🎈
                                if (_showShapeToolbar)
                                  Positioned(
                                    top: 8,     
                                    left: 140,  
                                    child: _buildFloatingShapeMenu(theme),
                                  ),

                                // 3. The Floating Text Menu 🎈
                                if (_showTextToolbar)
                                  Positioned(
                                    top: 8,     
                                    left: 210, // Shifted slightly to align under the Text toggle
                                    child: _buildFloatingTextMenu(theme),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (size.width > 1200) _buildRightPanel(theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNav(ThemeData theme) {
    return Container(
      height: 64, padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)))),
      child: Row(children: [
        // const Icon(Icons.arrow_back), const SizedBox(width: 15),
        Text("Canvas", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        _buildPageSelector(theme), const SizedBox(width: 20), const Icon(Icons.save_outlined),
      ]),
    );
  }

  bool _isShapeSelected(String tool) {
    return ['Rect', 'Circle', 'Line', 'Arrow'].contains(tool);
  }

  IconData _getShapeIcon(String tool) {
    switch (tool) {
      case 'Rect': return Icons.crop_square;
      case 'Circle': return Icons.panorama_fish_eye;
      case 'Line': return Icons.show_chart;
      case 'Arrow': return Icons.arrow_outward;
      default: return Icons.crop_square; 
    }
  }

  Widget _buildFloatingPencilMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DRAW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            _toolIcon(Icons.edit, "Pencil", theme),
            _toolIcon(Icons.polyline, "Pen", theme), 
            _vDiv(theme),
            const Text("PROPERTIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            
            _colorButton("Color", _pencilColor, 0),     // 👈 MUST BE MODE 0
            const SizedBox(width: 12),
            _colorButton("Fill", _penFillColor, 7),     // 👈 MUST BE MODE 7
            
            _vDiv(theme), _buildStrokeSlider(theme, 0), 
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingTextMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔽 THE NEW SUB-TOOL SELECTORS 🔽
            const Text("TOOLS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            _toolIcon(Icons.title, "Text", theme),
            _toolIcon(Icons.chat_bubble_outline, "Callout", theme),
            
            _vDiv(theme),
            const Text("FORMAT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            
            // 🔽 FORMATTING 🔽
            _formatToggle(Icons.format_bold, _textIsBold, () => setState(() {
              _textIsBold = !_textIsBold; if (_activeObject?.type == DrawingType.text) _activeObject!.isBold = _textIsBold;
            }), theme),
            _formatToggle(Icons.format_italic, _textIsItalic, () => setState(() {
              _textIsItalic = !_textIsItalic; if (_activeObject?.type == DrawingType.text) _activeObject!.isItalic = _textIsItalic;
            }), theme),
            _formatToggle(Icons.format_underlined, _textIsUnderline, () => setState(() {
              _textIsUnderline = !_textIsUnderline; if (_activeObject?.type == DrawingType.text) _activeObject!.isUnderline = _textIsUnderline;
            }), theme),
            _formatToggle(Icons.format_strikethrough, _textIsStrikethrough, () => setState(() {
              _textIsStrikethrough = !_textIsStrikethrough; if (_activeObject?.type == DrawingType.text) _activeObject!.isStrikethrough = _textIsStrikethrough;
            }), theme),
            
            _vDiv(theme),
            _buildTextSizeSlider(theme), 
            _vDiv(theme),
            
            // 🔽 COLORS & BORDER 🔽
            _colorButton("Text", _textColor, 4),         
            const SizedBox(width: 12),
            _colorButton("Border", _textBorderColor, 5), 
            const SizedBox(width: 12),
            _colorButton("Fill", _textFillColor, 6),     
            _vDiv(theme),
            _buildStrokeSlider(theme, 2), 
          ],
        ),
      ),
    );
  }
  
  Widget _buildFloatingShapeMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("SHAPES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            _toolIcon(Icons.crop_square, "Rect", theme),
            _toolIcon(Icons.panorama_fish_eye, "Circle", theme),
            _toolIcon(Icons.show_chart, "Line", theme),
            _toolIcon(Icons.arrow_outward, "Arrow", theme),
            _toolIcon(Icons.chat_bubble_outline, "Callout", theme), // 👈 NEW
            _vDiv(theme),
            const Text("PROPERTIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(width: 8),
            
            _colorButton("Color", _shapeLineColor, 1),   // 👈 MUST BE MODE 1
            const SizedBox(width: 12),
            _colorButton("Border", _shapeBorderColor, 2),// 👈 MUST BE MODE 2
            const SizedBox(width: 12),
            _colorButton("Fill", _shapeFillColor, 3),    // 👈 MUST BE MODE 3
            
            _vDiv(theme), _buildStrokeSlider(theme, 1), 
          ],
        ),
      ),
    );
  }
  
  Widget _buildFullWidthToolbar(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: theme.colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [

            // 🔽 1. SELECT TOOL (Closes everything) 🔽
            _mainMenuToggle(
              icon: Icons.near_me,
              label: "Select",
              isActive: _selectedTool == 'Select' && !_showPencilToolbar && !_showShapeToolbar && !_showTextToolbar,
              hasDropdown: false,
              theme: theme,
              onTap: () => setState(() {
                _selectedTool = 'Select';
                _showPencilToolbar = false;
                _showShapeToolbar = false;
                _showTextToolbar = false;
              }),
            ),

            // 🔽 2. DRAW TOGGLE 🔽
            _mainMenuToggle(
              icon: _selectedTool == 'Pen' ? Icons.polyline : Icons.edit,
              label: _selectedTool == 'Pen' ? "Pen" : "Pencil",
              isActive: _showPencilToolbar || _selectedTool == 'Pencil' || _selectedTool == 'Pen',
              hasDropdown: true,
              theme: theme,
              onTap: () => setState(() {
                _showPencilToolbar = !_showPencilToolbar;
                if (_showPencilToolbar) {
                  _showShapeToolbar = false; // Strictly close others
                  _showTextToolbar = false;
                  if (_selectedTool != 'Pencil' && _selectedTool != 'Pen') _selectedTool = 'Pencil';
                } else {
                  _selectedTool = 'Select'; // Revert to select if closed
                }
              }),
            ),

            // 🔽 3. SHAPES TOGGLE 🔽
            _mainMenuToggle(
              icon: _getShapeIcon(_selectedTool),
              label: "Shapes",
              isActive: _showShapeToolbar || _isShapeSelected(_selectedTool),
              hasDropdown: true,
              theme: theme,
              onTap: () => setState(() {
                _showShapeToolbar = !_showShapeToolbar;
                if (_showShapeToolbar) {
                  _showPencilToolbar = false; // Strictly close others
                  _showTextToolbar = false;
                  if (!_isShapeSelected(_selectedTool)) _selectedTool = 'Rect';
                } else {
                  _selectedTool = 'Select'; // Revert to select if closed
                }
              }),
            ),

            // 🔽 4. TEXT/CALLOUT TOGGLE 🔽
            _mainMenuToggle(
              icon: _selectedTool == 'Callout' ? Icons.chat_bubble_outline : Icons.title,
              label: _selectedTool == 'Callout' ? "Callout" : "Text",
              isActive: _showTextToolbar || _selectedTool == 'Text' || _selectedTool == 'Callout',
              hasDropdown: true,
              theme: theme,
              onTap: () => setState(() {
                _showTextToolbar = !_showTextToolbar;
                if (_showTextToolbar) {
                  _showPencilToolbar = false; 
                  _showShapeToolbar = false;
                  if (_selectedTool != 'Text' && _selectedTool != 'Callout') {
                    _selectedTool = 'Text'; // Default to Text when opening
                  }
                } else {
                  _selectedTool = 'Select'; 
                }
              }),
            ),

            // 🔽 5. PIN MARKER TOGGLE 🔽
            _mainMenuToggle(
              icon: Icons.place,
              label: "Pin",
              isActive: _selectedTool == 'Pin',
              hasDropdown: false,
              theme: theme,
              onTap: () => setState(() {
                _showPencilToolbar = false; 
                _showShapeToolbar = false;
                _showTextToolbar = false;
                _selectedTool = 'Pin';
              }),
            ),

            _vDiv(theme),
            _utilityIcon(Icons.undo, "Undo", theme, _undo, isEnabled: _undoStack.isNotEmpty),
            _utilityIcon(Icons.redo, "Redo", theme, _redo, isEnabled: _redoStack.isNotEmpty),
            _utilityIcon(Icons.delete_outline, "Delete", theme, _deleteSelected, isDestructive: true, isEnabled: _activeObject != null),
          ],
        ),
      ),
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
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
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
        Expanded(
          child: Slider(
            value: _textSize, min: 10, max: 120, 
            onChanged: (v) => setState(() {
              _textSize = v;
              // 🔽 FIXED: We only need to check for DrawingType.text! 🔽
              if (_activeObject?.type == DrawingType.text) {
                _activeObject!.fontSize = v;
              }
            })
          )
        ),
      ]),
    );
  }

  Widget _buildStrokeSlider(ThemeData theme, int mode) {
    double currentWidth;
    switch (mode) {
      case 0: currentWidth = _pencilStrokeWidth; break; // Pencil/Pen
      case 1: currentWidth = _shapeStrokeWidth; break;  // Shapes
      case 2: currentWidth = _textStrokeWidth; break;   // Text Border
      default: currentWidth = 2.0;
    }

    return SizedBox(
      width: 170, // Slightly wider to fit the label
      child: Row(children: [
        // 🔽 The new "Border" label you requested 🔽
        const Text("Border: ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        SizedBox(width: 28, child: Text("${currentWidth.toInt()}px", style: theme.textTheme.labelSmall)),
        Expanded(
          child: Slider(
            value: currentWidth, min: 1, max: 20, 
            onChanged: (v) => setState(() {
              if (mode == 0) {
                _pencilStrokeWidth = v;
                if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) _activeObject!.strokeWidth = v;
              } else if (mode == 1) {
                _shapeStrokeWidth = v;
                if (_activeObject?.type == DrawingType.rect || _activeObject?.type == DrawingType.circle || _activeObject?.type == DrawingType.line || _activeObject?.type == DrawingType.arrow) _activeObject!.strokeWidth = v;
              } else if (mode == 2) {
                _textStrokeWidth = v;
                if (_activeObject?.type == DrawingType.text) _activeObject!.strokeWidth = v;
              }
            })
          )
        ),
      ]),
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

  Widget _buildPageSelector(ThemeData theme) {
    return DropdownButton<String>(value: _currentPage, items: _pages.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _currentPage = v!));
  }

  Widget _utilityIcon(IconData icon, String msg, ThemeData theme, VoidCallback onTap, {bool isDestructive = false, bool isEnabled = true}) {
    return IconButton(
      onPressed: isEnabled ? onTap : null, 
      icon: Icon(icon, color: isEnabled ? (isDestructive ? Colors.red : theme.colorScheme.onSurface) : theme.disabledColor)
    );
  }

  Widget _vDiv(ThemeData theme) => VerticalDivider(width: 32, indent: 10, endIndent: 10, color: theme.colorScheme.outlineVariant);

  Widget _buildRightPanel(ThemeData theme) => Container(width: 240, color: theme.colorScheme.surfaceContainer, child: const Center(child: Text("Properties")));

  void _finalizeCurrentPreview() {
    if (_currentPreview != null) {
      _saveSnapshot();
      for (var obj in _drawingObjects) obj.isSelected = false;
      _currentPreview!.isSelected = true;

      // If it's a Pen and it has fewer than 3 points, it's just a dot/line, so discard it.
      if (_currentPreview!.type == DrawingType.pen && _currentPreview!.points!.length < 3) {
        _currentPreview = null;
        return;
      }

      // Remove the floating "mouse preview" point from the end of the array
      if (_currentPreview!.type == DrawingType.pen) {
        _currentPreview!.points!.removeLast();
      }

      _drawingObjects.add(_currentPreview!);
      _activeObject = _currentPreview;
      _selectedTool = 'Select';
      _currentPreview = null;
    }
  }
}

// --- PAINTERS ---
class CanvasPaper extends StatelessWidget {
  final List<DrawingObject> objects;
  final DrawingObject? preview;
  const CanvasPaper({super.key, required this.objects, this.preview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.hardEdge, 
      decoration: BoxDecoration(color: theme.brightness == Brightness.dark ? const Color(0xFF1C252E) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: CustomPaint(size: Size.infinite, painter: MainPainter(context, objects, preview)),
    );
  }
}

class MainPainter extends CustomPainter {
  final BuildContext context;
  final List<DrawingObject> objects;
  final DrawingObject? preview;
  MainPainter(this.context, this.objects, this.preview);

  @override
  void paint(ui.Canvas canvas, Size size) {
    final theme = Theme.of(context);
    final gridPaint = Paint()..color = theme.colorScheme.onSurface.withOpacity(0.05);
    for (double i = 0; i < size.width; i += 25) canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 25) canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    void drawShape(DrawingObject obj) {
      canvas.save();
      canvas.translate(obj.center.dx, obj.center.dy);
      canvas.rotate(obj.rotation);
      canvas.translate(-obj.center.dx, -obj.center.dy);

      final Rect rect = obj.rect;
      
      if (obj.type == DrawingType.text && obj.text != null) {        
        // 1. Text Auto-Height Calculation
        double fontSize = obj.fontSize ?? 24.0;
        if (fontSize < 1) fontSize = 1;

        final textPainter = TextPainter(
          text: TextSpan(text: obj.text, style: TextStyle(color: obj.color, fontSize: fontSize, fontWeight: obj.isBold ? FontWeight.bold : FontWeight.normal, fontStyle: obj.isItalic ? FontStyle.italic : FontStyle.normal)),
          textDirection: TextDirection.ltr, textAlign: TextAlign.left,
        );
        
        double availableWidth = rect.width > 20 ? rect.width - 20 : 10;
        textPainter.layout(maxWidth: availableWidth);
        double requiredHeight = textPainter.height + 20;
        
        // 🔽 FIXED: Smoothly snaps the height without moving your arrow points! 🔽
        if (obj.end.dy >= obj.start.dy) {
          obj.end = Offset(obj.end.dx, obj.start.dy + requiredHeight);
        } else {
          obj.start = Offset(obj.start.dx, obj.end.dy - requiredHeight);
        }
        
        final updatedRect = obj.rect;
        final borderPaint = Paint()..color = obj.borderColor..strokeWidth = obj.strokeWidth..style = PaintingStyle.stroke;

        // 2. 🌟 DRAW THE LEADER LINE IF IT'S A CALLOUT 🌟
        if (obj.isCallout && obj.points != null && obj.points!.length >= 2) {
          Offset knee = obj.points![0];
          Offset tip = obj.points![1];

          // Dynamically attach to the nearest edge
          Offset attach = Offset(updatedRect.center.dx, updatedRect.bottom); 
          if (knee.dy < updatedRect.top) attach = Offset(updatedRect.center.dx, updatedRect.top);
          else if (knee.dy > updatedRect.bottom) attach = Offset(updatedRect.center.dx, updatedRect.bottom);
          else if (knee.dx < updatedRect.left) attach = Offset(updatedRect.left, updatedRect.center.dy);
          else if (knee.dx > updatedRect.right) attach = Offset(updatedRect.right, updatedRect.center.dy);

          Path leaderPath = Path()..moveTo(attach.dx, attach.dy)..lineTo(knee.dx, knee.dy)..lineTo(tip.dx, tip.dy);
          canvas.drawPath(leaderPath, borderPaint);

          double angle = math.atan2(tip.dy - knee.dy, tip.dx - knee.dx);
          Path arrow = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - 15 * math.cos(angle - math.pi / 6), tip.dy - 15 * math.sin(angle - math.pi / 6))
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - 15 * math.cos(angle + math.pi / 6), tip.dy - 15 * math.sin(angle + math.pi / 6));
          canvas.drawPath(arrow, borderPaint);
        }

        // 3. Draw Background Box & Border
        if (obj.fillColor != Colors.transparent) canvas.drawRect(updatedRect, Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill);
        if (obj.borderColor != Colors.transparent) canvas.drawRect(updatedRect, borderPaint);
        
        // 4. Draw Text
        textPainter.paint(canvas, updatedRect.topLeft + const Offset(10, 10));

        // 5. 🌟 STANDARD RESIZE DOTS FOR CALLOUT ARROW 🌟
        if (obj.isSelected && obj.isCallout && obj.points != null) {
          Paint hP = Paint()..color = Colors.blue; 
          Paint wP = Paint()..color = Colors.white; 
          canvas.drawCircle(obj.points![0], 7, wP); canvas.drawCircle(obj.points![0], 5, hP); // Knee
          canvas.drawCircle(obj.points![1], 7, wP); canvas.drawCircle(obj.points![1], 5, hP); // Tip
        }
      
      } else if (obj.type == DrawingType.pin) {
          // 📍 THE MAP PIN PATH
          double w = rect.width;
          double h = rect.height;
          double r = w / 2; // Radius of the top curve
          
          Path pinPath = Path();
          pinPath.moveTo(rect.center.dx, rect.bottom); // Start at the pointy bottom tip
          // Curve up the left side
          pinPath.quadraticBezierTo(rect.left, rect.bottom - h * 0.4, rect.left, rect.top + r);
          // Draw the perfect semi-circle on top
          pinPath.arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r), clockwise: true);
          // Curve down the right side back to the tip
          pinPath.quadraticBezierTo(rect.right, rect.bottom - h * 0.4, rect.center.dx, rect.bottom);
          pinPath.close();

          final borderPaint = Paint()
            ..color = obj.color.withOpacity(obj.opacity)
            ..strokeWidth = obj.strokeWidth
            ..style = PaintingStyle.stroke;

          // Draw the solid red body
          if (obj.fillColor != Colors.transparent) {
            canvas.drawPath(pinPath, Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill);
          }
          // Draw the dark red border
          canvas.drawPath(pinPath, borderPaint);
          
          // Draw the classic white hole in the center of the top circle
          canvas.drawCircle(Offset(rect.center.dx, rect.top + r), r * 0.35, Paint()..color = Colors.white..style = PaintingStyle.fill);
          canvas.drawCircle(Offset(rect.center.dx, rect.top + r), r * 0.35, borderPaint);
        
      } else {
        if (obj.type != DrawingType.line && obj.type != DrawingType.pencil && obj.fillColor != Colors.transparent) {
          final fillPaint = Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill;
          if (obj.type == DrawingType.rect) canvas.drawRect(rect, fillPaint);
          if (obj.type == DrawingType.circle) canvas.drawOval(rect, fillPaint);
        }

        final strokePaint = Paint()
          ..color = obj.color 
          ..strokeWidth = obj.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null && obj.points!.isNotEmpty) {
          Path path = Path();
          path.moveTo(obj.points![0].dx, obj.points![0].dy);
          for (var i = 1; i < obj.points!.length; i++) {
            path.lineTo(obj.points![i].dx, obj.points![i].dy);
          }
          
          // 🔽 THE BUG FIX: Force the fill path to close! 🔽
          if (obj.fillColor != Colors.transparent && obj.points!.length > 2) {
             Path fillPath = Path.from(path); // Create a copy
             fillPath.close(); // Force it to close so Flutter knows it's a solid shape
             
             final fillPaint = Paint()
               ..color = obj.fillColor.withOpacity(obj.opacity)
               ..style = PaintingStyle.fill;
             canvas.drawPath(fillPath, fillPaint);
          }
          
          canvas.drawPath(path, strokePaint); // Draw the stroke on top

          // Draw the close node indicator for Pen
          if (obj == preview && obj.type == DrawingType.pen) {
            canvas.drawCircle(obj.points![0], 6, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2);
          }
        } else if (obj.type == DrawingType.line) {
          canvas.drawLine(obj.start, obj.end, strokePaint);
        } else if (obj.type == DrawingType.arrow) {
          // 1. Draw the main line
          canvas.drawLine(obj.start, obj.end, strokePaint);
          
          // 2. Calculate the arrowhead angle and draw it
          const double arrowLength = 15.0;
          const double arrowAngle = math.pi / 6; // 30 degrees
          double angle = math.atan2(obj.end.dy - obj.start.dy, obj.end.dx - obj.start.dx);

          Offset p1 = Offset(
            obj.end.dx - arrowLength * math.cos(angle - arrowAngle),
            obj.end.dy - arrowLength * math.sin(angle - arrowAngle),
          );
          Offset p2 = Offset(
            obj.end.dx - arrowLength * math.cos(angle + arrowAngle),
            obj.end.dy - arrowLength * math.sin(angle + arrowAngle),
          );

          Path arrowPath = Path()
            ..moveTo(obj.end.dx, obj.end.dy)
            ..lineTo(p1.dx, p1.dy)
            ..moveTo(obj.end.dx, obj.end.dy)
            ..lineTo(p2.dx, p2.dy);
          
          canvas.drawPath(arrowPath, strokePaint);
          
        } else if (obj.type == DrawingType.rect) {
          canvas.drawRect(rect, strokePaint);
        } else if (obj.type == DrawingType.circle) {
          canvas.drawOval(rect, strokePaint);
        }
      }

      if (obj.isSelected) {
        final hP = Paint()..color = Colors.blue;
        final wP = Paint()..color = Colors.white;
        
        // Rotation handle remains for all
        Offset rotPos = Offset(rect.topCenter.dx, rect.topCenter.dy - 40);
        canvas.drawLine(rect.topCenter, rotPos, hP..strokeWidth = 1);
        canvas.drawCircle(rotPos, 12, wP);
        canvas.drawCircle(rotPos, 10, hP);

        final rotIcon = TextPainter(
          text: const TextSpan(text: '\u21BB', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'MaterialIcons')),
          textDirection: TextDirection.ltr,
        );
        rotIcon.layout();
        rotIcon.paint(canvas, rotPos - Offset(rotIcon.width / 2, rotIcon.height / 2));

        // 🔽 HIDE RESIZE DOTS FOR PEN AND PENCIL 🔽
        if (obj.type != DrawingType.pencil && obj.type != DrawingType.pen) {
          final points = [rect.topLeft, rect.topCenter, rect.topRight, rect.centerLeft, rect.centerRight, rect.bottomLeft, rect.bottomCenter, rect.bottomRight];
          for (var p in points) { 
            canvas.drawCircle(p, 7, wP); 
            canvas.drawCircle(p, 5, hP); 
          }
        } else {
          // Draw just a simple bounding box to show it's selected
          canvas.drawRect(rect.inflate(4), hP..style = PaintingStyle.stroke..strokeWidth = 1);
        }
      }
      canvas.restore();
    }
    
    for (var obj in objects) drawShape(obj);
    if (preview != null) drawShape(preview!);
  }
  @override bool shouldRepaint(covariant MainPainter oldDelegate) => true;
}