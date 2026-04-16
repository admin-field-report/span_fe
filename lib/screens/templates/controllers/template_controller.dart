import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
  import 'package:file_picker/file_picker.dart';
import '../../../models/template.dart';
import '../../../models/tag_models.dart';
import '../../tools/models/tool_group.dart';
import '../../../core/api_service.dart';


class TemplateController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Template> _templates = [];
  bool _isLoading = false;
  String? _error;

  List<Template> get templates => _templates;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<AppTagGroup> currentTagGroups = [];
  bool _isDetailLoading = false;

  bool get isDetailLoading => _isDetailLoading;

  List<TemplateToolGroup> currentToolGroups = [];
  bool isToolGroupsLoading = false;

  List<TemplateDocument> currentDocuments = [];
  bool isDocumentsLoading = false;

  // 🚀 ADD THIS TO TEMPLATE CONTROLLER
  void clearTemplateDetails() {
    currentTagGroups = [];
    currentToolGroups = [];
    // Reset any other lists you might add later (like documents)
    notifyListeners(); 
  }

  Future<void> getAllTemplates() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/template/user');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _templates = dataList.map((item) => Template.fromJson(item)).toList();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 🚀 Returns a bool so the dialog can await the result
  Future<bool> removeTemplate(String id) async {
    _error = null;
    
    try {
      final response = await _apiService.delete('/template/$id');
      
      // Assuming your API returns a 200/204 or a success flag
      _templates.removeWhere((p) => p.id == id);
      notifyListeners();
      return true;
      
    } catch (e) {
      _error = "Failed to delete template";
      notifyListeners();
      return false;
    }
  }
  
  // 🚀 Returns Template? instead of bool
  Future<Template?> createTemplate(String name) async {
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.post(
        '/template/createTemplate',
        {'name': name},
      );

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (responseData['templateResponse'] != null) {
        
        final newTemplate = Template.fromJson(responseData['templateResponse']);
        
        _templates.insert(0, newTemplate);
        notifyListeners();
        
        return newTemplate;
      } else {
        _error = responseData['message'] ?? "Failed to create template";
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = "Network error: Couldn't create template";
      notifyListeners();
      return null;
    }
  }

  Future<void> getTagGroupsForTemplate(String templateId) async {
    _isDetailLoading = true;
    currentTagGroups = [];
    notifyListeners();

    try {
      final response = await _apiService.get('/tagGroupItem/template/$templateId');
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        currentTagGroups = dataList.map((item) => AppTagGroup.fromJson(item)).toList();
      }
    } catch (e) {
      _error = "Failed to load tag groups";
    } finally {
      _isDetailLoading = false;
      notifyListeners();
    }
  }

  Future<void> getToolGroupsForTemplate(String templateId) async {
    isToolGroupsLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/customToolGroupItem/template/$templateId');
      final data = jsonDecode(response.body);

      if (data['success'] == true && data['data'] != null) {
        currentToolGroups = (data['data'] as List)
            .map((json) => TemplateToolGroup.fromJson(json))
            .toList();
      } else {
        currentToolGroups = [];
      }
    } catch (e) {
      currentToolGroups = [];
    } finally {
      isToolGroupsLoading = false;
      notifyListeners();
    }
  }

  Future<List<AppTagGroup>> getAllMasterTagGroups() async {
    try {
      final response = await _apiService.get('/tagGroup/all'); 
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (data['success'] == true) {
        final List dataList = data['data'] ?? [];
        return dataList.map((item) => AppTagGroup.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Failed to fetch master tag groups: $e");
      return [];
    }
  }

  // 🚀 Save the assigned Tag Groups
  Future<bool> assignTagsToTemplate({
    required String templateId,
    required List<String> tagGroupIds,
  }) async {
    try {
      final payload = {
        "template_id": templateId,
        "tag_group_id_list": tagGroupIds,
      };

      final response = await apiService.post('/tagGroup/assign-to-template', payload);
      
      // Parse the JSON response
      final responseData = jsonDecode(response.body);

      // Assuming 200/201 indicates success.
      if (responseData['success'] == true) {
        return true;
      } else {
        notifyListeners();
        return false;
      }
    } catch (e) {
      notifyListeners();
      return false;
    }
  }

  // 🚀 FETCH ALL MASTER TOOL GROUPS
  Future<List<ToolGroup>> getAllMasterToolGroups() async {
    try {
      final response = await apiService.get('/customToolGroup/company');
      final data = jsonDecode(response.body);

      if (data['data'] != null) {
        return (data['data'] as List)
            .map((json) => ToolGroup.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 🚀 ASSIGN TOOL GROUPS TO TEMPLATE
  Future<bool> assignToolGroupsToTemplate({
    required String templateId,
    required List<String> toolGroupIds,
  }) async {
    try {
      final payload = {
        "template_id": templateId,
        "custom_tool_group_id_list": toolGroupIds,
      };

      final response = await apiService.post('/templateCustomToolGroup/assign-custom-tool-group', payload);
      
      final responseData = jsonDecode(response.body);

      if (responseData['success'] == true) {
        return true;
      } else {
        notifyListeners();
        return false;
      }
    } catch (e) {
      notifyListeners();
      return false;
    }
  }

  // THE FETCH API ---
  Future<void> getDocumentsForTemplate(String templateId) async {
    isDocumentsLoading = true;
    notifyListeners();

    try {
      final response = await apiService.get('/templateDocument/template/$templateId');
      final data = jsonDecode(response.body);

      if (data['success'] == true && data['data'] != null) {
        currentDocuments = (data['data'] as List)
            .map((json) => TemplateDocument.fromJson(json))
            .toList();
      } else {
        currentDocuments = [];
      }
    } catch (e) {
      currentDocuments = [];
    } finally {
      isDocumentsLoading = false;
      notifyListeners();
    }
  }

  // 🚀 ORCHESTRATE THE 3-STEP UPLOAD PROCESS
  Future<bool> uploadDocument(String templateId, PlatformFile file) async {
    try {
      // STEP 1: Get Presigned URL
      final presignedRes = await apiService.post('/presignedurl', {"file": file.name});
      final presignedData = jsonDecode(presignedRes.body);
      
      final signedUrl = presignedData['signedUrl'];
      final documentKey = presignedData['key'];

      if (signedUrl == null) throw Exception("Failed to get presigned URL");

      // STEP 2: Upload file directly to S3 (AWS requires a PUT request)
      // Using file.bytes ensures this works seamlessly on both Web and Mobile!
      final s3Response = await http.put(
        Uri.parse(signedUrl),
        body: file.bytes,
        headers: {
          'Content-Type': 'application/pdf',
        },
      );

      if (s3Response.statusCode != 200) {
        throw Exception("S3 Upload Failed with status: ${s3Response.statusCode}");
      }

      // STEP 3: Save to Database
      final createRes = await apiService.post('/templateDocument/createTemplateDocument', {
        "document_url": documentKey,
        "template_id": templateId
      });
      
      final createData = jsonDecode(createRes.body);
      return createData['success'] == true;

    } catch (e) {
      return false;
    }
  }

  // 🚀 DELETE DOCUMENT
  Future<bool> deleteDocument(String documentId) async {
    try {
      final response = await apiService.delete('/templateDocument/$documentId');
      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        return true; 
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}

final templateController = TemplateController();