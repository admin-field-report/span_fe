import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/canvas_models.dart';

class CanvasPaper extends StatelessWidget {
  final List<DrawingObject> objects;
  final DrawingObject? preview;
  final Uint8List? backgroundImageBytes;

  // 🚀 NEW: Accept dynamic dimensions
  final double width;
  final double height;

  const CanvasPaper({
    super.key, 
    required this.objects, 
    this.preview, 
    this.backgroundImageBytes,
    this.width = 816.0,  // Fallback A4 width
    this.height = 1056.0 // Fallback A4 height
  });


  @override
  Widget build(BuildContext context) {
    // 🚀 THE FIX: Center the canvas and force it to be the EXACT aspect ratio of the image
    return Center(
      child: AspectRatio(
        aspectRatio: width / height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundImageBytes != null)
              Image.memory(
                backgroundImageBytes!,
                // 🚀 Changed from contain to fill, because AspectRatio already guarantees the perfect shape!
                fit: BoxFit.fill, 
                errorBuilder: (context, error, stack) => const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.grey)),
              ),
            Positioned.fill(
              // RepaintBoundary keeps drawing repaints from also re-rasterizing
              // the background image layer (and vice versa) on every stroke.
              child: RepaintBoundary(
                child: CustomPaint(painter: MainPainter(context, objects, preview)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainPainter extends CustomPainter {
  final BuildContext context;
  final List<DrawingObject> objects;
  final DrawingObject? preview;
  
  MainPainter(this.context, this.objects, this.preview);

  Rect _calculateInternalBounds(List<DrawingObject> shapes) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void checkOffset(Offset p) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    void process(DrawingObject o) {
      checkOffset(o.start);
      checkOffset(o.end);
      if (o.points != null) {
        for (var p in o.points!) checkOffset(p);
      }
      if (o.internalShapes != null) {
        for (var child in o.internalShapes!) process(child);
      }
    }

    for (var o in shapes) process(o);

    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  void paint(ui.Canvas canvas, Size size) {
    final theme = Theme.of(context);
    final gridPaint = Paint()..color = theme.colorScheme.onSurface.withOpacity(0.05);
    for (double i = 0; i < size.width; i += 25) canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 25) canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    // 🚀 THE FIX: Calculate scale factor based on standard A4 height (1056)
    double scaleFactor = math.max(size.width, size.height) / 1056.0;
    if (scaleFactor < 1.0) scaleFactor = 1.0;

    // 🚀 THE FIX: Dynamically scale all visual handle variables
    final double dotOuter = 7.0 * scaleFactor;
    final double dotInner = 5.0 * scaleFactor;
    final double rotLineLength = 40.0 * scaleFactor;
    final double rotOuter = 12.0 * scaleFactor;
    final double rotInner = 10.0 * scaleFactor;
    final double rotIconFontSize = 16.0 * scaleFactor;
    final double selectionStroke = 1.0 * scaleFactor;
    final double inflatePencilSize = 4.0 * scaleFactor;

    void drawShape(DrawingObject obj, {bool isInternal = false}) {
      canvas.save();
      
      canvas.translate(obj.center.dx, obj.center.dy);
      canvas.rotate(obj.rotation);
      canvas.translate(-obj.center.dx, -obj.center.dy);

      final Rect rect = obj.rect;
      
      if (obj.type == DrawingType.text && obj.text != null) {        
        double fontSize = obj.fontSize;
        if (fontSize < 1) fontSize = 1;

        TextDecoration textDecoration = TextDecoration.none;

        if (obj.isUnderline && obj.isStrikethrough) {
          textDecoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
        } else if (obj.isUnderline) {
          textDecoration = TextDecoration.underline;
        } else if (obj.isStrikethrough) {
          textDecoration = TextDecoration.lineThrough;
        }

        final textStyle = TextStyle(
          color: obj.color, 
          fontSize: fontSize, 
          fontWeight: obj.isBold ? FontWeight.bold : FontWeight.normal, 
          fontStyle: obj.isItalic ? FontStyle.italic : FontStyle.normal,
          decoration: textDecoration, 
          decorationColor: obj.color, 
        );

        final textPainter = TextPainter(
          text: TextSpan(text: obj.text, style: textStyle),
          textDirection: TextDirection.ltr, 
          textAlign: TextAlign.left,
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

        if (!isInternal && obj.isSelected && obj.isCallout && obj.points != null) {
          Paint hP = Paint()..color = Colors.blue; 
          Paint wP = Paint()..color = Colors.white; 
          // 🚀 Used scaled dots
          canvas.drawCircle(obj.points![0], dotOuter, wP); canvas.drawCircle(obj.points![0], dotInner, hP);
          canvas.drawCircle(obj.points![1], dotOuter, wP); canvas.drawCircle(obj.points![1], dotInner, hP);
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
          
          if (obj.internalShapes != null && obj.internalShapes!.isNotEmpty) {
             Rect originalBounds = _calculateInternalBounds(obj.internalShapes!);
             
             if (originalBounds.width == 0 || originalBounds.height == 0) {
               originalBounds = originalBounds.inflate(50);
             }

             canvas.save();
             
             double scaleX = rect.width / originalBounds.width;
             double scaleY = rect.height / originalBounds.height;

             canvas.translate(rect.left, rect.top);
             canvas.scale(scaleX, scaleY);
             canvas.translate(-originalBounds.left, -originalBounds.top);

             for (var child in obj.internalShapes!) {
               drawShape(child, isInternal: true); 
             }
             
             canvas.restore();
             
          } else if (obj.customImage != null) {
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
          
          if (obj.type == DrawingType.polygon) {
            Path polygonPath = Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.right, rect.bottom)
              ..lineTo(rect.left, rect.bottom)
              ..close();
            canvas.drawPath(polygonPath, fillPaint);
          }
        }

        final strokePaint = Paint()
          ..color = obj.color 
          ..strokeWidth = obj.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        if ([DrawingType.brick, DrawingType.grid, DrawingType.horizontal, DrawingType.vertical, DrawingType.forwardDiag, DrawingType.reverseDiag, DrawingType.diamond, DrawingType.weave, DrawingType.dots, DrawingType.herringbone, DrawingType.concrete, DrawingType.shingles, DrawingType.insulation].contains(obj.type)) {
          canvas.save();
          canvas.clipRect(rect); 

          if (obj.fillColor != Colors.transparent) {
            canvas.drawRect(rect, Paint()..color = obj.fillColor.withOpacity(obj.opacity)..style = PaintingStyle.fill);
          }

          double spacing = 20.0; 

          if (obj.type == DrawingType.brick) {
            double bWidth = 40.0, bHeight = 16.0;
            int row = 0;
            for (double y = rect.top; y < rect.bottom; y += bHeight) {
              canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), strokePaint); 
              double startX = rect.left - (row % 2 != 0 ? bWidth / 2 : 0);
              for (double x = startX; x < rect.right + bWidth; x += bWidth) {
                canvas.drawLine(Offset(x, y), Offset(x, y + bHeight), strokePaint); 
              }
              row++;
            }
          }

          if (obj.type == DrawingType.horizontal || obj.type == DrawingType.grid) {
            for (double y = rect.top; y < rect.bottom; y += spacing) {
              canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), strokePaint);
            }
          }

          if (obj.type == DrawingType.vertical || obj.type == DrawingType.grid) {
            for (double x = rect.left; x < rect.right; x += spacing) {
              canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), strokePaint);
            }
          }

          if (obj.type == DrawingType.forwardDiag || obj.type == DrawingType.diamond) {
            for (double d = -rect.height; d < rect.width + rect.height; d += spacing) {
              canvas.drawLine(
                Offset(rect.left + d, rect.top), 
                Offset(rect.left + d + rect.height, rect.bottom), 
                strokePaint
              );
            }
          }

          if (obj.type == DrawingType.reverseDiag || obj.type == DrawingType.diamond) {
            for (double d = -rect.height; d < rect.width + rect.height; d += spacing) {
              canvas.drawLine(
                Offset(rect.left + d, rect.bottom), 
                Offset(rect.left + d + rect.height, rect.top), 
                strokePaint
              );
            }
          }

          if (obj.type == DrawingType.weave) {
            double wSize = 40.0; 
            double wSpace = 10.0; 
            
            for (double y = rect.top; y < rect.bottom; y += wSize) {
              for (double x = rect.left; x < rect.right; x += wSize) {
                int row = ((y - rect.top) / wSize).floor();
                int col = ((x - rect.left) / wSize).floor();
                if ((row + col) % 2 == 0) {
                  for (double i = y + wSpace; i < y + wSize; i += wSpace) {
                    canvas.drawLine(Offset(x, i), Offset(x + wSize, i), strokePaint);
                  }
                } else {
                  for (double i = x + wSpace; i < x + wSize; i += wSpace) {
                    canvas.drawLine(Offset(i, y), Offset(i, y + wSize), strokePaint);
                  }
                }
              }
            }
          }

          if (obj.type == DrawingType.dots) {
            math.Random rand = math.Random(obj.hashCode);
            double area = rect.width * rect.height;
            int numDots = (area * (obj.patternDensity / 100.0) * (1/15.0)).toInt(); 
            final dotPaint = Paint()..color = strokePaint.color..style = PaintingStyle.fill;
            for (int i = 0; i < numDots; i++) {
              double dx = rect.left + rand.nextDouble() * rect.width;
              double dy = rect.top + rand.nextDouble() * rect.height;
              canvas.drawCircle(Offset(dx, dy), strokePaint.strokeWidth / 2, dotPaint);
            }
          }

          if (obj.type == DrawingType.herringbone) {
            double size = 20.0;
            for (double y = rect.top - size; y < rect.bottom + size; y += size) {
               for (double x = rect.left - size; x < rect.right + size; x += size * 2) {
                   canvas.drawLine(Offset(x, y), Offset(x + size, y + size), strokePaint);
                   canvas.drawLine(Offset(x + size, y + size), Offset(x + size * 2, y), strokePaint);
                   canvas.drawLine(Offset(x + size, y + size), Offset(x + size, y + size * 2), strokePaint);
               }
            }
          }

          if (obj.type == DrawingType.concrete) {
            math.Random rand = math.Random(obj.hashCode); 
            double area = rect.width * rect.height;
            int numItems = (area * (obj.patternDensity / 100.0) * (1/12.0)).toInt(); 
            final dotPaint = Paint()..color = strokePaint.color..style = PaintingStyle.fill;
            for (int i = 0; i < numItems; i++) {
              double dx = rect.left + rand.nextDouble() * rect.width;
              double dy = rect.top + rand.nextDouble() * rect.height;
              if (rand.nextDouble() > 0.3) {
                canvas.drawCircle(Offset(dx, dy), strokePaint.strokeWidth / 2, dotPaint);
              } else {
                double s = strokePaint.strokeWidth * 2 + 1.5;
                Path rock = Path()..moveTo(dx, dy - s)..lineTo(dx + s, dy + s)..lineTo(dx - s, dy + s)..close();
                canvas.drawPath(rock, strokePaint);
              }
            }
          }

          if (obj.type == DrawingType.shingles) {
            math.Random rand = math.Random(obj.hashCode); 
            double rowH = 15.0;
            for (double y = rect.top; y < rect.bottom; y += rowH) {
              canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), strokePaint); 
              for (double x = rect.left; x < rect.right; x += 10.0 + rand.nextDouble() * 25.0) {
                canvas.drawLine(Offset(x, y), Offset(x, y + rowH), strokePaint);
              }
            }
          }

          if (obj.type == DrawingType.insulation) {
            double waveW = 30.0;
            double waveH = 15.0;
            Path wavePath = Path();
            for (double y = rect.top + waveH; y < rect.bottom + waveH; y += waveH * 2) {
              wavePath.moveTo(rect.left, y);
              for (double x = rect.left; x < rect.right; x += waveW) {
                wavePath.quadraticBezierTo(x + waveW / 4, y - waveH, x + waveW / 2, y);
                wavePath.quadraticBezierTo(x + waveW * 0.75, y + waveH, x + waveW, y);
              }
            }
            canvas.drawPath(wavePath, strokePaint);
          }

          canvas.drawRect(rect, strokePaint);
          canvas.restore();
        }

        else if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null && obj.points!.isNotEmpty) {
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

          // 🚀 Scaled pen preview dot
          if (!isInternal && obj == preview && obj.type == DrawingType.pen) {
            canvas.drawCircle(obj.points![0], 6 * scaleFactor, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 2 * scaleFactor);
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
        } else if (obj.type == DrawingType.polygon) {
          Path polygonPath = Path()
            ..moveTo(rect.center.dx, rect.top)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          canvas.drawPath(polygonPath, strokePaint);
        }
      }

      if (!isInternal && obj.isSelected) {
        final hP = Paint()..color = Colors.blue;
        final wP = Paint()..color = Colors.white;

        if (obj.type == DrawingType.line || obj.type == DrawingType.arrow) {
          // 🚀 Used scaled dots
          canvas.drawCircle(obj.start, dotOuter, wP);
          canvas.drawCircle(obj.start, dotInner, hP);
          canvas.drawCircle(obj.end, dotOuter, wP);
          canvas.drawCircle(obj.end, dotInner, hP);
        } else {
          // 🚀 Used scaled rotation line and dots
          Offset rotPos = Offset(rect.topCenter.dx, rect.topCenter.dy - rotLineLength);
          canvas.drawLine(rect.topCenter, rotPos, hP..strokeWidth = selectionStroke);
          canvas.drawCircle(rotPos, rotOuter, wP);
          canvas.drawCircle(rotPos, rotInner, hP);

          // 🚀 Used scaled icon font size
          final rotIcon = TextPainter(
            text: TextSpan(text: '\u21BB', style: TextStyle(color: Colors.white, fontSize: rotIconFontSize, fontWeight: FontWeight.bold, fontFamily: 'MaterialIcons')),
            textDirection: TextDirection.ltr,
          );
          rotIcon.layout();
          rotIcon.paint(canvas, rotPos - Offset(rotIcon.width / 2, rotIcon.height / 2));

          if (obj.type != DrawingType.pencil && obj.type != DrawingType.pen) {
            final points = [rect.topLeft, rect.topCenter, rect.topRight, rect.centerLeft, rect.centerRight, rect.bottomLeft, rect.bottomCenter, rect.bottomRight];
            for (var p in points) { 
              // 🚀 Used scaled dots
              canvas.drawCircle(p, dotOuter, wP); 
              canvas.drawCircle(p, dotInner, hP); 
            }
          } else {
            // 🚀 Used scaled inflation and stroke width
            canvas.drawRect(rect.inflate(inflatePencilSize), hP..style = PaintingStyle.stroke..strokeWidth = selectionStroke);
          }
        }
      }
      canvas.restore();
    }
    
    for (var obj in objects) drawShape(obj);
    if (preview != null) drawShape(preview!);
  }
  
  @override bool shouldRepaint(covariant MainPainter oldDelegate) => true;
}