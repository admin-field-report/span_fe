import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../../../reports/controllers/report_profiler_api.dart' show ProfilerTemplate, spanText;

/// Client for Span report generation, served by the dev tool's Span UI API
/// (`span-eve-agent`, routes under `/api/span-ui/runs` and
/// `/api/span-ui/inspections`). Same configuration as [ReportProfilerApi]:
/// `EVE_UI_BASE_URL` and `EVE_UI_KEY` (compile-time define wins over `.env`).
class ReportGenerationApi {
  static const String _definedBaseUrl = String.fromEnvironment('EVE_UI_BASE_URL');
  static const String _definedKey = String.fromEnvironment('EVE_UI_KEY');

  static final http.Client _client = http.Client();

  static String get baseUrl {
    final value = _definedBaseUrl.isNotEmpty ? _definedBaseUrl : dotenv.get('EVE_UI_BASE_URL', fallback: '');
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String get _key => _definedKey.isNotEmpty ? _definedKey : dotenv.get('EVE_UI_KEY', fallback: '');

  static bool get isConfigured => baseUrl.isNotEmpty;

  static Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw Exception('Report generation is not configured: set EVE_UI_BASE_URL in .env.');
    }
    return Uri.parse('$baseUrl/api/span-ui$path').replace(queryParameters: query);
  }

  static Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_key.isNotEmpty) 'x-span-ui-key': _key,
      };

  static Map<String, dynamic> _decode(http.Response response, String failure) {
    dynamic body;
    try {
      body = response.body.trim().isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    final map = _map(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw Exception('$failure The Span UI key is missing or wrong (EVE_UI_KEY).');
      }
      throw Exception(spanText('$failure ${map['error'] ?? 'HTTP ${response.statusCode}'}'));
    }
    return map;
  }

  static Future<List<GenerationInspection>> listInspections() async {
    final data = _decode(await _client.get(_uri('/inspections'), headers: _headers()), 'Could not load inspections.');
    return _mapList(data['inspections']).map(GenerationInspection.fromJson).toList();
  }

  /// Report templates Span can write with (profile ready), newest first.
  static Future<List<ProfilerTemplate>> listReadyTemplates() async {
    final data = _decode(await _client.get(_uri('/report-templates'), headers: _headers()), 'Could not load report templates.');
    return _mapList(data['templates']).map(ProfilerTemplate.fromJson).toList();
  }

  static Future<List<ReportRun>> listRuns({String? inspectionId, String? templateId, int limit = 25}) async {
    final data = _decode(
      await _client.get(
        _uri('/runs', {
          'limit': '$limit',
          'inspectionId': ?inspectionId,
          'templateId': ?templateId,
        }),
        headers: _headers(),
      ),
      'Could not load reports.',
    );
    return _mapList(data['runs']).map(ReportRun.fromJson).toList();
  }

  static Future<ReportRun> startRun({required String templateId, required String inspectionId}) async {
    final data = _decode(
      await _client.post(
        _uri('/runs'),
        headers: _headers(json: true),
        body: jsonEncode({'templateId': templateId, 'inspectionId': inspectionId}),
      ),
      'Could not start the report.',
    );
    return ReportRun.fromJson(_map(data['run']));
  }

  static Future<ReportRunDetail> getRun(String jobId) async {
    final data = _decode(await _client.get(_uri('/runs/$jobId'), headers: _headers()), 'Could not load the report.');
    return ReportRunDetail.fromJson(data);
  }

  static Future<GenerationEvents> getEvents(String jobId, {int? since}) async {
    final data = _decode(
      await _client.get(_uri('/runs/$jobId/events', since == null ? null : {'since': '$since'}), headers: _headers()),
      'Could not load progress.',
    );
    return GenerationEvents.fromJson(data);
  }

  static Future<Uint8List> getFileBytes(String jobId, String path) async {
    final response = await _client.get(_uri('/runs/$jobId/file', {'path': path}), headers: _headers());
    if (response.statusCode != 200) _decode(response, 'Could not load $path.');
    return response.bodyBytes;
  }

  /// The report as an editable document: its fill map (every template
  /// placeholder and the value used), the template's section order and field
  /// labels, the fields the inspection didn't answer, and the photos used.
  static Future<ReportFillDocument> getFillMap(String jobId) async {
    final data = _decode(await _client.get(_uri('/runs/$jobId/fill-map'), headers: _headers()), 'Could not load the report for editing.');
    return ReportFillDocument.fromJson(data);
  }

  /// Save the edited fill map. The server stores it and rebuilds the Word file
  /// from the template (deterministic fill, no model call).
  static Future<ReportEditStatus> saveEdits(String jobId, Map<String, dynamic> fillMap) async {
    final data = _decode(
      await _client.post(
        _uri('/runs/$jobId/edit'),
        headers: _headers(json: true),
        body: jsonEncode({'fillMap': fillMap}),
      ),
      'Could not save your changes.',
    );
    return ReportEditStatus.fromJson(data);
  }

  /// A photo the report uses (a path from the fill map).
  static Future<Uint8List> getPhotoBytes(String jobId, String path) async {
    final response = await _client.get(_uri('/runs/$jobId/photo', {'path': path}), headers: _headers());
    if (response.statusCode != 200) _decode(response, 'Could not load the photo.');
    return response.bodyBytes;
  }

  /// Upload a replacement photo; returns the path to put in the fill map.
  static Future<String> uploadPhoto(String jobId, Uint8List bytes, String fileName) async {
    final lower = fileName.toLowerCase();
    final type = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    final data = _decode(
      await _client.post(
        _uri('/runs/$jobId/photo'),
        headers: {..._headers(), 'Content-Type': type},
        body: bytes,
      ),
      'Could not upload the photo.',
    );
    return data['path']?.toString() ?? '';
  }

  /// Cancel a running report (shared job action route).
  static Future<void> cancelRun(String jobId) async {
    _decode(
      await _client.post(_uri('/jobs/$jobId'), headers: _headers(json: true), body: jsonEncode({'action': 'cancel'})),
      'Could not cancel the report.',
    );
  }
}

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

Map<String, dynamic> _map(dynamic raw) =>
    raw is Map ? raw.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(dynamic raw) => raw is List ? raw.map(_map).toList() : <Map<String, dynamic>>[];

DateTime? _date(dynamic value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

int? _int(dynamic value) => value is num ? value.toInt() : null;

List<String> _strings(dynamic raw) => raw is List ? raw.map((e) => spanText(e.toString())).toList() : const [];

class GenerationInspection {
  final String id;
  final String name;
  final String? projectName;
  final String? siteAddress;
  final String? inspectionDate;
  final String? inspectorName;
  final int documents;
  final int pages;
  final int findings;
  final int photos;

  const GenerationInspection({
    required this.id,
    required this.name,
    this.projectName,
    this.siteAddress,
    this.inspectionDate,
    this.inspectorName,
    this.documents = 0,
    this.pages = 0,
    this.findings = 0,
    this.photos = 0,
  });

  factory GenerationInspection.fromJson(Map<String, dynamic> json) => GenerationInspection(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Inspection',
        projectName: json['projectName']?.toString(),
        siteAddress: json['siteAddress']?.toString(),
        inspectionDate: json['inspectionDate']?.toString(),
        inspectorName: json['inspectorName']?.toString(),
        documents: _int(json['documents']) ?? 0,
        pages: _int(json['pages']) ?? 0,
        findings: _int(json['findings']) ?? 0,
        photos: _int(json['photos']) ?? 0,
      );
}

/// One generated report (a generate run).
class ReportRun {
  final String jobId;

  /// running | needs_clarification | ready | failed | cancelled
  final String status;
  final String templateId;
  final String? templateName;
  final String? inspectionId;
  final String? inspectionName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? durationSeconds;

  /// PASS | PASS WITH NOTES | FAIL (ready runs only)
  final String? qaResult;
  final int? questionCount;
  final String? note;
  final String? errorMessage;

  const ReportRun({
    required this.jobId,
    required this.status,
    required this.templateId,
    required this.createdAt,
    this.templateName,
    this.inspectionId,
    this.inspectionName,
    this.updatedAt,
    this.durationSeconds,
    this.qaResult,
    this.questionCount,
    this.note,
    this.errorMessage,
  });

  bool get isRunning => status == 'running' || status == 'queued' || status == 'needs_clarification';

  factory ReportRun.fromJson(Map<String, dynamic> json) {
    final error = _map(json['error']);
    return ReportRun(
      jobId: json['jobId']?.toString() ?? '',
      status: (json['status']?.toString() ?? 'running').toLowerCase(),
      templateId: json['templateId']?.toString() ?? '',
      templateName: json['templateName']?.toString(),
      inspectionId: json['inspectionId']?.toString(),
      inspectionName: json['inspectionName']?.toString(),
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt']),
      durationSeconds: _int(json['durationSeconds']),
      qaResult: json['qaResult']?.toString(),
      questionCount: _int(json['questionCount']),
      note: json['note'] == null ? null : spanText(json['note'].toString()),
      errorMessage: error.isEmpty ? null : spanText((error['detail'] ?? error['message'] ?? '').toString()),
    );
  }
}

class QaCheck {
  final String name;
  final String label;
  final String result;
  final bool passed;
  final String details;

  const QaCheck({required this.name, required this.label, required this.result, required this.passed, required this.details});

  bool get hasNotes => result.contains('NOTES');

  factory QaCheck.fromJson(Map<String, dynamic> json) => QaCheck(
        name: json['name']?.toString() ?? '',
        label: spanText(json['label']?.toString() ?? ''),
        result: json['result']?.toString() ?? '',
        passed: json['passed'] == true,
        details: spanText(json['details']?.toString() ?? ''),
      );
}

class ReportQa {
  final String? result;
  final List<QaCheck> checks;
  final List<String> fixed;
  final List<String> open;
  final List<String> visualReview;

  const ReportQa({this.result, this.checks = const [], this.fixed = const [], this.open = const [], this.visualReview = const []});

  factory ReportQa.fromJson(Map<String, dynamic> json) => ReportQa(
        result: json['result']?.toString(),
        checks: _mapList(json['checks']).map(QaCheck.fromJson).toList(),
        fixed: _strings(json['fixed']),
        open: _strings(json['open']),
        visualReview: _strings(json['visualReview']),
      );
}

class InspectorQuestion {
  final String field;
  final String question;
  final String? leftAs;

  const InspectorQuestion({required this.field, required this.question, this.leftAs});

  factory InspectorQuestion.fromJson(Map<String, dynamic> json) => InspectorQuestion(
        field: json['field']?.toString() ?? '',
        question: spanText(json['question']?.toString() ?? ''),
        leftAs: json['leftAs']?.toString(),
      );
}

class ReportStats {
  final int? durationSeconds;
  final int? pages;
  final int? examplePages;
  final int? photosPlaced;
  final int? photosTotal;
  final int? findingsCovered;
  final int? findingsTotal;

  const ReportStats({
    this.durationSeconds,
    this.pages,
    this.examplePages,
    this.photosPlaced,
    this.photosTotal,
    this.findingsCovered,
    this.findingsTotal,
  });

  factory ReportStats.fromJson(Map<String, dynamic> json) => ReportStats(
        durationSeconds: _int(json['durationSeconds']),
        pages: _int(json['pages']),
        examplePages: _int(json['examplePages']),
        photosPlaced: _int(json['photosPlaced']),
        photosTotal: _int(json['photosTotal']),
        findingsCovered: _int(json['findingsCovered']),
        findingsTotal: _int(json['findingsTotal']),
      );
}

class ReportRunDetail {
  final ReportRun run;
  final ReportStats stats;
  final ReportQa qa;
  final List<InspectorQuestion> questions;
  final String? notes;
  final String? reportPath;
  final int typicalMinutes;
  final int maxMinutes;
  final int findings;
  final int photos;

  const ReportRunDetail({
    required this.run,
    required this.stats,
    required this.qa,
    required this.questions,
    this.notes,
    this.reportPath,
    this.typicalMinutes = 6,
    this.maxMinutes = 20,
    this.findings = 0,
    this.photos = 0,
  });

  factory ReportRunDetail.fromJson(Map<String, dynamic> json) {
    final timing = _map(json['timing']);
    final inspection = _map(json['inspection']);
    return ReportRunDetail(
      run: ReportRun.fromJson(_map(json['run'])),
      stats: ReportStats.fromJson(_map(json['stats'])),
      qa: ReportQa.fromJson(_map(json['qa'])),
      questions: _mapList(json['questions']).map(InspectorQuestion.fromJson).toList(),
      notes: json['notes']?.toString(),
      reportPath: json['report']?.toString(),
      typicalMinutes: _int(timing['typicalMinutes']) ?? 6,
      maxMinutes: _int(timing['maxMinutes']) ?? 20,
      findings: _int(inspection['findings']) ?? 0,
      photos: _int(inspection['photos']) ?? 0,
    );
  }
}

class GenerationActivity {
  final int index;
  final DateTime? at;

  /// tool | message | error | status
  final String kind;
  final String text;
  final bool failed;

  const GenerationActivity({required this.index, required this.at, required this.kind, required this.text, this.failed = false});

  factory GenerationActivity.fromJson(Map<String, dynamic> json) => GenerationActivity(
        index: _int(json['index']) ?? 0,
        at: _date(json['at']),
        kind: json['kind']?.toString() ?? 'tool',
        text: spanText(json['text']?.toString() ?? ''),
        failed: json['failed'] == true,
      );
}

class GenerationEvents {
  final String status;
  final int nextIndex;
  final List<GenerationActivity> activities;
  final String phaseKey;
  final Map<String, DateTime> phaseStartedAt;
  final DateTime? lastEventAt;

  const GenerationEvents({
    required this.status,
    required this.nextIndex,
    required this.activities,
    required this.phaseKey,
    required this.phaseStartedAt,
    required this.lastEventAt,
  });

  factory GenerationEvents.fromJson(Map<String, dynamic> json) {
    final started = <String, DateTime>{};
    _map(json['phaseStartedAt']).forEach((key, value) {
      final date = _date(value);
      if (date != null) started[key] = date;
    });
    return GenerationEvents(
      status: (json['status']?.toString() ?? 'running').toLowerCase(),
      nextIndex: _int(json['nextIndex']) ?? 0,
      activities: _mapList(json['activities']).map(GenerationActivity.fromJson).toList(),
      phaseKey: _map(json['phase'])['key']?.toString() ?? 'starting',
      phaseStartedAt: started,
      lastEventAt: _date(json['lastEventAt']),
    );
  }
}

/// Rebuild state of the last saved edit.
class ReportEditStatus {
  /// rebuild_pending | rebuilding | rebuilt | rebuild_failed
  final String status;
  final DateTime? savedAt;
  final String? report;

  const ReportEditStatus({required this.status, this.savedAt, this.report});

  bool get isPending => status == 'rebuild_pending' || status == 'rebuilding';

  factory ReportEditStatus.fromJson(Map<String, dynamic> json) => ReportEditStatus(
        status: json['status']?.toString() ?? 'rebuild_pending',
        savedAt: _date(json['savedAt']),
        report: json['report']?.toString(),
      );
}

class ReportFillSection {
  final String id;
  final String? heading;
  final List<String> tokens;

  const ReportFillSection({required this.id, this.heading, this.tokens = const []});

  factory ReportFillSection.fromJson(Map<String, dynamic> json) => ReportFillSection(
        id: json['id']?.toString() ?? '',
        heading: json['heading']?.toString(),
        tokens: json['tokens'] is List ? (json['tokens'] as List).map((e) => e.toString()).toList() : const [],
      );
}

/// A field the inspection didn't answer (shown inline as "Add ...").
class ReportBlankField {
  /// "{{TOKEN}}" or "{{TOKEN}} (item A1-1)"
  final String field;
  final String question;

  const ReportBlankField({required this.field, required this.question});

  String get token {
    final match = RegExp(r'\{\{[^{}]+\}\}').firstMatch(field);
    return match?.group(0) ?? field;
  }
}

/// A generated report as template + fill map (see fill_template.py for the
/// value shapes: text, {text, max_chars}, [parallel rows], {image},
/// {images: [...]}, {{BLOCK:NAME}}: [item maps]).
class ReportFillDocument {
  final Map<String, dynamic> fillMap;

  /// generated | edited
  final String source;
  final ReportEditStatus? edit;
  final String? title;
  final List<ReportFillSection> sections;
  final Map<String, String> labels;
  final List<ReportBlankField> blanks;

  const ReportFillDocument({
    required this.fillMap,
    required this.source,
    this.edit,
    this.title,
    this.sections = const [],
    this.labels = const {},
    this.blanks = const [],
  });

  factory ReportFillDocument.fromJson(Map<String, dynamic> json) {
    final layout = _map(json['layout']);
    final edit = _map(json['edit']);
    return ReportFillDocument(
      fillMap: _map(json['fillMap']),
      source: json['source']?.toString() ?? 'generated',
      edit: edit.isEmpty ? null : ReportEditStatus.fromJson(edit),
      title: layout['title']?.toString(),
      sections: _mapList(layout['sections']).map(ReportFillSection.fromJson).toList(),
      labels: _map(layout['labels']).map((key, value) => MapEntry(key, value.toString())),
      blanks: _mapList(json['blanks'])
          .map((b) => ReportBlankField(field: b['field']?.toString() ?? '', question: spanText(b['question']?.toString() ?? '')))
          .toList(),
    );
  }
}
