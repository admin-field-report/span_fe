import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/project.dart';
import '../../../core/api_service.dart';
import '../../auth/controllers/auth_controller.dart';


class ProjectController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Project> _projects = [];
  bool _isLoading = false;

  List<ProjectInspection> _inspections = [];
  bool _isInspectionsLoading = false;

  List<ProjectDocument> _documents = [];
  bool _isDocumentsLoading = false;

  List<InspectionMediaGroup> _groupedMedia = [];
  bool _isMediaLoading = false;

  List<ProjectReport> _reports = [];
  bool _isReportLoading = false;

  String? _error;

  List<Project> get projects => _projects;
  bool get isLoading => _isLoading;

  List<ProjectInspection> get inspections => _inspections;
  bool get isInspectionsLoading => _isInspectionsLoading;

  List<ProjectDocument> get documents => _documents;
  bool get isDocumentsLoading => _isDocumentsLoading;

  List<InspectionMediaGroup> get groupedMedia => _groupedMedia;
  bool get isMediaLoading => _isMediaLoading;

  List<ProjectReport> get reports => _reports;
  bool get isReportLoading => _isReportLoading;

  String? get error => _error;
  
  Future<void> getAllProjects() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/project/user/${authController.user?.id}');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _projects = dataList.map((item) => Project.fromJson(item)).toList();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> getAllInspections(String projectId) async {
    _isInspectionsLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/inspection/project/$projectId');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _inspections = dataList.map((item) => ProjectInspection.fromJson(item)).toList();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isInspectionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> getAllDocuments(String projectId) async {
    _isDocumentsLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/templateDocument/project/$projectId');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _documents = dataList.map((item) => ProjectDocument.fromJson(item)).toList();
      }
      debugPrint("Loaded ${_documents.length} documents for project $projectId");
    } catch (e) {
      _error = e.toString();
      debugPrint("Error loading documents for project $projectId: $_error");
    } finally {
      _isDocumentsLoading = false;
      notifyListeners();
    }
  }

  Future<void> getAllProjectMedia(String projectId) async {
  _isMediaLoading = true;
  notifyListeners();

  try {
    final response = await _apiService.get('/presignedurl/canvas-json-images/$projectId');
    final List<dynamic> responseData = jsonDecode(response.body);

    List<InspectionMediaGroup> groups = [];

    for (var inspectionJson in responseData) {
      List<ProjectMedia> itemsInThisInspection = [];
      final List canvasItems = inspectionJson['canvas_page_item'] ?? [];

      for (var item in canvasItems) {
        final List images = item['canvas_page_item_image'] ?? [];
        final List tagsJson = item['canvas_page_item_tag'] ?? [];
        
        final List<ProjectMediaTag> itemTags = 
            tagsJson.map((t) => ProjectMediaTag.fromJson(t)).toList();

        for (var img in images) {
          itemsInThisInspection.add(ProjectMedia(
            id: "${item['id']}_${img['id'] ?? itemsInThisInspection.length}",
            imageUrl: img['signedUrl'],
            tags: itemTags,
          ));
        }
      }

      if (itemsInThisInspection.isNotEmpty) {
        groups.add(InspectionMediaGroup(
          inspectionId: inspectionJson['id'],
          inspectionName: inspectionJson['name'],
          createTime: DateTime.parse(inspectionJson['create_time']),
          items: itemsInThisInspection,
        ));
      }
    }
    _groupedMedia = groups;
  } catch (e) {
    _error = e.toString();
  } finally {
    _isMediaLoading = false;
    notifyListeners();
  }
}

  Future<void> getAllReports(String projectId) async {
    _isReportLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/report/getByProjectId/$projectId');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      final List dataList = responseData['data'] ?? [];
      _reports = dataList.map((item) => ProjectReport.fromJson(item)).toList();

    } catch (e) {
      _error = e.toString();
    } finally {
      _isReportLoading = false;
      notifyListeners();
    }
  }
}

final projectController = ProjectController();