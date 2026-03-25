import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/canvas_models.dart';

Future<void> exportCanvasToPdf({
  required BuildContext context,
  required bool exportAll,
  required List<String> pages,
  required String currentPage,
  required Map<String, PageData> pageDataMap,
}) async {
  final pdf = pw.Document();
  
  final List<String> targets = exportAll ? pages : [currentPage];
  final Size screenSize = MediaQuery.of(context).size;
  final pdfFormat = PdfPageFormat(screenSize.width, screenSize.height);

  for (var pageName in targets) {
    final data = pageDataMap[pageName]!;

    pdf.addPage(
      pw.Page(
        pageFormat: pdfFormat,
        margin: pw.EdgeInsets.zero, 
        build: (pw.Context context) {
          return pw.SizedBox(
            width: pdfFormat.width,
            height: pdfFormat.height,
            child: pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Container(color: PdfColors.white)),
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      for (var obj in data.objects) {
                        final pdfColor = PdfColor.fromInt(obj.color.value);
                        final pdfFill = PdfColor.fromInt(obj.fillColor.value);
                        final pdfBorder = PdfColor.fromInt(obj.borderColor.value);
                        final double stroke = obj.strokeWidth;

                        final cx = obj.center.dx;
                        final cy = obj.center.dy;
                        final double angle = obj.rotation;

                        Offset rot(Offset p) {
                          if (angle == 0) return p;
                          final dx = p.dx - cx;
                          final dy = p.dy - cy;
                          return Offset(
                            dx * math.cos(angle) - dy * math.sin(angle) + cx,
                            dx * math.sin(angle) + dy * math.cos(angle) + cy
                          );
                        }

                        if (obj.type == DrawingType.text && obj.isCallout && obj.points != null && obj.points!.length >= 2) {
                          final strokeC = pdfBorder != PdfColor.fromInt(Colors.transparent.value) ? pdfBorder : PdfColor.fromInt(Colors.redAccent.value);
                          canvas.setStrokeColor(strokeC);
                          canvas.setLineWidth(stroke);
                          
                          final basePoint = rot(Offset(obj.rect.center.dx, obj.rect.bottom));
                          final knee = rot(obj.points![0]);
                          final tip = rot(obj.points![1]);

                          canvas.moveTo(basePoint.dx, basePoint.dy);
                          canvas.lineTo(knee.dx, knee.dy);
                          canvas.lineTo(tip.dx, tip.dy);
                          canvas.strokePath();
                        }

                        if (obj.type == DrawingType.text) {
                          if (obj.fillColor != Colors.transparent || obj.borderColor != Colors.transparent) {
                            final tl = rot(obj.rect.topLeft);
                            final tr = rot(obj.rect.topRight);
                            final br = rot(obj.rect.bottomRight);
                            final bl = rot(obj.rect.bottomLeft);
                            
                            canvas.moveTo(tl.dx, tl.dy);
                            canvas.lineTo(tr.dx, tr.dy);
                            canvas.lineTo(br.dx, br.dy);
                            canvas.lineTo(bl.dx, bl.dy);
                            canvas.lineTo(tl.dx, tl.dy); 
                            
                            final strokeC = pdfBorder != PdfColor.fromInt(Colors.transparent.value) ? pdfBorder : pdfColor;
                            canvas.setStrokeColor(strokeC);
                            canvas.setLineWidth(stroke);

                            if (obj.fillColor != Colors.transparent) {
                              canvas.setFillColor(pdfFill);
                              canvas.fillAndStrokePath();
                            } else {
                              canvas.strokePath();
                            }
                          }
                          continue; 
                        }

                        canvas.setLineWidth(stroke);
                        final actualBorderC = pdfBorder != PdfColor.fromInt(Colors.transparent.value) ? pdfBorder : pdfColor;

                        if (obj.type == DrawingType.rect) {
                          final tl = rot(obj.rect.topLeft);
                          final tr = rot(obj.rect.topRight);
                          final br = rot(obj.rect.bottomRight);
                          final bl = rot(obj.rect.bottomLeft);

                          canvas.moveTo(tl.dx, tl.dy);
                          canvas.lineTo(tr.dx, tr.dy);
                          canvas.lineTo(br.dx, br.dy);
                          canvas.lineTo(bl.dx, bl.dy);
                          canvas.lineTo(tl.dx, tl.dy);
                          
                          canvas.setStrokeColor(actualBorderC);
                          if (obj.fillColor != Colors.transparent) {
                            canvas.setFillColor(pdfFill);
                            canvas.fillAndStrokePath();
                          } else {
                            canvas.strokePath();
                          }
                        } else if (obj.type == DrawingType.circle) {
                          canvas.setStrokeColor(actualBorderC);
                          canvas.drawEllipse(cx, cy, obj.rect.width / 2, obj.rect.height / 2);
                          if (obj.fillColor != Colors.transparent) {
                            canvas.setFillColor(pdfFill);
                            canvas.fillAndStrokePath();
                          } else {
                            canvas.strokePath();
                          }
                        } else if (obj.type == DrawingType.line || obj.type == DrawingType.arrow) {
                          canvas.setStrokeColor(pdfColor);
                          final rStart = rot(obj.start);
                          final rEnd = rot(obj.end);
                          
                          canvas.moveTo(rStart.dx, rStart.dy);
                          canvas.lineTo(rEnd.dx, rEnd.dy);

                          if (obj.type == DrawingType.arrow) {
                            const double arrowLength = 15.0;
                            const double arrowAngle = math.pi / 6;
                            double angle2 = math.atan2(rEnd.dy - rStart.dy, rEnd.dx - rStart.dx);
                            
                            canvas.moveTo(rEnd.dx, rEnd.dy);
                            canvas.lineTo(rEnd.dx - arrowLength * math.cos(angle2 - arrowAngle), rEnd.dy - arrowLength * math.sin(angle2 - arrowAngle));
                            canvas.moveTo(rEnd.dx, rEnd.dy);
                            canvas.lineTo(rEnd.dx - arrowLength * math.cos(angle2 + arrowAngle), rEnd.dy - arrowLength * math.sin(angle2 + arrowAngle));
                          }
                          canvas.strokePath();
                        } else if ((obj.type == DrawingType.pencil || obj.type == DrawingType.pen) && obj.points != null && obj.points!.isNotEmpty) {
                          canvas.setStrokeColor(pdfColor);
                          final firstPoint = rot(obj.points!.first);
                          canvas.moveTo(firstPoint.dx, firstPoint.dy);
                          
                          for (var p in obj.points!) {
                            final rp = rot(p);
                            canvas.lineTo(rp.dx, rp.dy);
                          }

                          if (obj.fillColor != Colors.transparent && obj.points!.length > 2) {
                            canvas.setFillColor(pdfFill);
                            canvas.fillAndStrokePath();
                          } else {
                            canvas.strokePath();
                          }
                        }
                      }
                    },
                  ),
                ),
                ...data.objects.where((o) => o.type == DrawingType.text && o.text != null).map((obj) {
                  return pw.Positioned(
                    left: obj.rect.left + 10, 
                    top: obj.rect.top + 10,
                    child: pw.Text(
                      obj.text!,
                      style: pw.TextStyle(
                        color: PdfColor.fromInt(obj.color.value),
                        fontSize: obj.fontSize,
                        fontWeight: obj.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                        fontStyle: obj.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: exportAll ? 'Project_Full_Export' : '${currentPage}_Export',
  );
}