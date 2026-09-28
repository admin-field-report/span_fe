import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Client for the Report Profiler API served by the Eve dev tool
/// (`span-eve-agent`, routes under `/api/span-ui/*`).
///
/// Configuration (read once, compile-time define wins over `.env`):
/// - `EVE_UI_BASE_URL` — dev tool origin, e.g. `https://span-eve-devtool.vercel.app`
///   or `http://localhost:3100` for a local `next dev`.
/// - `EVE_UI_KEY` — the dev tool password, sent as `x-span-ui-key`. Pass it
///   with `--dart-define=EVE_UI_KEY=...` rather than committing it to `.env`.
///
/// This is separate from the Span backend ([apiService]): profiler templates
/// live in the dev tool's store until the flow moves into the Span BE.
class ReportProfilerApi {
  static const String _definedBaseUrl = String.fromEnvironment('EVE_UI_BASE_URL');
  static const String _definedKey = String.fromEnvironment('EVE_UI_KEY');

  /// Files up to this size go through the API as multipart; larger ones are
  /// PUT straight to storage (Vercel functions cap request bodies at 4.5 MB).
  static const int maxMultipartBytes = 4 * 1024 * 1024;

  static final http.Client _client = http.Client();

  static String get baseUrl {
    final value = _definedBaseUrl.isNotEmpty
        ? _definedBaseUrl
        : dotenv.get('EVE_UI_BASE_URL', fallback: '');
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String get _key =>
      _definedKey.isNotEmpty ? _definedKey : dotenv.get('EVE_UI_KEY', fallback: '');

  static bool get isConfigured => baseUrl.isNotEmpty;

  static Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw Exception('Report Profiler is not configured: set EVE_UI_BASE_URL in .env.');
    }
    return Uri.parse('$baseUrl/api/span-ui$path').replace(queryParameters: query);
  }

  static Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_key.isNotEmpty) 'x-span-ui-key': _key,
      };

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  static Map<String, dynamic> _decode(http.Response response, String failure) {
    dynamic body;
    try {
      body = response.body.trim().isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    final map = _asMap(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw Exception('$failure The Report Profiler key is missing or wrong (EVE_UI_KEY).');
      }
      final message = map['error']?.toString() ?? map['message']?.toString() ?? 'HTTP ${response.statusCode}';
      throw Exception(spanText('$failure $message'));
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Templates
  // ---------------------------------------------------------------------------

  static Future<List<ProfilerTemplate>> listTemplates() async {
    final response = await _client.get(_uri('/templates'), headers: _headers());
    final data = _decode(response, 'Could not load profiler templates.');
    final list = data['templates'] is List ? data['templates'] as List : const [];
    return list.map((item) => ProfilerTemplate.fromJson(_asMap(item))).toList();
  }

  static Future<ProfilerTemplate> createTemplate(String name) async {
    final response = await _client.post(
      _uri('/templates'),
      headers: _headers(json: true),
      body: jsonEncode({'name': name.trim()}),
    );
    final data = _decode(response, 'Could not create the template.');
    return ProfilerTemplate.fromJson(_asMap(data['template']));
  }

  static Future<ProfilerDetail> getTemplate(String templateId) async {
    final response = await _client.get(_uri('/templates/$templateId'), headers: _headers());
    return ProfilerDetail.fromJson(_decode(response, 'Could not load the template.'));
  }

  // ---------------------------------------------------------------------------
  // Examples
  // ---------------------------------------------------------------------------

  static String contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  /// Upload one example report. Small files go multipart through the API;
  /// large ones get a one-off direct upload URL, then are registered.
  static Future<void> uploadExample(
    String templateId, {
    required String name,
    required Uint8List bytes,
  }) async {
    final contentType = contentTypeFor(name);
    if (bytes.length <= maxMultipartBytes) {
      final request = http.MultipartRequest('POST', _uri('/templates/$templateId/examples'))
        ..headers.addAll(_headers())
        // The API infers the type from the extension (no http_parser dep here).
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      final streamed = await _client.send(request);
      _decode(await http.Response.fromStream(streamed), 'Could not upload "$name".');
      return;
    }

    final grant = _decode(
      await _client.post(
        _uri('/templates/$templateId/examples/upload-url'),
        headers: _headers(json: true),
        body: jsonEncode({'name': name, 'contentType': contentType, 'size': bytes.length}),
      ),
      'Could not prepare the upload for "$name".',
    );
    final upload = _asMap(grant['upload']);
    final headers = _asMap(upload['headers']).map((k, v) => MapEntry(k, v.toString()));
    final put = await _client.put(
      Uri.parse(upload['url'].toString()),
      headers: headers,
      body: bytes,
    );
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw Exception('Could not upload "$name" (storage returned ${put.statusCode}).');
    }
    _decode(
      await _client.post(
        _uri('/templates/$templateId/examples'),
        headers: _headers(json: true),
        body: jsonEncode({
          'pathname': grant['pathname'],
          'name': name,
          'size': bytes.length,
          'contentType': contentType,
        }),
      ),
      'Could not register "$name".',
    );
  }

  static Future<void> deleteExample(String templateId, String pathname) async {
    final response = await _client.delete(
      _uri('/templates/$templateId/examples', {'pathname': pathname}),
      headers: _headers(),
    );
    _decode(response, 'Could not remove the example.');
  }

  // ---------------------------------------------------------------------------
  // Profile job
  // ---------------------------------------------------------------------------

  static Future<ProfilerJob> startProfile(String templateId) async {
    final response = await _client.post(
      _uri('/templates/$templateId/profile'),
      headers: _headers(json: true),
      body: jsonEncode(<String, dynamic>{}),
    );
    final data = _decode(response, 'Could not start profiling.');
    return ProfilerJob.fromJson(_asMap(data['job']));
  }

  static Future<ProfilerEvents> getEvents(String jobId, {int? since}) async {
    final response = await _client.get(
      _uri('/jobs/$jobId/events', since == null ? null : {'since': '$since'}),
      headers: _headers(),
    );
    return ProfilerEvents.fromJson(_decode(response, 'Could not load agent activity.'));
  }

  static Future<void> cancelJob(String jobId) => _jobAction(jobId, {'action': 'cancel'});

  static Future<void> reopenJob(String jobId) => _jobAction(jobId, {'action': 'reopen'});

  static Future<void> answerClarifications(String jobId, Map<String, String> answers) =>
      _jobAction(jobId, {'action': 'answer', 'answers': answers});

  static Future<void> _jobAction(String jobId, Map<String, dynamic> body) async {
    final response = await _client.post(
      _uri('/jobs/$jobId'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    _decode(response, 'The request failed.');
  }

  // ---------------------------------------------------------------------------
  // Profile pack files
  // ---------------------------------------------------------------------------

  static Future<Uint8List> getFileBytes(String templateId, String path) async {
    final response = await _client.get(
      _uri('/templates/$templateId/files', {'path': path}),
      headers: _headers(),
    );
    if (response.statusCode != 200) {
      _decode(response, 'Could not load $path.');
    }
    return response.bodyBytes;
  }

  static Future<String> getFileText(String templateId, String path) async {
    return utf8.decode(await getFileBytes(templateId, path), allowMalformed: true);
  }

  static Future<void> saveFile(
    String templateId,
    String path,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final response = await _client.put(
      _uri('/templates/$templateId/files', {'path': path}),
      headers: {..._headers(), 'Content-Type': contentType},
      body: bytes,
    );
    _decode(response, 'Could not save $path.');
  }

  static Future<void> saveText(String templateId, String path, String text) => saveFile(
        templateId,
        path,
        Uint8List.fromList(utf8.encode(text)),
        contentType: 'text/markdown; charset=utf-8',
      );
}

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

/// Server text (job errors, agent messages) may name the internal agent;
/// users only ever see the product name.
String spanText(String text) => text.replaceAll(RegExp(r'\bEve\b'), 'Span');

String? _spanTextOrNull(dynamic value) => value == null ? null : spanText(value.toString());

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

Map<String, dynamic> _map(dynamic raw) =>
    raw is Map ? raw.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(dynamic raw) =>
    raw is List ? raw.map(_map).toList() : <Map<String, dynamic>>[];

class ProfilerExample {
  final String name;
  final String pathname;
  final int size;

  ProfilerExample({required this.name, required this.pathname, required this.size});

  factory ProfilerExample.fromJson(Map<String, dynamic> json) => ProfilerExample(
        name: json['name']?.toString() ?? '',
        pathname: json['pathname']?.toString() ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

class ProfilerTemplate {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<ProfilerExample> examples;

  /// none | running | needs_clarification | ready | failed | cancelled
  final String status;
  final String? jobId;
  final DateTime? builtAt;
  final String? error;

  ProfilerTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.examples,
    required this.status,
    this.jobId,
    this.builtAt,
    this.error,
  });

  factory ProfilerTemplate.fromJson(Map<String, dynamic> json) {
    final profile = _map(json['profile']);
    return ProfilerTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled template',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      examples: _mapList(json['examples']).map(ProfilerExample.fromJson).toList(),
      status: (profile['status']?.toString() ?? 'none').toLowerCase(),
      jobId: profile['jobId']?.toString(),
      builtAt: _date(profile['builtAt']),
      error: _spanTextOrNull(profile['error']),
    );
  }
}

class ProfilerJob {
  final String jobId;
  final String status;
  final DateTime createdAt;
  final List<Map<String, dynamic>> clarifications;
  final String? errorMessage;
  final String? errorDetail;
  final String? note;

  ProfilerJob({
    required this.jobId,
    required this.status,
    required this.createdAt,
    required this.clarifications,
    this.errorMessage,
    this.errorDetail,
    this.note,
  });

  factory ProfilerJob.fromJson(Map<String, dynamic> json) {
    final error = _map(json['error']);
    return ProfilerJob(
      jobId: json['jobId']?.toString() ?? '',
      status: (json['status']?.toString() ?? 'running').toLowerCase(),
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      clarifications: _mapList(json['clarifications']),
      errorMessage: _spanTextOrNull(error['message']),
      errorDetail: _spanTextOrNull(error['detail']),
      note: _spanTextOrNull(json['note']),
    );
  }
}

class ProfilerPack {
  final String? template;
  final String? instructions;
  final String? styleGuide;
  final String? uncertaintyReport;
  final String? referencePdf;
  final List<String> referencePages;

  ProfilerPack({
    this.template,
    this.instructions,
    this.styleGuide,
    this.uncertaintyReport,
    this.referencePdf,
    this.referencePages = const [],
  });

  factory ProfilerPack.fromJson(Map<String, dynamic> json) => ProfilerPack(
        template: json['template']?.toString(),
        instructions: json['instructions']?.toString(),
        styleGuide: json['styleGuide']?.toString(),
        uncertaintyReport: json['uncertaintyReport']?.toString(),
        referencePdf: json['referencePdf']?.toString(),
        referencePages: (json['referencePages'] is List)
            ? (json['referencePages'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

class ProfilerDetail {
  final ProfilerTemplate template;
  final ProfilerJob? job;
  final ProfilerPack pack;

  /// Typical profile run length in minutes (measured ~9-16, up to ~30).
  final int typicalMinutes;
  final int maxMinutes;

  ProfilerDetail({
    required this.template,
    required this.job,
    required this.pack,
    required this.typicalMinutes,
    required this.maxMinutes,
  });

  factory ProfilerDetail.fromJson(Map<String, dynamic> json) {
    final timing = _map(json['timing']);
    return ProfilerDetail(
      template: ProfilerTemplate.fromJson(_map(json['template'])),
      job: json['job'] is Map ? ProfilerJob.fromJson(_map(json['job'])) : null,
      pack: ProfilerPack.fromJson(_map(json['pack'])),
      typicalMinutes: (timing['typicalMinutes'] as num?)?.toInt() ?? 12,
      maxMinutes: (timing['maxMinutes'] as num?)?.toInt() ?? 30,
    );
  }
}

class ProfilerActivity {
  final int index;
  final DateTime? at;

  /// tool | message | error | status
  final String kind;
  final String text;
  final String? phase;
  final bool failed;

  ProfilerActivity({
    required this.index,
    required this.at,
    required this.kind,
    required this.text,
    required this.phase,
    required this.failed,
  });

  factory ProfilerActivity.fromJson(Map<String, dynamic> json) => ProfilerActivity(
        index: (json['index'] as num?)?.toInt() ?? 0,
        at: _date(json['at']),
        kind: json['kind']?.toString() ?? 'tool',
        text: spanText(json['text']?.toString() ?? ''),
        phase: json['phase']?.toString(),
        failed: json['failed'] == true,
      );
}

class ProfilerEvents {
  final String status;
  final bool sessionStarted;
  final int nextIndex;
  final List<ProfilerActivity> activities;
  final String phaseKey;
  final Map<String, DateTime> phaseStartedAt;
  final DateTime? lastEventAt;

  ProfilerEvents({
    required this.status,
    required this.sessionStarted,
    required this.nextIndex,
    required this.activities,
    required this.phaseKey,
    required this.phaseStartedAt,
    required this.lastEventAt,
  });

  factory ProfilerEvents.fromJson(Map<String, dynamic> json) {
    final started = <String, DateTime>{};
    _map(json['phaseStartedAt']).forEach((key, value) {
      final date = _date(value);
      if (date != null) started[key] = date;
    });
    return ProfilerEvents(
      status: (json['status']?.toString() ?? 'running').toLowerCase(),
      sessionStarted: json['sessionStarted'] == true,
      nextIndex: (json['nextIndex'] as num?)?.toInt() ?? 0,
      activities: _mapList(json['activities']).map(ProfilerActivity.fromJson).toList(),
      phaseKey: _map(json['phase'])['key']?.toString() ?? 'starting',
      phaseStartedAt: started,
      lastEventAt: _date(json['lastEventAt']),
    );
  }
}
