import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../../core/api_service.dart';
import 'eve_profile_api.dart';

enum CreateReportStatus { success, partialSuccess, failure }

// --- MODEL ---
class ReportTemplate {
  final String id;
  final String name;
  final DateTime createDate;
  final String authorName;

  /// Eve Word-profile pointer fields (mirrors the BE's DB columns). `null`
  /// when the template has never had a profile job started — the UI treats
  /// that the same as `'none'`.
  final String? profileStatus;
  final String? profileJobId;

  ReportTemplate({
    required this.id, 
    required this.name, 
    required this.createDate,
    required this.authorName,
    this.profileStatus,
    this.profileJobId,
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
      profileStatus: json['profile_status']?.toString(),
      profileJobId: json['profile_job_id']?.toString(),
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

  bool _isLoadingTemplateDetails = false;
  bool get isLoadingTemplateDetails => _isLoadingTemplateDetails;
  Map<String, dynamic>? templateData;
  String? errorMessage;
  

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
      // 🚀 FIX: use the real per-file content type (docx/pdf/doc/txt) instead
      // of always claiming "application/pdf" — S3 stores whatever
      // Content-Type we PUT with, so a mismatched type here silently
      // corrupts how the file is later served/opened.
      final presignPayload = {
        "files": files.map((f) => {
          "file_name": f.name,
          "content_type": EveProfileApi.contentTypeForFileName(f.name)
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
        // 🚀 FIX: PUT with the matching Content-Type header — S3 requires the
        // header to match what the presigned URL was signed with, and the
        // stored object's Content-Type is what browsers use when opening it.
        final String contentType = urlInfo['content_type']?.toString() ??
            EveProfileApi.contentTypeForFileName(file.name);

        final uploadResponse = await http.put(
          Uri.parse(signedUrl),
          headers: {'Content-Type': contentType},
          body: file.bytes,
        );
        
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

  Future<void> deleteReport(String templateId) async {
    try {
      final response = await _apiService.delete('/reportTemplate/delete/$templateId');
      
      if (response.statusCode == 200) {
        reports.removeWhere((r) => r.id == templateId);
        notifyListeners();
      } else {
        final resData = jsonDecode(response.body);
        throw Exception(resData['message'] ?? "Failed to delete report.");
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> fetchTemplateDetails(String templateId) async {
    errorMessage = null;
    _isLoadingTemplateDetails = true;
    notifyListeners();

    try {
      final response = await _apiService.get('/reportTemplate/getById/$templateId');
      final resData = jsonDecode(response.body);
      templateData = resData['data'];
    } catch (e) {
      errorMessage = "Failed to fetch template details.";
    } finally {
      _isLoadingTemplateDetails = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> deleteDocument(String docId, bool updateSkill) async {
    try {
      final response = await _apiService.delete('/reportTemplate/$docId/document?updateSkill=$updateSkill');
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? "Failed to delete document.");
      }
    } catch (e) {
      throw Exception("Error deleting document: $e");
    }
  }

  Future<List<Map<String, String>>> uploadDocumentsToS3(
    String templateId, 
    List<PlatformFile> files, {
    Function(int current, int total)? onProgress, // 🚀 Added callback
  }) async {
    
    // 🚀 FIX: use the real per-file content type (docx/pdf/doc/txt) instead
    // of always claiming "application/pdf" — see the matching fix in
    // createReportWithDocuments above for why this matters.
    final presignPayload = {
      "files": files.map((f) => {
        "file_name": f.name,
        "content_type": EveProfileApi.contentTypeForFileName(f.name)
      }).toList()
    };
    
    final presignResponse = await _apiService.post(
      '/reportTemplate/$templateId/documents/presigned-urls', 
      presignPayload
    );
    
    final presignData = jsonDecode(presignResponse.body);
    
    if (presignData['uploads'] == null) {
       throw Exception("Failed to generate upload URLs.");
    }
    
    final List urlsData = presignData['uploads']; 
    List<Map<String, String>> registeredDocs = [];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final urlInfo = urlsData[i]; 
      
      final String signedUrl = urlInfo['signedUrl'] ?? urlInfo['presignedUrl'] ?? urlInfo['url'];
      final String s3Key = urlInfo['key'];
      final String contentType = urlInfo['content_type']?.toString() ??
          EveProfileApi.contentTypeForFileName(file.name);

      if (file.bytes == null) continue;

      // 🚀 FIX: PUT with the matching Content-Type header (see above).
      final uploadResponse = await http.put(
        Uri.parse(signedUrl),
        headers: {'Content-Type': contentType},
        body: file.bytes,
      );
      
      if (uploadResponse.statusCode == 200 || uploadResponse.statusCode == 201) {
        registeredDocs.add({
          "name": file.name,
          "key": s3Key
        });
        // 🚀 Report progress back to the UI
        onProgress?.call(i + 1, files.length);
      } else {
        throw Exception("Failed to upload ${file.name} to S3.");
      }
    }

    return registeredDocs;
  }

  Future<Map<String, dynamic>> addDocuments(String templateId, List<Map<String, String>> uploadedDocs, bool updateSkill) async {
    final response = await _apiService.post(
      '/reportTemplate/$templateId/documents?updateSkill=$updateSkill',
      {
        "documents": uploadedDocs 
      }
    );

    final resData = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return resData; 
    } else {
      throw Exception(resData['message'] ?? "Failed to register documents.");
    }
  }
}

final reportController = ReportController();