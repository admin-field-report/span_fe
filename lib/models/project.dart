class Project {
  final String id;
  final String name;
  final String description;
  final DateTime createDate;

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.createDate,
  });
  
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      createDate: json['create_time'] != null 
          ? DateTime.parse(json['create_time']) 
          : DateTime.now(),
    );
  }
}

class ProjectInspection {
  final String id;
  final String? name;
  final DateTime createTime;
  final String creatorId;

  ProjectInspection({
    required this.id,
    this.name,
    required this.createTime,
    required this.creatorId,
  });

  factory ProjectInspection.fromJson(Map<String, dynamic> json) {
    return ProjectInspection(
      id: json['id'],
      name: json['name'],
      createTime: DateTime.parse(json['create_time']),
      creatorId: json['created_by'],
    );
  }
}

class ProjectDocument {
  final String id;
  final String templateId;
  final String documentUrl;
  final String? documentName;
  final DateTime createTime;
  final String createdBy;

  ProjectDocument({
    required this.id,
    required this.templateId,
    required this.documentUrl,
    this.documentName,
    required this.createTime,
    required this.createdBy,
  });

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    return ProjectDocument(
      id: json['id'] ?? '', 
      templateId: json['template_id'] ?? '',
      documentUrl: json['document_url'] ?? '',
      documentName: json['document_name'],
      createTime: DateTime.parse(json['create_time'] ?? DateTime.now().toIso8601String()),
      createdBy: json['created_by'] ?? 'Unknown',
    );
  }
}