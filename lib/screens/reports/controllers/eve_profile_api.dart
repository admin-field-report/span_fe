import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:field_report_fe/core/api_service.dart';

/// Client for the Eve "Word profile" routes under `/reportTemplate/*`.
///
/// A Word profile is a reusable "style pack" Eve builds from a handful of
/// example Word/PDF reports so that later report generation can fill a
/// matching `.docx` for a project. The flow is:
///
/// 1. `createTemplate` — make an (initially empty) report template shell.
/// 2. `uploadExampleDocuments` — get S3 presigned PUT URLs for the example
///    files, upload the raw bytes straight to S3, then register the S3 keys
///    on the template.
/// 3. `generateProfile` — kick off the (long-running) Eve job that reads the
///    example docs and produces the profile pack. Returns a `job_id`.
/// 4. `getProfileJobStatus` — poll the job until it settles on `ready`,
///    `failed`, or `needs_clarification`.
/// 5. If Eve needs more info, `getProfileClarifications` /
///    `submitProfileClarifications` show/answer follow-up questions and
///    resume the same job.
/// 6. `getProfileMetadata` reads the DB-persisted pointer (status/job id/
///    error) for a template — handy for refreshing a list/badge without
///    having to know the last job id.
///
/// All calls here go through the shared [apiService], which already attaches
/// the Cognito `Authorization` header and resolves the API base URL — so
/// none of these methods need to touch `SharedPreferences` or `dotenv`
/// directly (unlike the original `fe_flutter` client this was ported from).
class EveProfileApi {
  // ---------------------------------------------------------------------------
  // JSON parsing helpers
  // ---------------------------------------------------------------------------

  /// Best-effort JSON decode; returns null instead of throwing on an empty
  /// or malformed body (some BE error responses aren't JSON).
  static dynamic _safeJsonDecode(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  /// Coerce any decoded JSON value into a `Map<String, dynamic>`, defaulting
  /// to an empty map for anything that isn't map-shaped.
  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return {};
  }

  /// Pull a list of maps out of common BE envelope shapes, e.g.
  /// `{ data: [...] }`, `{ uploads: [...] }`, or a bare JSON array.
  static List<Map<String, dynamic>> _extractMapList(dynamic responseData) {
    if (responseData is List) {
      return responseData
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList();
    }
    if (responseData is Map<String, dynamic>) {
      for (final key in ['data', 'uploads', 'documents', 'items']) {
        final candidate = responseData[key];
        if (candidate is List) {
          return _extractMapList(candidate);
        }
      }
    }
    return [];
  }

  /// Decode a response body and throw a readable [Exception] if the request
  /// failed. `okStatuses` lets callers accept e.g. 202 Accepted as success.
  static Map<String, dynamic> _decodeOrThrow(
    http.Response response,
    Set<int> okStatuses,
    String failureMessage,
  ) {
    final payload = _asMap(_safeJsonDecode(response.body));
    if (!okStatuses.contains(response.statusCode)) {
      final message = payload['message']?.toString() ?? response.body;
      throw Exception(
        '$failureMessage Status code: ${response.statusCode}, Body: $message',
      );
    }
    return payload;
  }

  // ---------------------------------------------------------------------------
  // MIME type helper (also used by report_controller.dart for uploads)
  // ---------------------------------------------------------------------------

  /// MIME type for report example uploads — mirrors the BE's
  /// `getReportExampleContentType` so S3 PUTs use the right `Content-Type`.
  static String contentTypeForFileName(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) return 'application/pdf';
    if (lowerName.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lowerName.endsWith('.doc')) return 'application/msword';
    if (lowerName.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  // ---------------------------------------------------------------------------
  // Template creation
  // ---------------------------------------------------------------------------

  /// Create a new (initially empty) report template and return its id.
  ///
  /// POST /reportTemplate/create
  /// Body: { "name": "<template name>" }
  /// Response: { message, data: { id, ... } }
  static Future<String> createTemplate(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Template name cannot be empty.');
    }

    final response = await apiService.post('/reportTemplate/create', {
      'name': trimmedName,
    });

    final payload = _decodeOrThrow(
      response,
      {200, 201},
      'Failed to create report template.',
    );

    // BE responses have wandered between a few envelope shapes over time —
    // check the most specific (nested `data.id`) first, then flatten out.
    final data = _asMap(payload['data']);
    final id = (data['id'] ?? payload['id'])?.toString();

    if (id == null || id.isEmpty) {
      throw Exception('Report template id not found in API response.');
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Example document upload (presigned URL -> S3 PUT -> register)
  // ---------------------------------------------------------------------------

  /// Ask the BE for S3 presigned PUT URLs for one or more example files.
  ///
  /// POST /reportTemplate/:id/documents/presigned-urls
  /// Body: { files: [ { file_name, content_type } ] }
  /// Response: { uploads: [ { file_name, key, signedUrl, content_type } ] }
  static Future<List<Map<String, dynamic>>> _getDocumentPresignedUrls({
    required String reportTemplateId,
    required List<Map<String, String>> files,
  }) async {
    final response = await apiService.post(
      '/reportTemplate/$reportTemplateId/documents/presigned-urls',
      {'files': files},
    );

    final payload = _decodeOrThrow(
      response,
      {200, 201},
      'Failed to get document presigned URLs.',
    );

    final uploads = _extractMapList(payload['uploads'] ?? payload);
    if (uploads.isEmpty) {
      throw Exception('Presigned URL response contained no uploads.');
    }
    return uploads;
  }

  /// Register already-uploaded S3 keys on the template.
  ///
  /// POST /reportTemplate/:id/documents
  /// Body: { documents: [ { name, key } ] }
  static Future<List<Map<String, dynamic>>> _registerDocuments({
    required String reportTemplateId,
    required List<Map<String, String>> documents,
  }) async {
    final response = await apiService.post(
      '/reportTemplate/$reportTemplateId/documents',
      {'documents': documents},
    );

    final payload = _decodeOrThrow(
      response,
      {200, 201},
      'Failed to register report template documents.',
    );

    final data = _asMap(payload['data']);
    return _extractMapList(data['documents'] ?? payload['documents'] ?? data);
  }

  /// Full example-upload pipeline for one batch of files:
  /// 1) ask BE for presigned S3 PUT URLs
  /// 2) PUT the raw bytes straight to S3 (no Cognito header — S3 uses the
  ///    presigned signature instead)
  /// 3) register the resulting S3 keys on the template
  ///
  /// [files] entries need a `name` and the raw `bytes` read from disk/picker.
  static Future<List<Map<String, dynamic>>> uploadExampleDocuments({
    required String reportTemplateId,
    required List<({String name, Uint8List bytes})> files,
  }) async {
    if (files.isEmpty) {
      throw Exception('At least one example document is required.');
    }

    final descriptors = files
        .map(
          (file) => {
            'file_name': file.name,
            'content_type': contentTypeForFileName(file.name),
          },
        )
        .toList();

    final uploads = await _getDocumentPresignedUrls(
      reportTemplateId: reportTemplateId,
      files: descriptors,
    );

    if (uploads.length != files.length) {
      throw Exception(
        'Presigned upload count (${uploads.length}) does not match '
        'selected files (${files.length}).',
      );
    }

    final registeredDocs = <Map<String, String>>[];

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final upload = uploads[i];
      final signedUrl = upload['signedUrl']?.toString() ??
          upload['presignedUrl']?.toString() ??
          upload['url']?.toString() ??
          '';
      final key = upload['key']?.toString() ?? '';
      final contentType =
          upload['content_type']?.toString() ?? contentTypeForFileName(file.name);

      if (signedUrl.isEmpty || key.isEmpty) {
        throw Exception('Missing signedUrl/key for file "${file.name}".');
      }
      if (file.bytes.isEmpty) {
        throw Exception(
          'Unable to read file "${file.name}". Please re-select your files.',
        );
      }

      // Raw `http` PUT straight to S3 — this bypasses `apiService` entirely
      // since the presigned URL is already authenticated and does not want
      // (or accept) our Cognito header.
      final putResponse = await http.put(
        Uri.parse(signedUrl),
        headers: {'Content-Type': contentType},
        body: file.bytes,
      );
      if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
        throw Exception(
          'Failed to upload "${file.name}" to S3. '
          'Status code: ${putResponse.statusCode}',
        );
      }

      registeredDocs.add({'name': file.name, 'key': key});
    }

    return _registerDocuments(
      reportTemplateId: reportTemplateId,
      documents: registeredDocs,
    );
  }

  // ---------------------------------------------------------------------------
  // Eve profile job APIs
  // ---------------------------------------------------------------------------

  /// Enqueue the Eve profile-build job for a template that already has
  /// example documents registered.
  ///
  /// POST /reportTemplate/:id/profile/generate → 202
  /// Response includes `job_id`, `status`, `status_endpoint`, etc.
  static Future<Map<String, dynamic>> generateProfile(
    String reportTemplateId,
  ) async {
    final response = await apiService.post(
      '/reportTemplate/$reportTemplateId/profile/generate',
      <String, dynamic>{},
    );

    // 202 Accepted is the expected success path for an async job enqueue;
    // some environments may still respond 200/201, so accept all three.
    return _decodeOrThrow(
      response,
      {200, 201, 202},
      'Failed to start Eve profile generation.',
    );
  }

  /// Poll the Eve profile job's current status.
  ///
  /// GET /reportTemplate/:id/profile/status/:jobId
  /// HTTP: 202 while queued/running, 200 once ready/needs_clarification,
  /// 500 once failed. We attach `_http_status` to the returned map so the
  /// UI can tell 202-in-flight apart from a 200 body that also says
  /// `status: "running"`, without losing the job payload itself.
  static Future<Map<String, dynamic>> getProfileJobStatus({
    required String reportTemplateId,
    required String jobId,
  }) async {
    final response = await apiService.get(
      '/reportTemplate/$reportTemplateId/profile/status/$jobId',
    );

    final payload = _asMap(_safeJsonDecode(response.body));
    payload['_http_status'] = response.statusCode;

    // A 500 that represents a terminal "failed" job state is not a
    // transport error — let it through so the caller can read
    // `status`/`error` from the body. Only bail out on other 4xx/5xx.
    if (response.statusCode >= 400 &&
        response.statusCode != 404 &&
        response.statusCode != 500) {
      final message = payload['message']?.toString() ?? response.body;
      throw Exception(
        'Failed to fetch Eve profile job status. '
        'Status code: ${response.statusCode}, Body: $message',
      );
    }

    return payload;
  }

  /// Read the clarification questions Eve is waiting on for the latest (or
  /// given) profile job.
  ///
  /// GET /reportTemplate/:id/profile/clarifications?job_id=
  static Future<Map<String, dynamic>> getProfileClarifications({
    required String reportTemplateId,
    String? jobId,
  }) async {
    final query = (jobId != null && jobId.isNotEmpty)
        ? '?job_id=${Uri.encodeQueryComponent(jobId)}'
        : '';
    final response = await apiService.get(
      '/reportTemplate/$reportTemplateId/profile/clarifications$query',
    );

    final payload = _decodeOrThrow(
      response,
      {200},
      'Failed to load profile clarifications.',
    );

    final data = _asMap(payload['data']);
    return data.isNotEmpty ? data : payload;
  }

  /// Submit clarification answers and resume the profile job.
  ///
  /// POST /reportTemplate/:id/profile/clarifications
  /// Body: { job_id?, clarification_answers: { [questionId]: string } }
  static Future<Map<String, dynamic>> submitProfileClarifications({
    required String reportTemplateId,
    required Map<String, String> clarificationAnswers,
    String? jobId,
  }) async {
    final body = <String, dynamic>{
      'clarification_answers': clarificationAnswers,
    };
    if (jobId != null && jobId.isNotEmpty) {
      body['job_id'] = jobId;
    }

    final response = await apiService.post(
      '/reportTemplate/$reportTemplateId/profile/clarifications',
      body,
    );

    return _decodeOrThrow(
      response,
      {200, 202},
      'Failed to submit profile clarifications.',
    );
  }

  /// Read the DB-persisted profile pointer (status / job id / error) for a
  /// template — used to refresh a list badge or resume a screen without
  /// already knowing the last job id.
  ///
  /// GET /reportTemplate/:id/profile
  static Future<Map<String, dynamic>> getProfileMetadata(
    String reportTemplateId,
  ) async {
    final response = await apiService.get('/reportTemplate/$reportTemplateId/profile');

    final payload = _decodeOrThrow(
      response,
      {200},
      'Failed to load Eve profile metadata.',
    );

    final data = _asMap(payload['data']);
    return data.isNotEmpty ? data : payload;
  }
}
