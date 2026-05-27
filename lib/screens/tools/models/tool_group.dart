import 'dart:convert';

class ToolItem {
  String id;
  String name;
  String canvasJson;
  String custom_tool_group_item_id;

  ToolItem({
    required this.id,
    required this.name,
    required this.canvasJson,
    required this.custom_tool_group_item_id,
  });

  factory ToolItem.fromJson(Map<String, dynamic> json) {
    final rawJsonData = json['jsonData'] ?? json['json_data'];
    
    String canvasDataString = '[]'; 

    if (rawJsonData != null) {
      if (rawJsonData is String) {
        canvasDataString = rawJsonData;
      } else {
        canvasDataString = jsonEncode(rawJsonData);
      }
    }

    return ToolItem(
      id: json['tool_id'] ?? json['id'] ?? '',
      name: json['name'] ?? 'Unnamed Tool',
      canvasJson: canvasDataString,
      custom_tool_group_item_id: json['custom_tool_group_item_id'] ?? '',
    );
  }
}

class ToolGroup {
  final String id;
  String name;
  List<ToolItem> tools;

  ToolGroup({
    required this.id,
    required this.name,
    this.tools = const [], 
  });

  factory ToolGroup.fromJson(Map<String, dynamic> json) {
    return ToolGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Group',
      tools: [],
    );
  }
}

