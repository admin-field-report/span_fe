import 'package:flutter/material.dart';

Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

String colorToHex(Color color) {
  return '#${color.value.toRadixString(16).substring(2, 8).toUpperCase()}';
}

class AppTemplate {
  final String id;
  final String name;

  AppTemplate({required this.id, required this.name});

  factory AppTemplate.fromJson(Map<String, dynamic> json) {
    return AppTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class AppTag {
  final String id;
  final String name;
  final Color color;

  AppTag({required this.id, required this.name, required this.color});

  factory AppTag.fromJson(Map<String, dynamic> json) {
    return AppTag(
      id: json['id'] ?? json['tag_id'] ?? '', 
      name: json['name'] ?? '',
      // color: json['color'] != null ? hexToColor(json['color']) : Colors.grey,
      color: Colors.grey,
    );
  }
}

class AppTagGroup {
  final String id;
  final String name;
  List<AppTag> tags;
  List<AppTemplate> templates; 

  AppTagGroup({
    required this.id, 
    required this.name, 
    this.tags = const [], 
    this.templates = const []
  });

  factory AppTagGroup.fromJson(Map<String, dynamic> json) {
    return AppTagGroup(
      id: json['tag_group_id'] ?? json['id'] ?? '',
      name: json['tag_group_name'] ?? json['name'] ?? '',
      tags: json['tags'] != null 
          ? (json['tags'] as List).map((t) => AppTag.fromJson(t)).toList() 
          : [],
      templates: json['templates'] != null 
          ? (json['templates'] as List).map((t) => AppTemplate.fromJson(t)).toList() 
          : [],
    );
  }
}