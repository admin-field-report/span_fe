import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- MODELS ---
enum DrawingType { line, rect, circle }
enum ResizeHandle { topLeft, topCenter, topRight, centerLeft, centerRight, bottomLeft, bottomCenter, bottomRight, body, none }

class DrawingObject {
  Offset start;
  Offset end;
  double strokeWidth;
  Color color;
  Color fillColor;
  double opacity; 
  bool isSelected;
  DrawingType type;

  DrawingObject({
    required this.start,
    required this.end,
    required this.type,
    this.strokeWidth = 2.0,
    this.color = Colors.black,
    this.fillColor = Colors.transparent,
    this.opacity = 1.0,
    this.isSelected = false,
  });

  Rect get rect => Rect.fromPoints(start, end);

  DrawingObject copy() => DrawingObject(
        start: start,
        end: end,
        type: type,
        strokeWidth: strokeWidth,
        color: color,
        fillColor: fillColor,
        opacity: opacity,
        isSelected: isSelected,
      );
}

// --- MAIN SCREEN ---
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

  final List<Color> _availableColors = [
    Colors.transparent, Colors.black, Colors.white, Colors.grey, Colors.red, 
    Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple,
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = _pages.first;
  }

  // --- UNDO / REDO LOGIC ---
  void _saveSnapshot() {
    _undoStack.add(_drawingObjects.map((e) => e.copy()).toList());
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear(); // New action invalidates redo history
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

  // --- COLOR PICKER ---
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

  // --- GESTURE HELPERS ---
  MouseCursor _getCursor(ResizeHandle handle) {
    switch (handle) {
      case ResizeHandle.topLeft:
      case ResizeHandle.bottomRight: return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeHandle.topRight:
      case ResizeHandle.bottomLeft: return SystemMouseCursors.resizeUpRightDownLeft;
      case ResizeHandle.topCenter:
      case ResizeHandle.bottomCenter: return SystemMouseCursors.resizeUpDown;
      case ResizeHandle.centerLeft:
      case ResizeHandle.centerRight: return SystemMouseCursors.resizeLeftRight;
      case ResizeHandle.body: return SystemMouseCursors.move;
      default: return SystemMouseCursors.basic;
    }
  }

  ResizeHandle _getHitHandle(Offset p, DrawingObject obj) {
    const double hSize = 25.0; 
    final r = obj.rect;
    if (obj.isSelected) {
      if ((p - r.topLeft).distance < hSize) return ResizeHandle.topLeft;
      if ((p - r.topCenter).distance < hSize) return ResizeHandle.topCenter;
      if ((p - r.topRight).distance < hSize) return ResizeHandle.topRight;
      if ((p - r.centerLeft).distance < hSize) return ResizeHandle.centerLeft;
      if ((p - r.centerRight).distance < hSize) return ResizeHandle.centerRight;
      if ((p - r.bottomLeft).distance < hSize) return ResizeHandle.bottomLeft;
      if ((p - r.bottomCenter).distance < hSize) return ResizeHandle.bottomCenter;
      if ((p - r.bottomRight).distance < hSize) return ResizeHandle.bottomRight;
    }
    if (obj.type == DrawingType.line) {
      if (_distToSegment(p, obj.start, obj.end) < 15) return ResizeHandle.body;
    } else {
      if (obj.rect.inflate(5).contains(p)) return ResizeHandle.body;
    }
    return ResizeHandle.none;
  }

  void _handlePointerDown(PointerDownEvent details) {
    final pos = details.localPosition;
    setState(() {
      if (_selectedTool != 'Select') {
        _saveSnapshot();
        for (var obj in _drawingObjects) obj.isSelected = false;
        DrawingType type = _selectedTool == 'Rect' ? DrawingType.rect : (_selectedTool == 'Circle' ? DrawingType.circle : DrawingType.line);

        _currentPreview = DrawingObject(
          start: pos, end: pos, type: type,
          strokeWidth: _strokeWidth, color: _activeColor,
          fillColor: _fillColor, opacity: _opacity,
        );
      } else {
        _activeHandle = ResizeHandle.none;
        DrawingObject? hitObj;
        ResizeHandle hitHandle = ResizeHandle.none;

        for (var obj in _drawingObjects.reversed) {
          if (obj.isSelected) {
            hitHandle = _getHitHandle(pos, obj);
            if (hitHandle != ResizeHandle.none && hitHandle != ResizeHandle.body) { hitObj = obj; break; }
          }
        }
        if (hitObj == null) {
          for (var obj in _drawingObjects.reversed) {
            hitHandle = _getHitHandle(pos, obj);
            if (hitHandle != ResizeHandle.none) { hitObj = obj; break; }
          }
        }

        if (hitObj != null) {
          for (var obj in _drawingObjects) obj.isSelected = false;
          hitObj.isSelected = true;
          _activeObject = hitObj;
          _activeHandle = hitHandle;
          _strokeWidth = hitObj.strokeWidth;
          _activeColor = hitObj.color;
          _fillColor = hitObj.fillColor;
          _opacity = hitObj.opacity;
          if (hitHandle == ResizeHandle.body) _dragOffset = pos - hitObj.start;
        } else {
          for (var obj in _drawingObjects) obj.isSelected = false;
          _activeObject = null;
        }
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent details, BoxConstraints constraints) {
    final pos = details.localPosition;
    final double maxWidth = constraints.maxWidth;
    final double maxHeight = constraints.maxHeight;

    setState(() {
      if (_currentPreview != null) {
        _currentPreview!.end = Offset(pos.dx.clamp(0.0, maxWidth), pos.dy.clamp(0.0, maxHeight));
      } else if (_activeObject != null && _activeHandle != ResizeHandle.none) {
        // Save snapshot only once when movement starts
        if (details.delta.distance > 0.1 && _undoStack.isEmpty || (_undoStack.isNotEmpty && _undoStack.last != _drawingObjects)) {
           // Movement logic usually handles snapshotting on PointerDown or PointerUp to avoid filling stack
        }

        Rect r = _activeObject!.rect;
        double left = r.left, top = r.top, right = r.right, bottom = r.bottom;

        if (_activeHandle == ResizeHandle.body) {
          Offset delta = _activeObject!.end - _activeObject!.start;
          double newX = (pos.dx - _dragOffset.dx).clamp(0.0, maxWidth - delta.dx.abs());
          double newY = (pos.dy - _dragOffset.dy).clamp(0.0, maxHeight - delta.dy.abs());
          _activeObject!.start = Offset(newX, newY);
          _activeObject!.end = Offset(newX + delta.dx, newY + delta.dy);
        } else {
          double px = pos.dx.clamp(0.0, maxWidth);
          double py = pos.dy.clamp(0.0, maxHeight);
          switch (_activeHandle) {
            case ResizeHandle.topLeft: left = px; top = py; break;
            case ResizeHandle.topCenter: top = py; break;
            case ResizeHandle.topRight: right = px; top = py; break;
            case ResizeHandle.centerLeft: left = px; break;
            case ResizeHandle.centerRight: right = px; break;
            case ResizeHandle.bottomLeft: left = px; bottom = py; break;
            case ResizeHandle.bottomCenter: bottom = py; break;
            case ResizeHandle.bottomRight: right = px; bottom = py; break;
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

  // --- KEYBOARD SHORTCUTS WRAPPER ---
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
        _toolIcon(Icons.near_me, "Select", theme), _toolIcon(Icons.show_chart, "Line", theme),
        _toolIcon(Icons.crop_square, "Rect", theme), _toolIcon(Icons.panorama_fish_eye, "Circle", theme),
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
      final Rect rect = obj.rect;
      
      // 1. FILL (Inside)
      if (obj.type != DrawingType.line && obj.fillColor != Colors.transparent) {
        final fillPaint = Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill;
        if (obj.type == DrawingType.rect) canvas.drawRect(rect, fillPaint);
        if (obj.type == DrawingType.circle) canvas.drawOval(rect, fillPaint);
      }

      // 2. STROKE (Border)
      final strokePaint = Paint()..color = obj.color..strokeWidth = obj.strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
      if (obj.type == DrawingType.line) canvas.drawLine(obj.start, obj.end, strokePaint);
      else if (obj.type == DrawingType.rect) canvas.drawRect(rect, strokePaint);
      else if (obj.type == DrawingType.circle) canvas.drawOval(rect, strokePaint);

      // 3. SELECTION HANDLES
      if (obj.isSelected) {
        final hP = Paint()..color = Colors.blue;
        final wP = Paint()..color = Colors.white;
        final points = [rect.topLeft, rect.topCenter, rect.topRight, rect.centerLeft, rect.centerRight, rect.bottomLeft, rect.bottomCenter, rect.bottomRight];
        for (var p in points) { canvas.drawCircle(p, 7, wP); canvas.drawCircle(p, 5, hP); }
      }
    }
    for (var obj in objects) drawShape(obj);
    if (preview != null) drawShape(preview!);
  }
  @override bool shouldRepaint(covariant MainPainter oldDelegate) => true;
}