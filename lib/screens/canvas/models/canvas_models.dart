import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum DrawingType { line, rect, circle, pencil, text, arrow, pen, pin }

enum ResizeHandle { 
  none, topLeft, topCenter, topRight, centerLeft, centerRight, 
  bottomLeft, bottomCenter, bottomRight, rotation, body, calloutKnee, calloutTip 
}

class DrawingObject {
  Offset start;
  Offset end;
  List<Offset>? points; 
  String? text; 
  double strokeWidth;
  Color color;      
  Color fillColor;  
  Color borderColor;
  double opacity;   
  bool isSelected;
  DrawingType type;
  double rotation; 
  double fontSize;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrikethrough;
  bool isCallout; 

  String? description;
  List<String>? tagIds;
  List<String>? imageUrls;

  DrawingObject({
    required this.start,
    required this.end,
    required this.type,
    this.points,
    this.text,
    this.strokeWidth = 2.0,
    this.color = Colors.black,
    this.fillColor = Colors.transparent,
    this.borderColor = Colors.transparent,
    this.opacity = 1.0,
    this.isSelected = false,
    this.rotation = 0.0,
    this.fontSize = 24.0,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.isCallout = false,

    this.description,
    this.tagIds,
    this.imageUrls, 
  });

  Rect get rect {
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
        borderColor: borderColor, 
        opacity: opacity,
        isSelected: isSelected,
        rotation: rotation,
        fontSize: fontSize,
        isBold: isBold,
        isItalic: isItalic,
        isUnderline: isUnderline,
        isStrikethrough: isStrikethrough,
        isCallout: isCallout, 
        description: description,
        tagIds: tagIds != null ? List.from(tagIds!) : null,
        imageUrls: imageUrls != null ? List.from(imageUrls!) : null,
      );
}

class PageData {
  String pageId;
  Uint8List? backgroundImageBytes;
  bool hasLoadedAnnotations; 
  List<DrawingObject> objects = [];
  List<List<DrawingObject>> undoStack = [];
  List<List<DrawingObject>> redoStack = [];

  PageData({
    required this.pageId,
    this.backgroundImageBytes,
    this.hasLoadedAnnotations = false,
  }); 
}

class ProjectTag {
  final String id;
  final String name;
  final Color color;

  ProjectTag({required this.id, required this.name, required this.color});

  factory ProjectTag.fromJson(Map<String, dynamic> json) {
    Color parsedColor = Colors.blue;
    if (json['color'] != null) {
      String hex = json['color'].toString().replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      parsedColor = Color(int.parse(hex, radix: 16));
    }
    
    return ProjectTag(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      color: parsedColor,
    );
  }
}