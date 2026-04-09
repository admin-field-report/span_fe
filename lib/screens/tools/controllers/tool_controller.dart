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
}