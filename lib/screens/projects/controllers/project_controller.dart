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

  String? _error;

  List<Project> get projects => _projects;
  bool get isLoading => _isLoading;

  List<ProjectInspection> get inspections => _inspections;
  bool get isInspectionsLoading => _isInspectionsLoading;

  List<ProjectDocument> get documents => _documents;
  bool get isDocumentsLoading => _isDocumentsLoading;

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
}

final projectController = ProjectController();