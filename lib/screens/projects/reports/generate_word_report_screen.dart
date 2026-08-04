import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:field_report_fe/core/api_service.dart';

import 'package:field_report_fe/utils/bytes_download_stub.dart'
    if (dart.library.html) 'package:field_report_fe/utils/bytes_download_web.dart';

import 'services/eve_generate_docx_api_service.dart';

/// Project → Reports: generate a filled Word (.docx) from a ready Eve profile.
///
/// Flow:
/// 1. Load this project's inspections.
/// 2. Load company report templates and **only offer** the ones whose Word
///    profile has finished (`profile_status == ready`) — see
///    `screens/reports/word_profile_template_screen.dart` for how a profile
///    gets built in the first place.
/// 3. POST `/inspection/report/generate-docx` → poll until ready/failed.
/// 4. Download the filled `.docx` and show the `generation-notes.md` Eve
///    wrote about what it did / had to guess at.
///
/// This screen does **not** upload sample reports — profiling belongs on
/// Templates → Reports. The existing HTML report flow (skills-based) is
/// untouched and still lives on `CreateReportScreen`.
class GenerateWordReportScreen extends StatefulWidget {
  final String projectId;

  const GenerateWordReportScreen({super.key, required this.projectId});

  @override
  State<GenerateWordReportScreen> createState() =>
      _GenerateWordReportScreenState();
}

class _GenerateWordReportScreenState extends State<GenerateWordReportScreen> {
  static const Duration _pollInterval = Duration(seconds: 3);
  // Fill jobs can run several AI calls in sequence — match the profile
  // screen's long poll budget rather than a short request timeout.
  static const Duration _pollTimeout = Duration(minutes: 20);

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isDownloading = false;
  String? _error;

  List<Map<String, dynamic>> _inspections = [];
  final List<Map<String, dynamic>> _selectedInspections = [];

  /// Templates with profile_status == ready only (Word path gate).
  List<Map<String, dynamic>> _readyTemplates = [];
  Map<String, dynamic>? _selectedTemplate;

  String? _jobId;
  String? _reportId;
  String _jobStatus = 'idle';
  String? _statusMessage;
  String? _generationNotes;
  String? _filledDocxUrl;
  String? _notesUrl;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ---------------------------------------------------------------------------
  // Inspection helpers
  // ---------------------------------------------------------------------------

  String? _getInspectionId(Map<String, dynamic> inspection) {
    final primaryId = inspection['id'] ??
        inspection['inspection_id'] ??
        inspection['inspectionId'] ??
        inspection['uuid'];
    final primaryValue = primaryId?.toString().trim();
    if (primaryValue != null && primaryValue.isNotEmpty) {
      return primaryValue;
    }
    return null;
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadInspectionsForProject(),
        _loadReadyTemplates(),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Same route/shape CreateReportScreen uses to list inspections for a
  /// project: GET /inspection/project/:projectId -> { success, data: [...] }.
  Future<void> _loadInspectionsForProject() async {
    final response = await apiService.get('/inspection/project/${widget.projectId}');
    final responseData = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load inspections. '
        'Status code: ${response.statusCode}, Body: ${response.body}',
      );
    }

    List<Map<String, dynamic>> inspections = [];
    if (responseData is Map<String, dynamic> && responseData['data'] is List) {
      inspections = (responseData['data'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    }

    if (!mounted) return;
    setState(() => _inspections = inspections);
  }

  /// Only templates with a ready Eve Word profile are selectable for DOCX
  /// fill — same company list as Templates → Reports, filtered client-side.
  Future<void> _loadReadyTemplates() async {
    final response = await apiService.get('/reportTemplate/getByCompanyId');
    final responseData = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load report templates. '
        'Status code: ${response.statusCode}, Body: ${response.body}',
      );
    }

    List<Map<String, dynamic>> templates = [];
    if (responseData is Map<String, dynamic> && responseData['data'] is List) {
      templates = (responseData['data'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    }

    final ready = templates.where((t) {
      final status = (t['profile_status']?.toString() ?? 'none').toLowerCase();
      return status == 'ready';
    }).toList();

    if (!mounted) return;
    setState(() {
      _readyTemplates = ready;
      if (_selectedTemplate == null && ready.isNotEmpty) {
        _selectedTemplate = ready.first;
      }
    });
  }

  void _toggleInspectionSelection(Map<String, dynamic> inspection) {
    if (_isGenerating) return;
    final id = _getInspectionId(inspection);
    if (id == null) return;

    setState(() {
      final index = _selectedInspections.indexWhere(
        (item) => _getInspectionId(item) == id,
      );
      if (index >= 0) {
        _selectedInspections.removeAt(index);
      } else {
        _selectedInspections.add(inspection);
      }
      // Changing selection clears a prior success so the user regenerates cleanly.
      if (_jobStatus == 'ready') {
        _jobStatus = 'idle';
        _jobId = null;
        _reportId = null;
        _generationNotes = null;
        _filledDocxUrl = null;
        _notesUrl = null;
        _statusMessage = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Generate + poll
  // ---------------------------------------------------------------------------

  String _labelForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'queued':
        return 'Queued…';
      case 'running':
        return 'Generating Word report…';
      case 'ready':
        return 'Word report ready';
      case 'failed':
        return 'Generation failed';
      default:
        return 'Checking status…';
    }
  }

  Future<void> _onGenerate() async {
    if (_isGenerating) return;

    final templateId = _selectedTemplate?['id']?.toString() ?? '';
    final inspectionIds = _selectedInspections
        .map(_getInspectionId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    if (templateId.isEmpty) {
      setState(
        () => _error =
            'Select a template with a ready Word profile (Templates → Reports).',
      );
      return;
    }
    if (inspectionIds.isEmpty) {
      setState(() => _error = 'Select at least one inspection.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
      _jobStatus = 'queued';
      _statusMessage = _labelForStatus('queued');
      _generationNotes = null;
      _filledDocxUrl = null;
      _notesUrl = null;
    });

    try {
      final enqueue = await EveGenerateDocxApiService.enqueueGenerateDocx(
        projectId: widget.projectId,
        reportTemplateId: templateId,
        inspectionIds: inspectionIds,
      );

      final jobId = enqueue['job_id']?.toString() ?? '';
      final reportId = enqueue['report_id']?.toString();
      if (jobId.isEmpty) {
        throw Exception('Generate enqueue response missing job_id.');
      }

      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _reportId = reportId;
        _jobStatus = (enqueue['status']?.toString() ?? 'queued').toLowerCase();
        _statusMessage = _labelForStatus(_jobStatus);
      });

      await _pollUntilSettled(jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _jobStatus = 'failed';
        _error = e.toString();
        _statusMessage = _labelForStatus('failed');
      });
    }
  }

  Future<void> _pollUntilSettled(String jobId) async {
    final deadline = DateTime.now().add(_pollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final job = await EveGenerateDocxApiService.getGenerateDocxJobStatus(jobId);
      final status = (job['status']?.toString() ?? 'unknown').toLowerCase();

      final errorMap = job['error'] is Map
          ? Map<String, dynamic>.from(
              (job['error'] as Map).map(
                (k, v) => MapEntry(k.toString(), v),
              ),
            )
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _jobStatus = status;
        _statusMessage = _labelForStatus(status);
        _reportId = job['report_id']?.toString() ?? _reportId;
      });

      if (status == 'ready') {
        final urls = EveGenerateDocxApiService.extractDownloadUrls(job);
        _filledDocxUrl = urls['filled_docx'];
        _notesUrl = urls['generation_notes'];

        // Fetch notes text for the "Review notes" panel (best-effort).
        String? notesText;
        if (_notesUrl != null && _notesUrl!.isNotEmpty) {
          try {
            notesText = await EveGenerateDocxApiService.downloadTextFromUrl(
              _notesUrl!,
            );
          } catch (_) {
            notesText =
                '(Could not load generation notes. Use Download notes if available.)';
          }
        }

        if (!mounted) return;
        setState(() {
          _isGenerating = false;
          _generationNotes = notesText;
          _statusMessage = 'Word report ready — download below.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Word report ready'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      if (status == 'failed') {
        final message = errorMap['message']?.toString() ??
            errorMap['detail']?.toString() ??
            job['message']?.toString() ??
            'Word report generation failed.';
        throw Exception(message);
      }

      // queued / running → keep waiting.
      await Future.delayed(_pollInterval);
    }

    throw Exception(
      'Timed out waiting for Word generation '
      '(last status: $_jobStatus). Try again or check the API worker.',
    );
  }

  // ---------------------------------------------------------------------------
  // Download artifacts
  // ---------------------------------------------------------------------------

  Future<void> _downloadFilledDocx() async {
    final url = _filledDocxUrl;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No filled.docx download URL yet.');
      return;
    }

    setState(() {
      _isDownloading = true;
      _error = null;
    });

    try {
      final bytes = await EveGenerateDocxApiService.downloadBytesFromUrl(url);
      final fileName =
          'report_${_reportId ?? DateTime.now().millisecondsSinceEpoch}.docx';
      await _downloadBytes(
        bytes,
        fileName: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Word download started'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadNotes() async {
    final url = _notesUrl;
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No generation-notes download URL yet.');
      return;
    }

    setState(() {
      _isDownloading = true;
      _error = null;
    });

    try {
      final bytes = await EveGenerateDocxApiService.downloadBytesFromUrl(url);
      final fileName =
          'generation-notes_${_reportId ?? DateTime.now().millisecondsSinceEpoch}.md';
      await _downloadBytes(bytes, fileName: fileName, mimeType: 'text/markdown');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Web: triggers a browser download. This app currently targets web only
  /// for the Eve Word flow, so non-web platforms surface a clear error
  /// instead of silently doing nothing (see `utils/bytes_download_stub.dart`
  /// for what it would take to support mobile/desktop later).
  Future<void> _downloadBytes(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      await downloadBytesWeb(bytes, fileName: fileName, mimeType: mimeType);
      return;
    }
    throw UnsupportedError(
      'Downloading files is only supported on web in this build.',
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Allow re-generate with the same selection after a successful run.
    final canGenerate = !_isLoading &&
        !_isGenerating &&
        _readyTemplates.isNotEmpty &&
        _selectedTemplate != null &&
        _selectedInspections.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Word Report'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick inspections and a Word-ready template. '
                      'Profiles are built under Templates → Reports.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),

                    // ---- Ready templates ----
                    _sectionCard(
                      title: 'Word-ready template',
                      child: _readyTemplates.isEmpty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No templates with a ready Word profile yet.',
                                  style: TextStyle(color: Colors.orange.shade800),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Go to Templates → Reports → Create from Word '
                                  'examples, build a profile, then return here.',
                                ),
                              ],
                            )
                          : DropdownButtonFormField<String>(
                              value: _selectedTemplate?['id']?.toString(),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Template',
                              ),
                              items: _readyTemplates.map((t) {
                                final id = t['id']?.toString() ?? '';
                                final name = t['name']?.toString() ?? 'Untitled';
                                return DropdownMenuItem<String>(
                                  value: id,
                                  child: Text(name),
                                );
                              }).toList(),
                              onChanged: _isGenerating
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      final match = _readyTemplates.firstWhere(
                                        (t) => t['id']?.toString() == value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                      setState(() {
                                        _selectedTemplate =
                                            match.isEmpty ? null : match;
                                      });
                                    },
                            ),
                    ),
                    const SizedBox(height: 16),

                    // ---- Inspections ----
                    _sectionCard(
                      title: 'Select inspection(s)',
                      child: _inspections.isEmpty
                          ? const Text(
                              'No inspections found for this project.',
                              style: TextStyle(color: Colors.grey),
                            )
                          : Column(
                              children: _inspections.map((inspection) {
                                final id = _getInspectionId(inspection) ?? '';
                                final name =
                                    inspection['name']?.toString() ?? id;
                                final createdAt =
                                    inspection['create_time']?.toString();
                                final dateLabel = createdAt != null
                                    ? DateFormat('dd MMM yyyy, hh:mm a')
                                        .format(DateTime.tryParse(createdAt) ??
                                            DateTime.now())
                                    : null;
                                final isSelected = _selectedInspections.any(
                                  (item) => _getInspectionId(item) == id,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: _isGenerating
                                      ? null
                                      : (_) =>
                                          _toggleInspectionSelection(inspection),
                                  title: Text(dateLabel ?? name),
                                  subtitle: id.isNotEmpty
                                      ? Text('ID: $id')
                                      : null,
                                  contentPadding: EdgeInsets.zero,
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 24),

                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: canGenerate ? _onGenerate : null,
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.description_outlined),
                        label: Text(
                          _jobStatus == 'ready'
                              ? 'Generate again'
                              : 'Generate Word report',
                        ),
                      ),
                    ),

                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (_isGenerating) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              _jobId != null
                                  ? '$_statusMessage (job: $_jobId)'
                                  : _statusMessage!,
                              style: TextStyle(color: Colors.grey.shade800),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],

                    // ---- Success: download + notes ----
                    if (_jobStatus == 'ready') ...[
                      const SizedBox(height: 24),
                      _sectionCard(
                        title: 'Download',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_reportId != null)
                              Text(
                                'Report id: $_reportId',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _isDownloading ||
                                          _filledDocxUrl == null
                                      ? null
                                      : _downloadFilledDocx,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Download .docx'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _isDownloading || _notesUrl == null
                                      ? null
                                      : _downloadNotes,
                                  icon: const Icon(Icons.notes),
                                  label: const Text('Download notes'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'Review notes',
                        child: (_generationNotes == null ||
                                _generationNotes!.trim().isEmpty)
                            ? Text(
                                'No generation notes were returned for this job.',
                                style: TextStyle(color: Colors.grey.shade700),
                              )
                            : SelectableText(
                                _generationNotes!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// Shared card chrome for each setup section (matches other report screens).
  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
