import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../core/api_service.dart';


class ProjectController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

// --- STATE VARIABLES ---
  List<String> assignedTagGroupIds = [];
  List<String> assignedToolGroupIds = [];
  bool isSettingsLoading = false;

  // --- API METHOD ---
  Future<void> fetchProjectTags(String projectId) async {
    try {
      final response = await _apiService.get('/projectTagGroup/$projectId');
      if (response.body.isNotEmpty) {
        final res = jsonDecode(response.body);
        if (res['success'] == true && res['data'] != null) {
          assignedTagGroupIds = (res['data'] as List).map((item) => item['id'].toString()).toList();
        } else {
          assignedTagGroupIds = [];
        }
      }
    } catch (e) {
      assignedTagGroupIds = [];
    }
  }

  Future<void> fetchProjectTools(String projectId) async {
    try {
      final response = await _apiService.get('/projectCustomToolGroup/$projectId');
      if (response.body.isNotEmpty) {
        final res = jsonDecode(response.body);
        if (res['success'] == true && res['data'] != null) {
          assignedToolGroupIds = (res['data'] as List).map((item) => item['id'].toString()).toList();
        } else {
          assignedToolGroupIds = [];
        }
      }
    } catch (e) {
      assignedToolGroupIds = [];
    }
  }
  
  Future<bool> manageProjectTagGroups(String projectId, List<String> initialIds, List<String> currentIds) async {
    try {
      final Map<String, int> formattedMap = {};

      // 1. Any item currently selected (existing or newly added) is sent as 1
      for (String id in currentIds) {
        formattedMap[id] = 1;
      }

      // 2. Any item that WAS selected, but is NO LONGER selected, is sent as 0
      for (String id in initialIds) {
        if (!currentIds.contains(id)) {
          formattedMap[id] = 0;
        }
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

  Future<bool> manageProjectToolGroups(String projectId, List<String> initialIds, List<String> currentIds) async {
    try {
      final Map<String, int> formattedMap = {};

      // 1. Any item currently selected (existing or newly added) is sent as 1
      for (String id in currentIds) {
        formattedMap[id] = 1;
      }

      // 2. Any item that WAS selected, but is NO LONGER selected, is sent as 0
      for (String id in initialIds) {
        if (!currentIds.contains(id)) {
          formattedMap[id] = 0;
        }
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