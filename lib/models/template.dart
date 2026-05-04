import '../screens/tools/models/tool_group.dart';

class Template {
  final String id;
  final String name;
  final String userId;
  final String companyId;
  final DateTime createDate;

  Template({
    required this.id,
    required this.name,
    required this.userId,
    required this.companyId,
    required this.createDate,
  });
  
  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      userId: json['user_id'] ?? '',
      companyId: json['company_id'] ?? '',
      createDate: json['create_time'] != null 
          ? DateTime.parse(json['create_time']) 
          : DateTime.now(),
    );
  }
}


class TemplateToolGroup {
  final String customToolGroupId;
  final String name;
  final List<ToolItem> tools;

  TemplateToolGroup({
    required this.customToolGroupId,
    required this.name,
    required this.tools,
  });

  factory TemplateToolGroup.fromJson(Map<String, dynamic> json) {
    return TemplateToolGroup(
      customToolGroupId: json['custom_tool_group_id'] ?? '',
      name: json['custom_tool_group_name'] ?? 'Unnamed Tool Set',
      tools: (json['tools'] as List<dynamic>?)
              ?.map((t) => ToolItem.fromJson(t))
              .toList() ?? [],
    );
  }
}

class TemplateDocument {
  final String id;
  final String templateId;
  final String documentUrl;
  final String? documentName;
  final DateTime? createTime;

  TemplateDocument({
    required this.id,
    required this.templateId,
    required this.documentUrl,
    this.documentName,
    this.createTime,
  });

  factory TemplateDocument.fromJson(Map<String, dynamic> json) {
    return TemplateDocument(
      id: json['id'] ?? '',
      templateId: json['template_id'] ?? '',
      documentUrl: json['document_url'] ?? '',
      documentName: json['document_name'],
      createTime: json['create_time'] != null ? DateTime.tryParse(json['create_time']) : null,
    );
  }

  String get displayName {
    if (documentName != null && documentName!.trim().isNotEmpty) {
      return documentName!;
    }
    if (documentUrl.isNotEmpty) {
      return documentUrl.split('/').last;
    }
    return 'Unnamed Document';
  }
  
  String get formattedDate {
    if (createTime == null) return "Unknown date";
    return "${createTime!.year}-${createTime!.month.toString().padLeft(2, '0')}-${createTime!.day.toString().padLeft(2, '0')}";
  }
}