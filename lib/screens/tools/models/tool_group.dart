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
  String id;
  String name;
  List<ToolItem> tools;

  ToolGroup({
    required this.id,
    required this.name,
    this.tools = const [],
  });
}