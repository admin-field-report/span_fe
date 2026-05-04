import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum DrawingType { 
  pencil, pen, line, arrow, rect, circle, text, pin, customTool, polygon,
  brick, grid, horizontal, vertical, forwardDiag, reverseDiag, diamond, weave, dots,
  herringbone, concrete, shingles, insulation
}
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

  String? base64Image;
  ui.Image? customImage;

  String? description;
  List<String>? tagIds;
  List<String>? imageUrls;

  String? toolId;

  double patternDensity = 20.0;

  List<DrawingObject>? internalShapes; 
  Rect? originalBounds;

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

    this.base64Image,
    this.customImage,

    this.toolId,

    this.internalShapes,
    this.originalBounds,
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
        base64Image: base64Image,
        customImage: customImage,
        internalShapes: internalShapes != null ? List.from(internalShapes!) : null,
        originalBounds: originalBounds,
      );

  // 🚀 1. TO JSON: Converts the object into a Map for the API
  Map<String, dynamic> toJson() {
    return {
      'type': type.name, // Converts enum to string (e.g., 'brick', 'pencil')
      'start': {'dx': start.dx, 'dy': start.dy},
      'end': {'dx': end.dx, 'dy': end.dy},
      if (points != null) 'points': points!.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      if (text != null) 'text': text,
      'strokeWidth': strokeWidth,
      // Convert colors to ARGB Hex strings
      'color': color.value.toRadixString(16).padLeft(8, '0'),
      'fillColor': fillColor.value.toRadixString(16).padLeft(8, '0'),
      'borderColor': borderColor.value.toRadixString(16).padLeft(8, '0'),
      'opacity': opacity,
      'rotation': rotation,
      'fontSize': fontSize,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'isStrikethrough': isStrikethrough,
      'isCallout': isCallout,
      if (description != null) 'description': description,
      if (tagIds != null) 'tagIds': tagIds,
      if (imageUrls != null) 'imageUrls': imageUrls,
      if (base64Image != null) 'base64Image': base64Image,
      if (toolId != null) 'toolId': toolId,
      'patternDensity': patternDensity,
      // Note: customImage (ui.Image) is NOT saved because raw memory textures cannot be serialized.
      // It will be re-decoded from base64Image when fromJson is called!
    };
  }

  // 🚀 2. FROM JSON: Rebuilds the DrawingObject from the API data
  factory DrawingObject.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse Colors from hex strings
    Color parseColor(dynamic colorVal, Color defaultColor) {
      if (colorVal == null) return defaultColor;
      if (colorVal is int) return Color(colorVal);
      if (colorVal is String) {
        String hex = colorVal.replaceAll('#', '');
        if (hex.length == 6) hex = 'FF$hex'; // Add alpha if missing
        return Color(int.parse(hex, radix: 16));
      }
      return defaultColor;
    }

    // Helper to safely parse Offsets
    Offset parseOffset(dynamic val) {
      if (val == null) return Offset.zero;
      return Offset((val['dx'] ?? 0).toDouble(), (val['dy'] ?? 0).toDouble());
    }

    // Match string to DrawingType Enum
    DrawingType parseType(String? typeStr) {
      if (typeStr == null) return DrawingType.pencil;
      return DrawingType.values.firstWhere(
        (e) => e.name == typeStr, 
        orElse: () => DrawingType.pencil
      );
    }

    List<Offset>? parsedPoints;
    if (json['points'] != null) {
      parsedPoints = (json['points'] as List).map((p) => parseOffset(p)).toList();
    }

    var obj = DrawingObject(
      type: parseType(json['type']),
      start: parseOffset(json['start']),
      end: parseOffset(json['end']),
      points: parsedPoints,
      text: json['text'],
      strokeWidth: (json['strokeWidth'] ?? 2.0).toDouble(),
      color: parseColor(json['color'], Colors.black),
      fillColor: parseColor(json['fillColor'], Colors.transparent),
      borderColor: parseColor(json['borderColor'], Colors.transparent),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      rotation: (json['rotation'] ?? 0.0).toDouble(),
      fontSize: (json['fontSize'] ?? 24.0).toDouble(),
      isBold: json['isBold'] ?? false,
      isItalic: json['isItalic'] ?? false,
      isUnderline: json['isUnderline'] ?? false,
      isStrikethrough: json['isStrikethrough'] ?? false,
      isCallout: json['isCallout'] ?? false,
      description: json['description'],
      tagIds: json['tagIds'] != null ? List<String>.from(json['tagIds']) : null,
      imageUrls: json['imageUrls'] != null ? List<String>.from(json['imageUrls']) : null,
      base64Image: json['base64Image'],
      toolId: json['toolId'],
    );
    
    if (json['patternDensity'] != null) {
      obj.patternDensity = json['patternDensity'].toDouble();
    }
    
    return obj;
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
  final List<String> tagIds;
  
  final List<DrawingObject> toolObjects; 

  CustomTool({
    required this.toolId, 
    required this.toolName, 
    required this.tagIds, 
    this.toolObjects = const []
  });
}

class CustomToolGroup {
  final String toolGroup;
  final List<CustomTool> tools;

  CustomToolGroup({required this.toolGroup, required this.tools});
}