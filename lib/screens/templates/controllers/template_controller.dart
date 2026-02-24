import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/template.dart';
import '../../../core/api_service.dart';
import '../../auth/controllers/auth_controller.dart';


class TemplateController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Template> _templates = [];
  bool _isLoading = false;
  String? _error;

  List<Template> get templates => _templates;
  bool get isLoading => _isLoading;
  String? get error => _error;
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

  Future<void> removeTemplate(String id) async {
    final originalList = List<Template>.from(_templates);
    _templates.removeWhere((p) => p.id == id);
    notifyListeners();

    try {
      await _apiService.delete('/template/$id');
    } catch (e) {
      _templates = originalList;
      _error = "Failed to delete template";
      notifyListeners();
    }
  }
}

final templateController = TemplateController();