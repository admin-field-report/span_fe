import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../models/tool_group.dart';

class ToolController extends ChangeNotifier {
  final ApiService _api = ApiService(); 

  // --- STATE ---
  List<ToolGroup> toolGroups = [];
  bool isGroupsLoading = false;
  String? error;

  List<ToolItem> masterTools = [];
  bool isMasterToolsLoading = false;

  bool isGroupDetailsLoading = false;

  // --- METHODS ---
  
  // 🚀 FETCH ALL TOOL GROUPS
  Future<void> fetchGroups() async {
    isGroupsLoading = true;
    error = null;
    notifyListeners();

    try {
      final response = await _api.get('/customToolGroup/company');
      final data = jsonDecode(response.body);

      if (data['data'] != null) {
        toolGroups = (data['data'] as List)
            .map((json) => ToolGroup.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        error = data['message'] ?? "Failed to load tool groups.";
      }
    } catch (e) {
      error = "Network error while fetching tool groups.";
    } finally {
      isGroupsLoading = false;
      notifyListeners();
    }
  }

  // 🚀 1. ADD THIS NEW METHOD
  Future<void> fetchGroupDetails(String groupId) async {
    isGroupDetailsLoading = true;
    notifyListeners();

    try {
      // final response = await _api.get('/customToolGroupItem/custom-tool-group/$groupId');
      final response = await _api.get('/customToolGroupItem/customToolGroup/$groupId');
      final data = jsonDecode(response.body);

      if (data['data'] != null) {
        final fetchedTools = (data['data'] as List)
            .map((json) => ToolItem.fromJson(json as Map<String, dynamic>))
            .toList();
            
        final groupIndex = toolGroups.indexWhere((g) => g.id == groupId);
        if (groupIndex != -1) {
          toolGroups[groupIndex].tools = fetchedTools;
        }
      }
    } catch (e) {
      debugPrint("🚨 Error fetching group details: $e");
    } finally {
      isGroupDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchMasterTools() async {
    isMasterToolsLoading = true;
    error = null;
    notifyListeners();

    try {
      final response = await _api.get('/customTool/company');
      final data = jsonDecode(response.body);

        debugPrint("✅ Fetched ${data['data'].length} master tools.");
            
      if (data['data'] != null) {
        masterTools = (data['data'] as List)
            .map((json) => ToolItem.fromJson(json as Map<String, dynamic>))
            .toList();
            debugPrint("✅ Parsed ${masterTools.length} master tools successfully.");
      } else {
        error = data['message'] ?? "Failed to load custom tools.";
      }
    } catch (e) {
      error = "Network error while fetching custom tools.";
    } finally {
      isMasterToolsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createToolGroup(String name, List<String> toolIds, List<String> toolGroupIds) async {
    try {
      final payload = {
        "name": name,
        "custom_tool_id_list": toolIds,
        "custom_tool_group_id_list": toolGroupIds,
      };

      final response = await _api.post('/customToolGroup/group', payload);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true; 
      } else {
        error = "Failed to create group. Server responded with ${response.statusCode}";
        notifyListeners();
        return false;
      }
    } catch (e) {
      error = "Network error while creating group.";
      notifyListeners();
      return false;
    }
  }

  // 🚀 UPDATE EXISTING TOOL GROUP
  Future<bool> updateToolGroup({
    required String groupId,
    required String name,
    required List<String> toolIds,
  }) async {
    try {
      final payload = {
        "name": name,
        "custom_tool_id_list": toolIds,
      };

      // Make the API call
      final response = await _api.put('/customToolGroup/update/$groupId', payload);
      
      // Parse the JSON response
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        error = responseData['message'] ?? "Failed to update group.";
        notifyListeners();
        return false;
      }
    } catch (e) {
      error = "Network error while updating group.";
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteToolGroup(String groupId) async {
    try {
      // Assuming your ApiService has a .delete() method
      final response = await _api.delete('/customToolGroup/$groupId');
      
      if (response.statusCode == 200) {
        return true; 
      } else {
        error = "Failed to delete group. Server responded with ${response.statusCode}";
        notifyListeners();
        return false;
      }
    } catch (e) {
      error = "Network error while deleting group.";
      notifyListeners();
      return false;
    }
  }

  // 🚀 CREATE A NEW TOOL
  Future<bool> createTool({
    required String name,
    required String groupId,
    required String canvasJson,
    required List<String> tagIds,
  }) async {
    try {
      final payload = {
        "name": name,
        "custom_tool_group_id": groupId,
        "json_data": jsonDecode(canvasJson),
        "tag_ids": tagIds,
      };
      final response = await _api.post('/customTool/new', payload);
      
      // Parse the JSON response
      final responseData = jsonDecode(response.body);

      // Check if the response contains the newly created tool data
      if (responseData['data'] != null && responseData['data']['id'] != null) {
        return true;
      } else {
        error = responseData['message'] ?? "Failed to create tool.";
        notifyListeners();
        return false;
      }
    } catch (e) {
      error = "Network error while creating tool.";
      notifyListeners();
      return false;
    }
  }
}