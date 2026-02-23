import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/project.dart';
import '../../../core/api_service.dart';
import '../../auth/controllers/auth_controller.dart';


class ProjectController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Project> _projects = [];
  bool _isLoading = false;
  String? _error;

  List<Project> get projects => _projects;
  bool get isLoading => _isLoading;
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

  Future<void> removeProject(String id) async {
    final originalList = List<Project>.from(_projects);
    _projects.removeWhere((p) => p.id == id);
    notifyListeners();

    try {
      await _apiService.delete('/projects/$id');
    } catch (e) {
      _projects = originalList;
      _error = "Failed to delete project";
      notifyListeners();
    }
  }
}

final projectController = ProjectController();