import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:field_report_fe/core/api_service.dart';

/// Client for the Eve "generate filled Word report" routes.
///
/// Once a report template has a `ready` Word profile (see
/// `screens/reports/controllers/eve_profile_api.dart`), a project can ask
/// Eve to fill that profile's `.docx` template using one or more
/// inspections. The flow is:
///
/// 1. `enqueueGenerateDocx` — POST the project/template/inspections and get
///    back a `job_id` (Cognito-authenticated, goes through [apiService]).
/// 2. `getGenerateDocxJobStatus` — poll until `ready`/`failed`. Once ready,
///    the payload's `download_urls` map has short-lived signed S3 GET URLs
///    for the filled `.docx` and a `generation-notes.md`.
/// 3. `downloadBytesFromUrl` / `downloadTextFromUrl` — fetch those signed
///    URLs directly with raw `http` (no Cognito header — the URL itself is
///    already the auth).
/// 4. `getReportById` is a convenience lookup for a `report` row (which may
///    carry the same `download_urls` once generation is done), useful if a
///    user navigates back to an existing report later.
class EveGenerateDocxApiService {
  // ---------------------------------------------------------------------------
  // JSON parsing helpers (same approach as EveProfileApi)
  // ---------------------------------------------------------------------------

  static dynamic _safeJsonDecode(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return {};
  }

  // ---------------------------------------------------------------------------
  // Generate + poll (Cognito-authenticated via apiService)
  // ---------------------------------------------------------------------------

  /// Enqueue an Eve DOCX fill for a project + ready Word profile template.
  ///
  /// POST /inspection/report/generate-docx
  /// Body: { project_id, report_template_id, inspection_ids, format: "docx" }
  /// Success: 202 with job_id, report_id, status_endpoint, …
  static Future<Map<String, dynamic>> enqueueGenerateDocx({
    required String projectId,
    required String reportTemplateId,
    required List<String> inspectionIds,
  }) async {
    final response = await apiService.post('/inspection/report/generate-docx', {
      'project_id': projectId,
      'report_template_id': reportTemplateId,
      'inspection_ids': inspectionIds,
      'format': 'docx',
    });

    final payload = _asMap(_safeJsonDecode(response.body));

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 202) {
      final message = payload['message']?.toString() ?? response.body;
      throw Exception(
        'Failed to start Word report generation. '
        'Status code: ${response.statusCode}, Body: $message',
      );
    }

    return payload;
  }

  /// Poll the Eve DOCX-generate job's current status.
  ///
  /// GET /inspection/report/generate-docx/:jobId
  /// HTTP: 202 while queued/running, 200 when ready, 500 when failed. On
  /// ready, the payload includes a `download_urls` map. We attach
  /// `_http_status` so callers can distinguish transport status from the
  /// job's own `status` field without losing the body.
  static Future<Map<String, dynamic>> getGenerateDocxJobStatus(
    String jobId,
  ) async {
    final response = await apiService.get('/inspection/report/generate-docx/$jobId');

    final payload = _asMap(_safeJsonDecode(response.body));
    payload['_http_status'] = response.statusCode;

    // A 500 carrying a terminal "failed" job body is not a transport
    // error — let it through so the caller can read job.error.message.
    if (response.statusCode >= 400 &&
        response.statusCode != 404 &&
        response.statusCode != 500) {
      final message = payload['message']?.toString() ?? response.body;
      throw Exception(
        'Failed to fetch Word generate job status. '
        'Status code: ${response.statusCode}, Body: $message',
      );
    }

    return payload;
  }

  /// Load a report row (includes `download_urls` once DOCX artifacts exist).
  ///
  /// GET /report/getById/:id
  static Future<Map<String, dynamic>> getReportById(String reportId) async {
    final response = await apiService.get('/report/getById/$reportId');

    final payload = _asMap(_safeJsonDecode(response.body));
    if (response.statusCode != 200) {
      final message = payload['message']?.toString() ?? response.body;
      throw Exception(
        'Failed to load report. '
        'Status code: ${response.statusCode}, Body: $message',
      );
    }

    final data = _asMap(payload['data']);
    return data.isNotEmpty ? data : payload;
  }

  // ---------------------------------------------------------------------------
  // Artifact download helpers (signed S3 GET URLs — no Cognito header)
  // ---------------------------------------------------------------------------

  /// GET raw bytes from a short-lived signed S3 URL.
  ///
  /// Deliberately uses `http.get` directly (not [apiService]) — these URLs
  /// carry their own signature/expiry in the query string and must NOT get
  /// our Cognito `Authorization` header attached.
  static Future<Uint8List> downloadBytesFromUrl(String signedUrl) async {
    final response = await http.get(Uri.parse(signedUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to download artifact. Status code: ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  /// GET UTF-8 text (e.g. `generation-notes.md`) from a signed S3 URL.
  static Future<String> downloadTextFromUrl(String signedUrl) async {
    final bytes = await downloadBytesFromUrl(signedUrl);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Pull the `download_urls` map out of either a job poll payload or a
  /// report row, normalizing to the two keys the UI cares about.
  static Map<String, String> extractDownloadUrls(Map<String, dynamic> payload) {
    final map = _asMap(payload['download_urls']);
    final out = <String, String>{};
    final filled = map['filled_docx']?.toString() ?? '';
    final notes = map['generation_notes']?.toString() ?? '';
    if (filled.isNotEmpty) out['filled_docx'] = filled;
    if (notes.isNotEmpty) out['generation_notes'] = notes;
    return out;
  }
}
