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

  Project? currentProject;
  bool isProjectDetailsLoading = false;
  String? projectDetailsError;
  
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
          
          // 🚀 NEW: Sort the list descending by createDate (newest first)
          _projects.sort((a, b) => b.createDate.compareTo(a.createDate));
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
      final response = await _apiService.get('/projectDocument/project/$projectId');

      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _documents = dataList.map((item) => ProjectDocument.fromJson(item)).toList();

        _documents.sort((a, b) {
          if (a.createTime == null || b.createTime == null) return 0;
          return b.createTime!.compareTo(a.createTime!);
        });
      }
      
    } catch (e) {
      _error = e.toString();
    } finally {
      _isDocumentsLoading = false;
      notifyListeners();
    }
  }

  Future<void> getAllProjectMedia(String projectId) async {
    _isMediaLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/presignedurl/project-media/$projectId');
      final List<dynamic> responseData = jsonDecode(response.body);

      List<InspectionMediaGroup> groups = [];

      for (var inspectionJson in responseData) {
        List<ProjectMedia> itemsInThisInspection = [];
        
        // 1. Parse Canvas Items (Your existing code)
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

        // 2. 🚀 Parse Project Document Images (The new code)
        final List projectDocuments = inspectionJson['project_document'] ?? [];
        for (var doc in projectDocuments) {
          final List images = doc['canvasPageItemImages'] ?? [];
          final List tagsJson = doc['canvasPageItemTags'] ?? [];
          
          final List<ProjectMediaTag> itemTags = 
              tagsJson.map((t) => ProjectMediaTag.fromJson(t)).toList();
          
          for (var img in images) {
            itemsInThisInspection.add(ProjectMedia(
              id: "${doc['id']}_${img['id'] ?? itemsInThisInspection.length}",
              imageUrl: img['signedUrl'],
              tags: itemTags,
            ));
          }
        }

        // 3. Add to group if we found any media from either source
        if (itemsInThisInspection.isNotEmpty) {
          groups.add(InspectionMediaGroup(
            inspectionId: inspectionJson['id'],
            inspectionName: inspectionJson['name'], // Note: This might be null based on your JSON
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

      // 🚀 NEW: Sort the list descending by createDate (newest first)
      _reports.sort((a, b) => b.createDate.compareTo(a.createDate));

    } catch (e) {
      _error = e.toString();
    } finally {
      _isReportLoading = false;
      notifyListeners();
    }
  }


  // ----------------------------------------------------------------
  // PROJECT DETAILS APIS
  // ----------------------------------------------------------------

  Future<void> fetchProjectDetails(String projectId) async {
    // 1. SMART CACHE: Try to find the project in memory first (Instant Load)
    try {
      currentProject = projects.firstWhere((p) => p.id == projectId);
      isProjectDetailsLoading = false;
      projectDetailsError = null;
      notifyListeners();
      return; // STOP HERE! No API call needed!
    } catch (e) {
      // Not in memory (e.g., user refreshed the browser). Proceed to API call.
    }

    // 2. FALLBACK: Hit the API only if memory failed
    isProjectDetailsLoading = true;
    projectDetailsError = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/project/$projectId');
      final resData = jsonDecode(response.body);

      if (resData['success'] == true && resData['data'] != null) {
        currentProject = Project.fromJson(resData['data']);
      } else {
        currentProject = null;
        projectDetailsError = "Failed to load project data.";
      }
    } catch (e) {
      currentProject = null;
      projectDetailsError = "A network error occurred.";
    } finally {
      isProjectDetailsLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------------
  // PROJECT SETTINGS APIS
  // ----------------------------------------------------------------

  Future<void> getProjectSettings(String projectId) async {
    try {
      // Fetch assigned Tags
      final tagRes = await _apiService.get('/projectTagGroup/$projectId');
      // Fetch assigned Tools
      final toolRes = await _apiService.get('/projectCustomToolGroup/$projectId');
      
      // TODO: Parse these responses and store the assigned IDs in your state.
      // e.g., assignedTagGroupIds = parsed IDs;
      // e.g., assignedToolGroupIds = parsed IDs;
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching project settings: $e");
    }
  }

  Future<bool> manageProjectTagGroups(String projectId, List<String> selectedTagIds) async {
    try {
      // 🚀 Format list into the required Map: {"id_1": 0, "id_2": 1}
      final Map<String, int> formattedMap = {};
      for (int i = 0; i < selectedTagIds.length; i++) {
        formattedMap[selectedTagIds[i]] = i;
      }

      final payload = {
        "project_id": projectId,
        "tag_group_id_list": formattedMap,
      };

      final response = await _apiService.post('/projectTagGroup/manage', payload);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint("Error managing tags: $e");
      return false;
    }
  }

  Future<bool> manageProjectToolGroups(String projectId, List<String> selectedToolIds) async {
    try {
      // 🚀 Format list into the required Map: {"id_1": 0, "id_2": 1}
      final Map<String, int> formattedMap = {};
      for (int i = 0; i < selectedToolIds.length; i++) {
        formattedMap[selectedToolIds[i]] = i;
      }

      final payload = {
        "project_id": projectId,
        "custom_tool_group_id_list": formattedMap,
      };

      final response = await _apiService.post('/projectCustomToolGroup/manage', payload);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint("Error managing tools: $e");
      return false;
    }
  }


  // ----------------------------------------------------------------
  // FETCH MASTER LISTS FOR SETTINGS
  // ----------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getCompanyTagGroups() async {
    try {
      final response = await _apiService.get('/tagGroupItem/company');
      final resData = jsonDecode(response.body);

      if (resData['success'] == true && resData['data'] != null) {
        return (resData['data'] as List).map((item) => {
          'id': item['tag_group_id'],
          'name': item['tag_group_name'],
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching company tag groups: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCompanyToolGroups() async {
    try {
      final response = await _apiService.get('/customToolGroup/company');
      final resData = jsonDecode(response.body);

      if (resData['message'] != null && resData['data'] != null) {
        return (resData['data'] as List).map((item) => {
          'id': item['id'],
          'name': item['name'],
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching company tool groups: $e");
      return [];
    }
  }
}

final projectController = ProjectController();