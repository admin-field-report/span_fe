class ToolItem {
  String id;
  String name;
  String canvasJson;

  ToolItem({
    required this.id,
    required this.name,
    required this.canvasJson,
  });
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

