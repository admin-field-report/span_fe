import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../models/project.dart';
import '../../../core/api_service.dart';

class InspectionController extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  // ==========================================
  // 1. PROJECT INSPECTIONS STATE (Existing)
  // ==========================================
  List<ProjectInspection> _inspections = [];
  bool _isInspectionsLoading = false;
  String? _error;

  List<ProjectInspection> get inspections => _inspections;
  bool get isInspectionsLoading => _isInspectionsLoading;
  String? get error => _error;

  // ==========================================
  // 2. INSPECTION DETAILS STATE (New)
  // ==========================================
  bool _isDetailsLoading = false;
  String? _detailsError;
  List<Map<String, dynamic>> _documents = [];
  List<String> _mediaUrls = [];

  bool get isDetailsLoading => _isDetailsLoading;
  String? get detailsError => _detailsError;
  List<Map<String, dynamic>> get documents => _documents;
  List<String> get mediaUrls => _mediaUrls;

  // ==========================================
  // METHODS
  // ==========================================

  Future<void> getAllInspections(String projectId) async {
    _isInspectionsLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.get('/inspection/project/$projectId');
      final Map<String, dynamic> responseData = jsonDecode(response.body); 

      if (responseData['success'] == true) {
        final List dataList = responseData['data'] ?? [];
        _inspections = dataList.map((item) => ProjectInspection.fromJson(item)).toList();
        
        // 🚀 NEW: Sort the list descending by createTime (newest first)
        _inspections.sort((a, b) => b.createTime.compareTo(a.createTime));
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isInspectionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchInspectionDetails(String inspectionId) async {
    _isDetailsLoading = true;
    _detailsError = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchDocuments(inspectionId),
        _fetchMedia(inspectionId),
      ]);

      // Parse results
      _documents = results[0] as List<Map<String, dynamic>>;
      _mediaUrls = results[1] as List<String>;

    } catch (e) {
      _detailsError = "Failed to load inspection details.";
      debugPrint("Inspection Details Fetch Error: $e");
    } finally {
      _isDetailsLoading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDocuments(String inspectionId) async {
    try {
      final response = await _apiService.get('/projectDocument/$inspectionId');
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (responseData['success'] == true && responseData['data'] != null) {
        return List<Map<String, dynamic>>.from(responseData['data']);
      }
      return [];
    } catch (e) {
      debugPrint("Doc Fetch Error: $e");
      return [];
    }
  }

  Future<List<String>> _fetchMedia(String inspectionId) async {
    try {
      final response = await _apiService.get('/presignedurl/inspection-images/$inspectionId');
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      List<String> allMediaUrls = [];

      if (responseData['data'] != null && (responseData['data'] as List).isNotEmpty) {
        final firstItem = responseData['data'][0];
        
        // 1. Grab the standard inspection images
        if (firstItem['signedUrls'] != null) {
          allMediaUrls.addAll(List<String>.from(firstItem['signedUrls']));
        }

        // 2. Grab the document-specific images
        if (firstItem['documentSignedUrls'] != null) {
          final List documentImages = firstItem['documentSignedUrls'];
          
          for (var docItem in documentImages) {
            if (docItem['signedUrl'] != null) {
              allMediaUrls.addAll(List<String>.from(docItem['signedUrl']));
            }
          }
        }
      }
      
      return allMediaUrls;
      
    } catch (e) {
      debugPrint("Media Fetch Error: $e");
      return [];
    }
  }

}


// Global instance
final inspectionController = InspectionController();