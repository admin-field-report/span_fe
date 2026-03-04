import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../screens/auth/controllers/auth_controller.dart';
import 'storage_service.dart';
import '../utils/app_responsive.dart';

class ApiService {
  final String baseUrl = dotenv.get('BASE_URL', fallback: '');
  final http.Client _client = http.Client();

  // Middleware: Centralized headers
  Map<String, String> _getHeaders() {
     final token = StorageService.getString(keyIdToken);
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-platform': AppResponsive.getPlatformName(),
      if (token != null) 
        'Authorization': token,
    };
  }

  // --- Methods ---

  Future<http.Response> get(String endpoint) async {
    return _processRequest(() => _client.get(Uri.parse('$baseUrl$endpoint'), headers: _getHeaders()));
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    return _processRequest(() => _client.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _getHeaders(),
      body: jsonEncode(body),
    ));
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    return _processRequest(() => _client.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: _getHeaders(),
      body: jsonEncode(body),
    ));
  }

  Future<http.Response> delete(String endpoint) async {
    return _processRequest(() => _client.delete(Uri.parse('$baseUrl$endpoint'), headers: _getHeaders()));
  }

  // --- Middleware Logic: Global Response Handling ---

  Future<http.Response> _processRequest(Future<http.Response> Function() request) async {
    try {
      final response = await request();
      
      if (kDebugMode) print('🌐 API ${response.request?.method}: ${response.request?.url} [${response.statusCode}]');

      // 401 Redirect Logic
      if (response.statusCode == 401) {
        if (kDebugMode) print('⚠️ 401 Unauthorized detected. Redirecting to login...');
        AuthController.instance.logout(); // This triggers the GoRouter redirect automatically
      }

      return response;
    } catch (e) {
      if (kDebugMode) print('❌ API CONNECTION ERROR: $e');
      rethrow;
    }
  }
}

final apiService = ApiService();