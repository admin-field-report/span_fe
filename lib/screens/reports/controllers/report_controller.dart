import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../core/api_service.dart';

enum CreateReportStatus { success, partialSuccess, failure }

// --- MODEL ---
class ReportTemplate {
  final String id;
  final String name;
  final DateTime createDate;
  final String authorName;

  ReportTemplate({
    required this.id, 
    required this.name, 
    required this.createDate,
    required this.authorName,
  });

  factory ReportTemplate.fromJson(Map<String, dynamic> json) {
    String author = 'Unknown';
    if (json['user'] != null) {
      final firstName = json['user']['first_name'] ?? '';
      final lastName = json['user']['last_name'] ?? '';
      author = "$firstName $lastName".trim();
    }

    return ReportTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unnamed Report',
      createDate: json['create_time'] != null 
          ? DateTime.tryParse(json['create_time']) ?? DateTime.now() 
          : DateTime.now(),
      authorName: author,
    );
  }
}

// --- CONTROLLER ---
class ReportController extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  List<ReportTemplate> _reports = [];
  List<ReportTemplate> get reports => _reports;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> getAllReports() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Hardcoded for now as requested
      final response = await _apiService.get('/reportTemplate/getByCompanyId');
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (responseData['data'] != null) {
        final List dataList = responseData['data'];
        _reports = dataList.map((item) => ReportTemplate.fromJson(item)).toList();
        
        // 🚀 THE FIX: Sort the list descending by createDate so the newest is at index 0
        _reports.sort((a, b) => b.createDate.compareTo(a.createDate));
      }
    } catch (e) {
      debugPrint("Error fetching reports: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<CreateReportStatus> createReportWithDocuments(String name, List<PlatformFile> files) async {
    bool isReportCreated = false;

    try {
      // 1. Create the Report Template
      final createPayload = {"name": name};
      final createResponse = await _apiService.post('/reportTemplate/create', createPayload);
      final createData = jsonDecode(createResponse.body);
      
      if (createData['data'] == null) {
        return CreateReportStatus.failure;
      }
      
      final String reportId = createData['data']['id'];
      isReportCreated = true; // 🚀 Flag as created, but defer refreshing to the UI

      if (files.isEmpty) return CreateReportStatus.success;

      // 2. Get Pre-signed URLs
      final presignPayload = {
        "files": files.map((f) => {
          "file_name": f.name,
          "content_type": "application/pdf"
        }).toList()
      };
      
      final presignResponse = await _apiService.post('/reportTemplate/$reportId/documents/presigned-urls', presignPayload);
      final presignData = jsonDecode(presignResponse.body);
      
      if (presignData['uploads'] == null) return CreateReportStatus.partialSuccess;
      
      final List urlsData = presignData['uploads']; 
      List<Map<String, String>> registeredDocs = [];

      // 3. Upload files to S3 via Pre-signed URLs
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final urlInfo = urlsData[i]; 
        
        final String signedUrl = urlInfo['signedUrl'] ?? urlInfo['presignedUrl'] ?? urlInfo['url'];
        final String s3Key = urlInfo['key'];

        final uploadResponse = await http.put(Uri.parse(signedUrl), body: file.bytes);
        
        if (uploadResponse.statusCode == 200) {
          registeredDocs.add({
            "name": file.name,
            "key": s3Key
          });
        }
      }

      if (registeredDocs.isEmpty) return CreateReportStatus.partialSuccess;

      // 4. Register the uploaded documents to the template
      final registerPayload = {"documents": registeredDocs};
      final registerResponse = await _apiService.post('/reportTemplate/$reportId/documents', registerPayload);
      
      if (registerResponse.statusCode != 200 && registerResponse.statusCode != 201) {
        return CreateReportStatus.partialSuccess;
      }

      if (registeredDocs.length < files.length) return CreateReportStatus.partialSuccess;

      return CreateReportStatus.success;

    } catch (e) {
      debugPrint("Error in createReportWithDocuments: $e");
      return isReportCreated ? CreateReportStatus.partialSuccess : CreateReportStatus.failure;
    }
  }
}

final reportController = ReportController();