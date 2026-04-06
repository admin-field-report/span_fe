import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum DrawingType { line, rect, circle, pencil, text, arrow, pen, pin, customTool }

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
  double patternDensity; // 🚀 Re-added for the Dots/Concrete tools!

  String? base64Image;
  ui.Image? customImage; // Note: Cannot be JSON serialized directly, re-decoded from base64

  String? description;
  List<String>? tagIds;
  List<String>? imageUrls;

  String? toolId;

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
    this.patternDensity = 20.0,
    this.description,
    this.tagIds,
    this.imageUrls,
    this.base64Image,
    this.customImage,
    this.toolId,
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
        patternDensity: patternDensity,
        description: description,
        tagIds: tagIds != null ? List.from(tagIds!) : null,
        imageUrls: imageUrls != null ? List.from(imageUrls!) : null,
        base64Image: base64Image,
        customImage: customImage,
        toolId: toolId,
      );

  // ==========================================
  // 🚀 JSON PARSERS FOR SAVING & LOADING TOOLS
  // ==========================================

  factory DrawingObject.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, double fallback) {
      if (value == null) return fallback;
      return (value as num).toDouble();
    }

    Color parseColor(String? hexString, Color fallback) {
      if (hexString == null || hexString.isEmpty) return fallback;
      return Color(int.parse(hexString, radix: 16));
    }

    Offset parseOffset(Map<String, dynamic>? map) {
      if (map == null) return Offset.zero;
      return Offset(parseDouble(map['dx'], 0), parseDouble(map['dy'], 0));
    }

    DrawingType parsedType = DrawingType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => DrawingType.rect, 
    );

    List<Offset>? parsedPoints;
    if (json['points'] != null) {
      parsedPoints = (json['points'] as List).map((p) => parseOffset(p as Map<String, dynamic>)).toList();
    }

    return DrawingObject(
      type: parsedType,
      // We parse start/end, but default to offset.zero if using mock data that didn't have it
      start: json['start'] != null ? parseOffset(json['start']) : Offset.zero,
      end: json['end'] != null ? parseOffset(json['end']) : Offset.zero,
      points: parsedPoints,
      text: json['text'],
      strokeWidth: parseDouble(json['strokeWidth'], 2.0),
      color: parseColor(json['color'], Colors.black),
      fillColor: parseColor(json['fillColor'], Colors.transparent),
      borderColor: parseColor(json['borderColor'], Colors.transparent),
      opacity: parseDouble(json['opacity'], 1.0),
      rotation: parseDouble(json['rotation'], 0.0),
      fontSize: parseDouble(json['fontSize'], 24.0),
      isBold: json['isBold'] ?? false,
      isItalic: json['isItalic'] ?? false,
      isUnderline: json['isUnderline'] ?? false,
      isStrikethrough: json['isStrikethrough'] ?? false,
      isCallout: json['isCallout'] ?? false,
      patternDensity: parseDouble(json['patternDensity'], 20.0),
      description: json['description'],
      tagIds: json['tagIds'] != null ? List<String>.from(json['tagIds']) : null,
      imageUrls: json['imageUrls'] != null ? List<String>.from(json['imageUrls']) : null,
      base64Image: json['base64Image'],
      toolId: json['toolId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'start': {'dx': start.dx, 'dy': start.dy},
      'end': {'dx': end.dx, 'dy': end.dy},
      'rotation': rotation,
      'color': color.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'fillColor': fillColor.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'borderColor': borderColor.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'strokeWidth': strokeWidth,
      'opacity': opacity,
      'patternDensity': patternDensity,
      'fontSize': fontSize,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'isStrikethrough': isStrikethrough,
      'isCallout': isCallout,
      
      // Nullable fields
      if (points != null) 'points': points!.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      if (text != null) 'text': text,
      if (description != null) 'description': description,
      if (toolId != null) 'toolId': toolId,
      if (base64Image != null) 'base64Image': base64Image,
      if (tagIds != null) 'tagIds': tagIds,
      if (imageUrls != null) 'imageUrls': imageUrls,
    };
  }
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

class CustomTool {
  final String toolId;
  final String toolName;
  final String base64ImageUrl;
  final List<String> tagIds;
  ui.Image? decodedImage;

  CustomTool({required this.toolId, required this.toolName, required this.base64ImageUrl, required this.tagIds, this.decodedImage});
}

class CustomToolGroup {
  final String toolGroup;
  final List<CustomTool> tools;

  CustomToolGroup({required this.toolGroup, required this.tools});
}
