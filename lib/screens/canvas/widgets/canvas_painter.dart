import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/canvas_models.dart';

class CanvasPaper extends StatelessWidget {
  final List<DrawingObject> objects;
  final DrawingObject? preview;
  final Uint8List? backgroundImageBytes;

  const CanvasPaper({super.key, required this.objects, this.preview, this.backgroundImageBytes});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backgroundImageBytes != null)
          Image.memory(
            backgroundImageBytes!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
          ),
        Positioned.fill(
          child: CustomPaint(painter: MainPainter(context, objects, preview)),
        ),
      ],
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
        double fontSize = obj.fontSize;
        if (fontSize < 1) fontSize = 1;

        final textPainter = TextPainter(
          text: TextSpan(text: obj.text, style: TextStyle(color: obj.color, fontSize: fontSize, fontWeight: obj.isBold ? FontWeight.bold : FontWeight.normal, fontStyle: obj.isItalic ? FontStyle.italic : FontStyle.normal)),
          textDirection: TextDirection.ltr, textAlign: TextAlign.left,
        );
        
        double availableWidth = rect.width > 20 ? rect.width - 20 : 10;
        textPainter.layout(maxWidth: availableWidth);
        double requiredHeight = textPainter.height + 20;
        
        if (obj.end.dy >= obj.start.dy) {
          obj.end = Offset(obj.end.dx, obj.start.dy + requiredHeight);
        } else {
          obj.start = Offset(obj.start.dx, obj.end.dy - requiredHeight);
        }
        
        final updatedRect = obj.rect;
        final borderPaint = Paint()..color = obj.borderColor..strokeWidth = obj.strokeWidth..style = PaintingStyle.stroke;

        if (obj.isCallout && obj.points != null && obj.points!.length >= 2) {
          Offset knee = obj.points![0];
          Offset tip = obj.points![1];

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

        if (obj.fillColor != Colors.transparent) canvas.drawRect(updatedRect, Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill);
        if (obj.borderColor != Colors.transparent) canvas.drawRect(updatedRect, borderPaint);
        
        textPainter.paint(canvas, updatedRect.topLeft + const Offset(10, 10));

        if (obj.isSelected && obj.isCallout && obj.points != null) {
          Paint hP = Paint()..color = Colors.blue; 
          Paint wP = Paint()..color = Colors.white; 
          canvas.drawCircle(obj.points![0], 7, wP); canvas.drawCircle(obj.points![0], 5, hP);
          canvas.drawCircle(obj.points![1], 7, wP); canvas.drawCircle(obj.points![1], 5, hP);
        }
      
      } else if (obj.type == DrawingType.pin) {
          double w = rect.width;
          double h = rect.height;
          double r = w / 2; 
          
          Path pinPath = Path();
          pinPath.moveTo(rect.center.dx, rect.bottom); 
          pinPath.quadraticBezierTo(rect.left, rect.bottom - h * 0.4, rect.left, rect.top + r);
          pinPath.arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r), clockwise: true);
          pinPath.quadraticBezierTo(rect.right, rect.bottom - h * 0.4, rect.center.dx, rect.bottom);
          pinPath.close();

          final borderPaint = Paint()
            ..color = obj.color.withOpacity(obj.opacity)
            ..strokeWidth = obj.strokeWidth
            ..style = PaintingStyle.stroke;

          if (obj.fillColor != Colors.transparent) {
            canvas.drawPath(pinPath, Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill);
          }
          canvas.drawPath(pinPath, borderPaint);
          
          canvas.drawCircle(Offset(rect.center.dx, rect.top + r), r * 0.35, Paint()..color = Colors.white..style = PaintingStyle.fill);
          canvas.drawCircle(Offset(rect.center.dx, rect.top + r), r * 0.35, borderPaint);
      
      } else if (obj.type == DrawingType.customTool) {
          if (obj.customImage != null) {
            final srcRect = Rect.fromLTWH(
              0, 0, 
              obj.customImage!.width.toDouble(), 
              obj.customImage!.height.toDouble()
            );
            
            final dstRect = obj.rect;

            final imagePaint = Paint()
              ..filterQuality = FilterQuality.high
              ..color = Colors.white.withOpacity(obj.opacity);

            canvas.drawImageRect(obj.customImage!, srcRect, dstRect, imagePaint);
            
          } else {
            final fallbackPaint = Paint()
              ..color = Colors.grey.withOpacity(0.5)
              ..style = PaintingStyle.fill;
            canvas.drawRect(obj.rect, fallbackPaint);
          }
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
          
          if (obj.fillColor != Colors.transparent && obj.points!.length > 2) {
             Path fillPath = Path.from(path); 
             fillPath.close(); 
             
             final fillPaint = Paint()
               ..color = obj.fillColor.withOpacity(obj.opacity)
               ..style = PaintingStyle.fill;
             canvas.drawPath(fillPath, fillPaint);
          }
          
          canvas.drawPath(path, strokePaint);

          if (obj == preview && obj.type == DrawingType.pen) {
            canvas.drawCircle(obj.points![0], 6, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2);
          }
        } else if (obj.type == DrawingType.line) {
          canvas.drawLine(obj.start, obj.end, strokePaint);
        } else if (obj.type == DrawingType.arrow) {
          canvas.drawLine(obj.start, obj.end, strokePaint);
          
          const double arrowLength = 15.0;
          const double arrowAngle = math.pi / 6; 
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

        if (obj.type != DrawingType.pencil && obj.type != DrawingType.pen) {
          final points = [rect.topLeft, rect.topCenter, rect.topRight, rect.centerLeft, rect.centerRight, rect.bottomLeft, rect.bottomCenter, rect.bottomRight];
          for (var p in points) { 
            canvas.drawCircle(p, 7, wP); 
            canvas.drawCircle(p, 5, hP); 
          }
        } else {
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