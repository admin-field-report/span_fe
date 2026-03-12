import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- MODELS ---
enum DrawingType { line, rect, circle, pencil, text }
enum ResizeHandle { topLeft, topCenter, topRight, centerLeft, centerRight, bottomLeft, bottomCenter, bottomRight, rotation, body, none }

class DrawingObject {
  Offset start;
  Offset end;
  List<Offset>? points; 
  String? text; 
  double strokeWidth;
  Color color;
  Color fillColor;
  double opacity; 
  bool isSelected;
  DrawingType type;
  double rotation; 

  DrawingObject({
    required this.start,
    required this.end,
    required this.type,
    this.points,
    this.text,
    this.strokeWidth = 2.0,
    this.color = Colors.black,
    this.fillColor = Colors.transparent,
    this.opacity = 1.0,
    this.isSelected = false,
    this.rotation = 0.0,
  });

  Rect get rect {
    if (type == DrawingType.pencil && points != null && points!.isNotEmpty) {
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
        opacity: opacity,
        isSelected: isSelected,
        rotation: rotation,
      );
}

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});
  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  String _selectedTool = 'Select';
  double _strokeWidth = 2.0;
  double _opacity = 1.0; 
  Color _activeColor = Colors.black; 
  Color _fillColor = Colors.transparent;
  
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

  final List<Color> _availableColors = [
    Colors.transparent, Colors.black, Colors.white, Colors.grey, Colors.red, 
    Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple,
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = _pages.first;
  }

  // --- TEXT TOOL DIALOG (Updated for Editing) ---
  Future<void> _showTextDialog({required Offset position, DrawingObject? existingObject}) async {
    final TextEditingController controller = TextEditingController(text: existingObject?.text ?? "");
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingObject == null ? "Enter Text" : "Edit Text"),
        content: SizedBox(
          width: 400, // Fixed width for the dialog entry
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null, // Allows multi-line input
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
                  // Calculate size based on the text content
                  final textPainter = TextPainter(
                    text: TextSpan(
                      text: controller.text,
                      style: TextStyle(fontSize: _strokeWidth * 10), // Font size linked to stroke width or a default
                    ),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: 500); // Max width before wrapping

                  final calculatedSize = Offset(textPainter.width + 20, textPainter.height + 20);

                  if (existingObject != null) {
                    existingObject.text = controller.text;
                    // Update the bounding box to fit the new text
                    existingObject.end = existingObject.start + calculatedSize;
                  } else {
                    final textObj = DrawingObject(
                      start: position,
                      end: position + calculatedSize,
                      type: DrawingType.text,
                      text: controller.text,
                      color: _activeColor,
                      opacity: _opacity,
                      isSelected: true,
                      strokeWidth: _strokeWidth, // Using this to control font scale
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
    if (_selectedTool == 'Eraser') return SystemMouseCursors.none; // Fixed 'nocursor'
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
      default: return SystemMouseCursors.basic;
    }
  }

  ResizeHandle _getHitHandle(Offset p, DrawingObject obj) {
    const double hSize = 25.0; 
    final localP = _toLocalSpace(p, obj);
    final r = obj.rect;

    if (obj.isSelected) {
      Offset rotPos = Offset(r.topCenter.dx, r.topCenter.dy - 40);
      if ((localP - rotPos).distance < hSize) return ResizeHandle.rotation;
      if ((localP - r.topLeft).distance < hSize) return ResizeHandle.topLeft;
      if ((localP - r.topCenter).distance < hSize) return ResizeHandle.topCenter;
      if ((localP - r.topRight).distance < hSize) return ResizeHandle.topRight;
      if ((localP - r.centerLeft).distance < hSize) return ResizeHandle.centerLeft;
      if ((localP - r.centerRight).distance < hSize) return ResizeHandle.centerRight;
      if ((localP - r.bottomLeft).distance < hSize) return ResizeHandle.bottomLeft;
      if ((localP - r.bottomCenter).distance < hSize) return ResizeHandle.bottomCenter;
      if ((localP - r.bottomRight).distance < hSize) return ResizeHandle.bottomRight;
    }
    
    if (obj.type == DrawingType.line) {
      if (_distToSegment(localP, obj.start, obj.end) < 15) return ResizeHandle.body;
    } else if (obj.type == DrawingType.pencil && obj.points != null) {
      for (int i = 0; i < obj.points!.length - 1; i++) {
        if (_distToSegment(localP, obj.points![i], obj.points![i+1]) < 15) return ResizeHandle.body;
      }
    } else {
      if (r.inflate(5).contains(localP)) return ResizeHandle.body;
    }
    return ResizeHandle.none;
  }

  void _handlePointerDown(PointerDownEvent details) {
    final pos = details.localPosition;
    final now = DateTime.now();

    setState(() {
      if (_selectedTool == 'Text') {
        _showTextDialog(position: pos);
      } else if (_selectedTool == 'Eraser') {
        _saveSnapshot();
        _drawingObjects.removeWhere((obj) => _getHitHandle(pos, obj) != ResizeHandle.none);
      } else if (_selectedTool != 'Select') {
        _saveSnapshot();
        for (var obj in _drawingObjects) obj.isSelected = false;
        
        DrawingType type = (_selectedTool == 'Pencil') ? DrawingType.pencil : 
                           (_selectedTool == 'Rect' ? DrawingType.rect : (_selectedTool == 'Circle' ? DrawingType.circle : DrawingType.line));
        List<Offset>? pts = (type == DrawingType.pencil) ? [pos] : null;

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type, points: pts,
          strokeWidth: _strokeWidth, color: _activeColor,
          fillColor: _fillColor, opacity: _opacity,
        );
      } else {
        _activeHandle = ResizeHandle.none;
        DrawingObject? hitObj;
        ResizeHandle hitHandle = ResizeHandle.none;

        for (var obj in _drawingObjects.reversed) {
          hitHandle = _getHitHandle(pos, obj);
          if (hitHandle != ResizeHandle.none) { hitObj = obj; break; }
        }

        if (hitObj != null) {
          // Double tap to edit text
          if (hitObj.type == DrawingType.text && 
              _lastTapTime != null && 
              now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
            _showTextDialog(position: pos, existingObject: hitObj);
            return;
          }
          _lastTapTime = now;

          if (!hitObj.isSelected) _saveSnapshot();
          for (var obj in _drawingObjects) obj.isSelected = false;
          hitObj.isSelected = true;
          _activeObject = hitObj;
          _activeHandle = hitHandle;
          
          if (hitHandle == ResizeHandle.rotation) {
             _initialRotationAngle = math.atan2(pos.dy - hitObj.center.dy, pos.dx - hitObj.center.dx) - hitObj.rotation;
          } else if (hitHandle == ResizeHandle.body) {
            _dragOffset = pos - hitObj.start;
          }
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
        } else if (_activeHandle == ResizeHandle.body) {
          Offset delta = _activeObject!.end - _activeObject!.start;
          Offset moveDelta = (pos - _dragOffset) - _activeObject!.start;
          _activeObject!.start = pos - _dragOffset;
          _activeObject!.end = _activeObject!.start + delta;
          if (_activeObject!.type == DrawingType.pencil) {
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
      if (_currentPreview != null) {
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

  void _showColorPicker(bool isFill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFill ? "Select Fill Color" : "Select Border Color"),
        content: Wrap(
          spacing: 10, runSpacing: 10,
          children: _availableColors.map((color) => GestureDetector(
            onTap: () {
              setState(() {
                if (isFill) {
                  _fillColor = color;
                  if (_activeObject != null) { _saveSnapshot(); _activeObject!.fillColor = color; }
                } else {
                  _activeColor = color;
                  if (_activeObject != null) { _saveSnapshot(); _activeObject!.color = color; }
                }
              });
              Navigator.pop(context);
            },
            child: CircleAvatar(
              backgroundColor: color == Colors.transparent ? Colors.white : color,
              radius: 20,
              child: color == Colors.transparent 
                ? const Icon(Icons.block, size: 16, color: Colors.red) 
                : (isFill ? _fillColor : _activeColor) == color ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          )).toList(),
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
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return MouseRegion(
                                  cursor: _getCursor(_hoveredHandle),
                                  onHover: (d) {
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
                                    child: CanvasPaper(objects: _drawingObjects, preview: _currentPreview),
                                  ),
                                );
                              }
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
        const Icon(Icons.arrow_back), const SizedBox(width: 15),
        Text("Canvas Designer Pro", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        _buildPageSelector(theme), const SizedBox(width: 20), const Icon(Icons.save_outlined),
      ]),
    );
  }

  Widget _buildFullWidthToolbar(ThemeData theme) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), color: theme.colorScheme.surface,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        _buildStrokeSlider(theme), _vDiv(theme),
        _buildOpacitySlider(theme), _vDiv(theme),
        _colorButton("Border", _activeColor, false), const SizedBox(width: 12),
        _colorButton("Fill", _fillColor, true), _vDiv(theme),
        _toolIcon(Icons.near_me, "Select", theme),
        _toolIcon(Icons.edit, "Pencil", theme),
        _toolIcon(Icons.show_chart, "Line", theme),
        _toolIcon(Icons.crop_square, "Rect", theme), 
        _toolIcon(Icons.panorama_fish_eye, "Circle", theme),
        _toolIcon(Icons.title, "Text", theme),
        _vDiv(theme), 
        _utilityIcon(Icons.undo, "Undo", theme, _undo, isEnabled: _undoStack.isNotEmpty),
        _utilityIcon(Icons.redo, "Redo", theme, _redo, isEnabled: _redoStack.isNotEmpty),
        _utilityIcon(Icons.delete_outline, "Delete", theme, _deleteSelected, isDestructive: true, isEnabled: _activeObject != null),
      ])),
    );
  }

  Widget _colorButton(String label, Color color, bool isFill) {
    return GestureDetector(
      onTap: () => _showColorPicker(isFill),
      child: Column(children: [
        CircleAvatar(radius: 16, backgroundColor: color == Colors.transparent ? Colors.grey[200] : color, child: color == Colors.transparent ? const Icon(Icons.block, size: 12, color: Colors.red) : null),
        const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8)),
      ]),
    );
  }

  Widget _buildOpacitySlider(ThemeData theme) {
    return Row(children: [
      const Icon(Icons.opacity, size: 16),
      SizedBox(width: 80, child: Slider(value: _opacity, onChanged: (v) => setState(() { 
        _opacity = v; if (_activeObject != null) _activeObject!.opacity = v;
      }))),
    ]);
  }

  Widget _buildStrokeSlider(ThemeData theme) {
    return Row(children: [
      Text("${_strokeWidth.toInt()}px", style: theme.textTheme.labelSmall),
      SizedBox(width: 80, child: Slider(value: _strokeWidth, min: 1, max: 15, onChanged: (v) => setState(() {
        _strokeWidth = v; if (_activeObject != null) _activeObject!.strokeWidth = v;
      }))),
    ]);
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
      
      // --- RESPONSIVE TEXT HANDLING ---
      if (obj.type == DrawingType.text && obj.text != null) {
        // Calculate font size based on the current height of the bounding box.
        // 0.8 is a safety factor to keep text within the selection handles.
        double dynamicFontSize = rect.height * 0.8;
        
        // Prevent font size from becoming zero or negative during weird drags
        if (dynamicFontSize < 1) dynamicFontSize = 1;

        final textPainter = TextPainter(
          text: TextSpan(
            text: obj.text,
            style: TextStyle(
              color: obj.color.withOpacity(obj.opacity),
              fontSize: dynamicFontSize, 
              fontWeight: FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        );
        
        // Use the width of the box to handle wrapping
        textPainter.layout(maxWidth: rect.width > 0 ? rect.width : 1);
        textPainter.paint(canvas, rect.topLeft);
      } else {
        if (obj.type != DrawingType.line && obj.type != DrawingType.pencil && obj.fillColor != Colors.transparent) {
          final fillPaint = Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill;
          if (obj.type == DrawingType.rect) canvas.drawRect(rect, fillPaint);
          if (obj.type == DrawingType.circle) canvas.drawOval(rect, fillPaint);
        }

        final strokePaint = Paint()
          ..color = obj.color.withOpacity(obj.opacity)
          ..strokeWidth = obj.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        if (obj.type == DrawingType.pencil && obj.points != null && obj.points!.isNotEmpty) {
          Path path = Path();
          path.moveTo(obj.points![0].dx, obj.points![0].dy);
          for (var i = 1; i < obj.points!.length; i++) path.lineTo(obj.points![i].dx, obj.points![i].dy);
          canvas.drawPath(path, strokePaint);
        } else if (obj.type == DrawingType.line) {
          canvas.drawLine(obj.start, obj.end, strokePaint);
        } else if (obj.type == DrawingType.rect) {
          canvas.drawRect(rect, strokePaint);
        } else if (obj.type == DrawingType.circle) {
          canvas.drawOval(rect, strokePaint);
        }
      }

      if (obj.isSelected) {
        final hP = Paint()..color = Colors.blue;
        final wP = Paint()..color = Colors.white;
        
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

        final points = [rect.topLeft, rect.topCenter, rect.topRight, rect.centerLeft, rect.centerRight, rect.bottomLeft, rect.bottomCenter, rect.bottomRight];
        for (var p in points) { canvas.drawCircle(p, 7, wP); canvas.drawCircle(p, 5, hP); }
      }
      canvas.restore();
    }
    
    for (var obj in objects) drawShape(obj);
    if (preview != null) drawShape(preview!);
  }
  @override bool shouldRepaint(covariant MainPainter oldDelegate) => true;
}