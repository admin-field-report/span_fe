import 'package:flutter/material.dart';

// -- Project
class Project {
  final String id;
  final String name;
  final String description;
  final DateTime createDate;
  final String clientId;
  final String clientName;

  Project({
    required this.id,
    required this.name,
    required this.description,
    required this.createDate,
    required this.clientId,
    required this.clientName
  });
  
  // factory Project.fromJson(Map<String, dynamic> json) {
  //   return Project(
  //     id: json['id'] ?? '',
  //     name: json['name'] ?? '',
  //     description: json['description'] ?? '',
  //     clientId: json['client_id'] ?? '',
  //     clientName: json['client'] ? json['client']['name'] : '',
  //     createDate: json['create_time'] != null 
  //         ? DateTime.parse(json['create_time']) 
  //         : DateTime.now(),
  //   );
  // }
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      clientId: json['client_id'] ?? '',
      clientName: json['client']?['name'] ?? '', 
      createDate: json['create_time'] != null 
          ? (DateTime.tryParse(json['create_time']) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

// -- Inspections 
class ProjectInspection {
  final String id;
  final String name;
  final DateTime createTime;
  final String creatorId;

  ProjectInspection({
    required this.id,
    required this.name,
    required this.createTime,
    required this.creatorId,
  });

  factory ProjectInspection.fromJson(Map<String, dynamic> json) {
    return ProjectInspection(
      id: json['id'],
      name: json['name'] ?? 'Unknown',
      createTime: DateTime.parse(json['create_time']),
      creatorId: json['created_by'],
    );
  }
}

// -- Documents 
class ProjectDocument {
  final String id;
  final String templateId;
  final String documentUrl;
  final String documentName;
  final DateTime createTime;
  final String createdBy;
  final String status;

  ProjectDocument({
    required this.id,
    required this.templateId,
    required this.documentUrl,
    required this.documentName,
    required this.createTime,
    required this.createdBy,
    required this.status
  });

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    return ProjectDocument(
      id: json['id'] ?? '', 
      templateId: json['template_id'] ?? '',
      documentUrl: json['document_url'] ?? '',
      documentName: json['document_name'] ?? 'Unknown',
      createTime: DateTime.parse(json['create_time'] ?? DateTime.now().toIso8601String()),
      createdBy: json['created_by'] ?? 'Unknown',
      status: json['status'] ?? ''
    );
  }
}


// -- Media
class ProjectMediaTag {
  final String name;
  final Color color;

  ProjectMediaTag({required this.name, required this.color});

  factory ProjectMediaTag.fromJson(Map<String, dynamic> json) {
    final tagMap = json['tag'] ?? {};
    String hexColor = tagMap['color'] ?? "#FFFFFF";
    
    // Convert #RRGGBB to 0xFFRRGGBB
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) hexColor = 'FF$hexColor';

    return ProjectMediaTag(
      name: tagMap['name'] ?? 'Unknown',
      color: Color(int.parse('0x$hexColor')),
    );
  }
}

class ProjectMedia {
  final String id;
  final String imageUrl;
  final List<ProjectMediaTag> tags;

  ProjectMedia({required this.id, required this.imageUrl, required this.tags});
}

class InspectionMediaGroup {
  final String inspectionId;
  final String? inspectionName;
  final DateTime createTime;
  final List<ProjectMedia> items;

  InspectionMediaGroup({
    required this.inspectionId,
    this.inspectionName,
    required this.createTime,
    required this.items,
  });
}

// -- Reports
class ProjectReport {
  final String id;
  final String name;
  final DateTime createDate;

  /// Present once a report was generated via the Eve Word flow — `'docx'`
  /// vs the historical HTML/skill reports (which leave this `null`).
  final String? reportFormat;

  /// Signed/persisted URL for the filled `.docx`, when available. This is
  /// optional and best-effort: the authoritative source for a fresh signed
  /// URL is always `EveGenerateDocxApiService.getReportById`, since S3
  /// signed URLs expire.
  final String? reportDocxUrl;

  ProjectReport({
    required this.id,
    required this.name,
    required this.createDate,
    this.reportFormat,
    this.reportDocxUrl,
  });
  
  factory ProjectReport.fromJson(Map<String, dynamic> json) {
    return ProjectReport(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      createDate: json['create_time'] != null 
          ? DateTime.parse(json['create_time']) 
          : DateTime.now(),
      reportFormat: json['report_format']?.toString(),
      reportDocxUrl: json['download_urls'] is Map
          ? (json['download_urls'] as Map)['filled_docx']?.toString()
          : json['filled_docx_url']?.toString(),
    );
  }
}