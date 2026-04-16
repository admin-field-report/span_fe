import 'package:flutter/material.dart';
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/canvas/widgets/canvas_painter.dart';
import 'dart:math' as math;

// ==========================================
// PREVIEW CENTERING WRAPPER PAINTER (UPDATED)
// ==========================================
class CenteredPreviewPainter extends CustomPainter {
  final BuildContext context;
  final List<DrawingObject> objects;

  CenteredPreviewPainter(this.context, this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    // 1. Calculate the bounds
    Rect bounds = _calculateBounds(objects);

    // 🚀 THE FIX: If the drawing is just a single point (like Text or a Dot), 
    // it has no width/height. We artificially inflate it so the math doesn't crash!
    if (bounds.width == 0 || bounds.height == 0) {
      bounds = bounds.inflate(100.0); 
    }

    // 2. Calculate scale to fit in the 300x300 container
    double padding = 40.0; 
    double scaleX = (size.width - padding) / bounds.width;
    double scaleY = (size.height - padding) / bounds.height;
    double scale = math.min(scaleX, scaleY);

    if (scale > 1.0) scale = 1.0;

    canvas.save();
    
    // 🚀 THE FIX: We clip the outer 300x300 box so nothing bleeds into your UI
    canvas.clipRect(Offset.zero & size);
    
    // Center the drawing
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    // 🚀 THE FIX: We pass a MASSIVE size to your MainPainter instead of 300x300. 
    // This stops MainPainter from accidentally clipping drawings that were drawn far down the screen.
    Size massiveSize = Size(bounds.right + 2000, bounds.bottom + 2000);
    MainPainter(context, objects, null).paint(canvas, massiveSize);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Rect _calculateBounds(List<DrawingObject> objects) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void checkOffset(Offset offset) {
      if (offset.dx < minX) minX = offset.dx;
      if (offset.dy < minY) minY = offset.dy;
      if (offset.dx > maxX) maxX = offset.dx;
      if (offset.dy > maxY) maxY = offset.dy;
    }

    void processObject(DrawingObject obj) {
      checkOffset(obj.start);
      checkOffset(obj.end);

      if (obj.points != null && obj.points!.isNotEmpty) {
        for (var point in obj.points!) {
          checkOffset(point);
        }
      }

      if (obj.internalShapes != null && obj.internalShapes!.isNotEmpty) {
        for (var internalObj in obj.internalShapes!) {
          processObject(internalObj);
        }
      }
    }

    for (var obj in objects) {
      processObject(obj);
    }

    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}