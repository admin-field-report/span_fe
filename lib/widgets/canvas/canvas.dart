import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import 'models/canvas_models.dart';
import 'widgets/canvas_painter.dart';
import 'widgets/property_panel.dart';

class Canvas extends StatefulWidget {
  final Uint8List? initialBackgroundImage;

  const Canvas({
    super.key,
    this.initialBackgroundImage,
  });

  @override
  State<Canvas> createState() => CanvasState();
}

class CanvasState extends State<Canvas> {
  final FocusNode _canvasFocusNode = FocusNode();
  
  bool _isFullScreen = false;

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
  bool _showBrickToolbar = false;

  double _patternDensity = 20.0; 

  // Local Data Stores
  List<DrawingObject> _drawingObjects = [];
  final List<List<DrawingObject>> _undoStack = [];
  final List<List<DrawingObject>> _redoStack = [];

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); 
    super.dispose();
  }

  void applyExternalToolConfig(String tool, double stroke, Color color, Color fill, double opacity) {
    setState(() {
      _selectedTool = tool;
      
      // 🚀 Deselect active object when changed externally
      for (var obj in _drawingObjects) {
        obj.isSelected = false;
      }
      _activeObject = null;
      
      // Apply to Pencil/Pen
      _pencilStrokeWidth = stroke;
      _pencilColor = color;
      _penFillColor = fill;
      _pencilOpacity = opacity;

      // Apply to Shapes
      _shapeStrokeWidth = stroke;
      _shapeLineColor = color;
      _shapeBorderColor = color;
      _shapeFillColor = fill;
      _shapeOpacity = opacity;

      // Apply to Text
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
                    if (initialFill == Colors.transparent) initialFill = const Color(0xFFFFF59D); // Classic sticky note yellow
                    if (initialBorder == Colors.transparent) initialBorder = Colors.transparent;
                    if (initialText == Colors.black) initialText = Colors.black87;
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
        } else if ([DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(type)) { 
          objColor = _shapeBorderColor; 
          objFill = _shapeFillColor; 
          objOpacity = _shapeOpacity; 
          objStroke = _shapeStrokeWidth;  
        }

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type, points: pts, strokeWidth: objStroke, color: objColor, fillColor: objFill, opacity: objOpacity,
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
                // 🚀 FIX FOR THE BORDER BUTTON
                else if (mode == 2) { 
                  _shapeBorderColor = newColor; 
                  if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(_activeObject!.type)) {
                    _activeObject!.color = newColor; 
                  }
                } 
                // 🚀 FIX FOR THE FILL BUTTON
                else if (mode == 3) { 
                  _shapeFillColor = newColor; 
                  if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(_activeObject!.type)) {
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
                              if (mode == 3) { 
                                _shapeOpacity = v; 
                                if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(_activeObject!.type)) _activeObject!.opacity = v; 
                              }
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

  bool _isShapeSelected(String tool) => ['Rect', 'Circle', 'Line', 'Arrow', 'Polygon'].contains(tool);

  IconData _getShapeIcon(String tool) {
    switch (tool) {
      case 'Rect': return Icons.crop_square;
      case 'Circle': return Icons.panorama_fish_eye;
      case 'Line': return Icons.show_chart;
      case 'Arrow': return Icons.arrow_outward;
      case 'Polygon': return Icons.change_history;
      default: return Icons.crop_square; 
    }
  }

  // 🚀 ADDED THIS FUNCTION TO CHECK FOR PATTERN TOOLS
  bool _isPatternSelected(String tool) => ['Brick', 'Grid', 'Horizontal', 'Vertical', 'Forward', 'Reverse', 'Diamond', 'Weave', 'Dots'].contains(tool);

  // 🚀 ADDED BACK AS REQUESTED
  Widget _utilityIcon(IconData icon, String msg, ThemeData theme, VoidCallback onTap, {bool isDestructive = false, bool isEnabled = true}) {
    return IconButton(
      tooltip: msg,
      onPressed: isEnabled ? onTap : null, 
      icon: Icon(icon, color: isEnabled ? (isDestructive ? Colors.red : theme.colorScheme.onSurface) : theme.disabledColor)
    );
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
      onTap: () => setState(() {
        _selectedTool = label;
        
        for (var obj in _drawingObjects) {
          obj.isSelected = false;
        }
        _activeObject = null;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12), 
        child: Column(
          children: [
            CircleAvatar(
              radius: 18, 
              backgroundColor: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainer, 
              child: Icon(icon, color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, size: 16)
            ),
            const SizedBox(height: 4), 
            Text(label, style: const TextStyle(fontSize: 9)),
          ]
        )
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
    if (_activeObject != null) {
      currentWidth = _activeObject!.strokeWidth;
    } else {
      switch (mode) { 
        case 0: currentWidth = _pencilStrokeWidth; break; 
        case 1: currentWidth = _shapeStrokeWidth; break; 
        case 2: currentWidth = _textStrokeWidth; break; 
        default: currentWidth = 2.0; 
      }
    }

    // Failsafe clamp to ensure the slider doesn't crash if a value gets weird
    currentWidth = currentWidth.clamp(1.0, 20.0);

    return SizedBox(
      width: double.infinity, 
      child: Row(children: [
        SizedBox(width: 32, child: Text("${currentWidth.toInt()}px", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: currentWidth, 
            min: 1, 
            max: 20, 
            onChanged: (v) => setState(() {
              if (mode == 0) { 
                _pencilStrokeWidth = v; 
                if (_activeObject?.type == DrawingType.pencil || _activeObject?.type == DrawingType.pen) _activeObject!.strokeWidth = v; 
              } 
              else if (mode == 1) { 
                _shapeStrokeWidth = v; 
                if (_activeObject != null && [DrawingType.rect, DrawingType.circle, DrawingType.line, DrawingType.arrow, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(_activeObject!.type)) {
                  _activeObject!.strokeWidth = v; 
                }
              }
              else if (mode == 2) { 
                _textStrokeWidth = v; 
                if (_activeObject?.type == DrawingType.text) _activeObject!.strokeWidth = v; 
              }
            })
          )
        ),
      ]),
    );
  }

  Widget _buildDensitySlider() {
    double currentDensity = (_activeObject?.type == DrawingType.dots) ? _activeObject!.patternDensity : _patternDensity;
    return SizedBox(
      width: double.infinity,
      child: Row(children: [
        SizedBox(width: 38, child: Text("${currentDensity.toInt()}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(
          child: Slider(
            value: currentDensity, min: 5, max: 100, divisions: 19,
            onChanged: (v) => setState(() {
              _patternDensity = v;
              if (_activeObject?.type == DrawingType.dots) _activeObject!.patternDensity = v;
            })
          )
        ),
      ]),
    );
  }

  Widget _vDiv(ThemeData theme) => VerticalDivider(width: 32, indent: 10, endIndent: 10, color: theme.colorScheme.outlineVariant);

  // Modern UI Helper for grouping properties
  Widget _buildPropSection(ThemeData theme, String title, IconData icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: theme.colorScheme.primary),
            const SizedBox(width: 6), 
            Text(
              title, 
              style: TextStyle(
                fontSize: 9, // 🚀 Tiny, clean typography for section headers
                fontWeight: FontWeight.bold, 
                color: theme.colorScheme.primary, 
                letterSpacing: 0.5
              )
            ),
          ],
        ),
        const SizedBox(height: 6), // 🚀 Very tight gap above the card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), // 🚀 Tightened inner content padding
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8), 
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: content,
        ),
        const SizedBox(height: 12), // 🚀 Shorter spacing between the different sections
      ],
    );
  }

  Widget _buildPanelContent(ThemeData theme) {
    DrawingType? type = _activeObject?.type;
    
    // 1. PENCIL & PEN
    if (_selectedTool == 'Pencil' || _selectedTool == 'Pen' || type == DrawingType.pencil || type == DrawingType.pen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropSection(
            theme, "STROKE THICKNESS", Icons.line_weight,
            _buildStrokeSlider(theme, 0),
          ),
          _buildPropSection(
            theme, "APPEARANCE", Icons.color_lens_outlined,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _colorButton("Line", _activeObject?.color ?? _pencilColor, 0),
                _colorButton("Fill", _activeObject?.fillColor ?? _penFillColor, 7),
              ],
            ),
          ),
        ],
      );
    }

    // 2. SHAPES & PATTERNS
    if (_isShapeSelected(_selectedTool) || _isPatternSelected(_selectedTool) || (type != null && [DrawingType.rect, DrawingType.circle, DrawingType.line, DrawingType.arrow, DrawingType.polygon, DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.diamond, DrawingType.reverseDiag, DrawingType.weave].contains(type))) {
      // Determine if we are working with a Line/Arrow or a Rect/Circle
      bool isLineOrArrow = _selectedTool == 'Line' || _selectedTool == 'Arrow' || type == DrawingType.line || type == DrawingType.arrow;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropSection(
            theme, "THICKNESS", Icons.border_style,
            _buildStrokeSlider(theme, 1),
          ),
          if (_selectedTool == 'Dots' || _activeObject?.type == DrawingType.dots)
            _buildPropSection(
              theme, "DENSITY", Icons.blur_on,
              _buildDensitySlider(),
            ),
          _buildPropSection(
            theme, "APPEARANCE", Icons.palette_outlined,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: isLineOrArrow 
                  // 🚀 Only show Line Color for Lines and Arrows
                  ? [
                      _colorButton("Line", _activeObject?.color ?? _shapeLineColor, 1),
                    ]
                  // 🚀 Show Border and Fill for Rectangles and Circles
                  : [
                      // Fix: Rect/Circle border color is stored in the object's `.color` property
                      _colorButton("Border", _activeObject?.color ?? _shapeBorderColor, 2),
                      _colorButton("Fill", _activeObject?.fillColor ?? _shapeFillColor, 3),
                    ],
            ),
          ),
        ],
      );
    }

    // 3. TEXT
    if (_selectedTool == 'Text' || _selectedTool == 'Callout' || _selectedTool == 'Note' || type == DrawingType.text) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropSection(
            theme, "TYPOGRAPHY", Icons.text_fields,
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _formatToggle(Icons.format_bold, _activeObject?.isBold ?? _textIsBold, () => setState(() { _textIsBold = !_textIsBold; if (_activeObject != null) _activeObject!.isBold = _textIsBold; }), theme),
                    _formatToggle(Icons.format_italic, _activeObject?.isItalic ?? _textIsItalic, () => setState(() { _textIsItalic = !_textIsItalic; if (_activeObject != null) _activeObject!.isItalic = _textIsItalic; }), theme),
                    _formatToggle(Icons.format_underlined, _activeObject?.isUnderline ?? _textIsUnderline, () => setState(() { _textIsUnderline = !_textIsUnderline; if (_activeObject != null) _activeObject!.isUnderline = _textIsUnderline; }), theme),
                    _formatToggle(Icons.format_strikethrough, _activeObject?.isStrikethrough ?? _textIsStrikethrough, () => setState(() { _textIsStrikethrough = !_textIsStrikethrough; if (_activeObject != null) _activeObject!.isStrikethrough = _textIsStrikethrough; }), theme),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextSizeSlider(theme),
              ],
            ),
          ),
          _buildPropSection(
            theme, "OUTLINE WIDTH", Icons.border_outer,
            _buildStrokeSlider(theme, 2),
          ),
          _buildPropSection(
            theme, "COLORS", Icons.format_color_fill,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _colorButton("Text", _activeObject?.color ?? _textColor, 4),
                _colorButton("Border", _activeObject?.borderColor ?? _textBorderColor, 5),
                _colorButton("Fill", _activeObject?.fillColor ?? _textFillColor, 6),
              ],
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFloatingPencilMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DRAW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _toolIcon(Icons.edit, "Pencil", theme), _toolIcon(Icons.polyline, "Pen", theme),
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
            _toolIcon(Icons.title, "Text", theme), 
            _toolIcon(Icons.chat_bubble_outline, "Callout", theme),
            _toolIcon(Icons.sticky_note_2, "Note", theme), 
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
            _toolIcon(Icons.crop_square, "Rect", theme), 
            _toolIcon(Icons.panorama_fish_eye, "Circle", theme), 
            _toolIcon(Icons.change_history, "Polygon", theme),
            _toolIcon(Icons.show_chart, "Line", theme), 
            _toolIcon(Icons.arrow_outward, "Arrow", theme),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingBrickMenu(ThemeData theme) {
    return Material(
      elevation: 8, borderRadius: BorderRadius.circular(8), color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("PATTERNS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(width: 8),
            _toolIcon(Icons.view_module, "Brick", theme), 
            _toolIcon(Icons.grid_on, "Grid", theme), 
            _toolIcon(Icons.notes, "Horizontal", theme), 
            _toolIcon(Icons.view_column, "Vertical", theme), 
            _toolIcon(Icons.trending_up, "Forward", theme),
            _toolIcon(Icons.trending_down, "Reverse", theme),
            _toolIcon(Icons.grid_goldenratio, "Weave", theme),
            _toolIcon(Icons.grid_4x4, "Diamond", theme), 
            _toolIcon(Icons.scatter_plot, "Dots", theme),
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
                  
                  _mainMenuToggle(icon: _selectedTool == 'Pen' ? Icons.polyline : Icons.edit, label: _selectedTool == 'Pen' ? "Pen" : "Pencil", isActive: _showPencilToolbar || _selectedTool == 'Pencil' || _selectedTool == 'Pen', hasDropdown: true, theme: theme, onTap: () => setState(() { 
                    _showPencilToolbar = !_showPencilToolbar; 
                    if (_showPencilToolbar) { 
                      _showShapeToolbar = false; _showTextToolbar = false; 
                      if (_selectedTool != 'Pencil' && _selectedTool != 'Pen') _selectedTool = 'Pencil'; 
                      // 🚀 Clear selection
                      for (var obj in _drawingObjects) obj.isSelected = false; _activeObject = null;
                    } else { 
                      _selectedTool = 'Select'; 
                    } 
                  })),
                  
                  _mainMenuToggle(icon: _getShapeIcon(_selectedTool), label: "Shapes", isActive: _showShapeToolbar || _isShapeSelected(_selectedTool), hasDropdown: true, theme: theme, onTap: () => setState(() { 
                    _showShapeToolbar = !_showShapeToolbar; 
                    if (_showShapeToolbar) { 
                      _showPencilToolbar = false; _showTextToolbar = false; 
                      if (!_isShapeSelected(_selectedTool)) _selectedTool = 'Rect'; 
                      // 🚀 Clear selection
                      for (var obj in _drawingObjects) obj.isSelected = false; _activeObject = null;
                    } else { 
                      _selectedTool = 'Select'; 
                    } 
                  })),
                  
                  _mainMenuToggle(
                    icon: _selectedTool == 'Callout' ? Icons.chat_bubble_outline : (_selectedTool == 'Note' ? Icons.sticky_note_2 : Icons.title), 
                    label: _selectedTool == 'Callout' ? "Callout" : (_selectedTool == 'Note' ? "Note" : "Text"), 
                    isActive: _showTextToolbar || _selectedTool == 'Text' || _selectedTool == 'Callout' || _selectedTool == 'Note', 
                    hasDropdown: true, 
                    theme: theme, 
                    onTap: () => setState(() { 
                      _showTextToolbar = !_showTextToolbar; 
                      if (_showTextToolbar) { 
                        _showPencilToolbar = false; _showShapeToolbar = false; 
                        if (_selectedTool != 'Text' && _selectedTool != 'Callout' && _selectedTool != 'Note') { _selectedTool = 'Text'; } 
                        for (var obj in _drawingObjects) obj.isSelected = false; _activeObject = null;
                      } else { 
                        _selectedTool = 'Select'; 
                      } 
                    })
                  ),

                 // 🚀 Updated Main Menu Button
                  _mainMenuToggle(
                    icon: Icons.view_module, 
                    label: "Pattern", 
                    isActive: _showBrickToolbar || _isPatternSelected(_selectedTool),
                    hasDropdown: true, 
                    theme: theme,
                    onTap: () => setState(() { 
                      _showBrickToolbar = !_showBrickToolbar; 
                      if (_showBrickToolbar) { 
                        _showPencilToolbar = false; _showShapeToolbar = false; _showTextToolbar = false; 
                        if (_selectedTool != 'Brick') _selectedTool = 'Brick'; 
                        for (var obj in _drawingObjects) obj.isSelected = false; _activeObject = null;
                      } else { 
                        _selectedTool = 'Select'; 
                      } 
                    })
                  ),
                  
                  _mainMenuToggle(icon: Icons.place, label: "Pin", isActive: _selectedTool == 'Pin', hasDropdown: false, theme: theme, onTap: () => setState(() { 
                    _showPencilToolbar = false; _showShapeToolbar = false; _showTextToolbar = false; _selectedTool = 'Pin';
                    for (var obj in _drawingObjects) obj.isSelected = false; _activeObject = null;
                  })),
                  
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
                                        backgroundImageBytes: widget.initialBackgroundImage,                                          
                                      ),
                                    ),
                                  ]
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Floating Menus
                    if (_showPencilToolbar) Positioned(top: 8, left: 80, child: _buildFloatingPencilMenu(theme)),
                    if (_showShapeToolbar) Positioned(top: 8, left: 140, child: _buildFloatingShapeMenu(theme)),
                    if (_showTextToolbar) Positioned(top: 8, left: 210, child: _buildFloatingTextMenu(theme)),
                    if (_showBrickToolbar) Positioned(top: 8, left: 280, child: _buildFloatingBrickMenu(theme)),

                    // 🌟 FULL HEIGHT PROPERTIES PANEL 🌟
                    if (_activeObject != null || ((_showPencilToolbar || _showShapeToolbar || _showTextToolbar) && _selectedTool != 'Select' && _selectedTool != 'Eraser' && _selectedTool != 'Pin'))
                      Positioned(
                        top: 0, right: 0, bottom: 0,
                        child: Material(
                          elevation: 16, 
                          child: PropertiesPanel(
                            title: _activeObject != null ? "EDIT ANNOTATION" : "${_selectedTool.toUpperCase()} SETTINGS",
                            content: _buildPanelContent(theme),
                            onClose: () {
                              setState(() {
                                if (_activeObject != null) {
                                  for (var obj in _drawingObjects) { obj.isSelected = false; }
                                  _activeObject = null;
                                } else {
                                  _selectedTool = 'Select';
                                  _showPencilToolbar = false;
                                  _showShapeToolbar = false;
                                  _showTextToolbar = false;
                                }
                              });
                            },
                          ),
                        ),
                      ),

                    // 🌟 3. NATIVE FULLSCREEN TOGGLE BUTTON 🌟
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
}