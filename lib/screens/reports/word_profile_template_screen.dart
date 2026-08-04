import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'controllers/eve_profile_api.dart';
import 'widgets/eve_profile_clarification_sheet.dart';

/// Templates → Reports: create/manage an Eve Word profile from example docs.
///
/// Flow:
/// 1. Name the template (create path) or reuse an existing [templateId].
/// 2. Upload 1–N example files via the presigned `/documents` APIs.
/// 3. POST `/profile/generate` and poll `/profile/status/:jobId`.
/// 4. If the job says `needs_clarification`, show
///    [EveProfileClarificationSheet] and resume the same job with answers.
///
/// This screen intentionally does NOT embed the Eve chat UI — progress here
/// is a simple status panel with a spinner + label, which is enough for a
/// long-running background job the user mostly just waits on.
class WordProfileTemplateScreen extends StatefulWidget {
  /// When set, skip create and operate on this existing report template.
  final String? templateId;

  /// Display name for the app bar / form prefill.
  final String? templateName;

  /// Last known profile job id (e.g. from a list row) so resume can poll
  /// immediately instead of waiting on a metadata refresh first.
  final String? initialJobId;

  /// Last known `profile_status` from the list row.
  final String? initialProfileStatus;

  const WordProfileTemplateScreen({
    super.key,
    this.templateId,
    this.templateName,
    this.initialJobId,
    this.initialProfileStatus,
  });

  @override
  State<WordProfileTemplateScreen> createState() =>
      _WordProfileTemplateScreenState();
}

class _WordProfileTemplateScreenState extends State<WordProfileTemplateScreen> {
  // BE allows the same extensions as the HTML skill example uploads.
  static const Set<String> _allowedExtensions = {
    'pdf',
    'doc',
    'docx',
    'txt',
  };
  static const Duration _pollInterval = Duration(seconds: 3);
  // Profile jobs run several AI tool calls in sequence, so give this a long
  // budget — the user can always reopen the screen to keep polling later.
  static const Duration _pollTimeout = Duration(minutes: 20);

  final TextEditingController _nameController = TextEditingController();

  String? _templateId;
  String? _jobId;
  String _profileStatus = 'none';
  String? _statusMessage;
  String? _error;
  String? _profileError;

  List<PlatformFile> _selectedFiles = [];
  bool _isBusy = false;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _templateId = widget.templateId;
    _jobId = widget.initialJobId;
    _profileStatus = (widget.initialProfileStatus ?? 'none').toLowerCase();
    if (widget.templateName != null && widget.templateName!.trim().isNotEmpty) {
      _nameController.text = widget.templateName!.trim();
    }

    // Resume an in-flight or paused job when opened from a list row badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeResumeExistingJob();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isCreateMode =>
      _templateId == null || _templateId!.trim().isEmpty;

  bool get _isTerminalReady => _profileStatus == 'ready';

  bool get _isInFlight =>
      _profileStatus == 'queued' || _profileStatus == 'running';

  // ---------------------------------------------------------------------------
  // File selection
  // ---------------------------------------------------------------------------

  String? _validateFiles(List<PlatformFile> files) {
    if (files.isEmpty) {
      return 'Upload at least one example report (.docx preferred).';
    }
    if (files.length > 10) {
      return 'Upload at most 10 example files.';
    }
    for (final file in files) {
      final lower = file.name.toLowerCase();
      final dot = lower.lastIndexOf('.');
      if (dot < 0) return 'Every file must have an extension.';
      final ext = lower.substring(dot + 1);
      if (!_allowedExtensions.contains(ext)) {
        return 'Only .pdf, .doc, .docx, and .txt files are allowed.';
      }
      if (file.bytes == null || file.bytes!.isEmpty) {
        return 'Could not read "${file.name}". Re-select the file.';
      }
    }
    return null;
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.toList(),
      withData: true,
    );
    if (result == null) return;

    final validationError = _validateFiles(result.files);
    setState(() {
      _error = validationError;
      if (validationError == null) {
        _selectedFiles = result.files;
      }
    });
  }

  void _removeFile(int index) {
    final updated = List<PlatformFile>.from(_selectedFiles)..removeAt(index);
    setState(() {
      _selectedFiles = updated;
      _error = updated.isEmpty ? null : _validateFiles(updated);
    });
  }

  // ---------------------------------------------------------------------------
  // Job resume / poll / clarifications
  // ---------------------------------------------------------------------------

  /// Called once after the first frame when opening an existing template —
  /// picks up wherever the last known status left off (still running,
  /// waiting on clarifications, or just needs a metadata refresh).
  Future<void> _maybeResumeExistingJob() async {
    if (_isCreateMode) return;

    final status = _profileStatus;
    if (status == 'needs_clarification') {
      await _handleNeedsClarification();
      return;
    }

    if ((status == 'queued' || status == 'running') &&
        _jobId != null &&
        _jobId!.isNotEmpty) {
      await _pollUntilSettled();
      return;
    }

    // Refresh metadata so the panel shows the latest DB pointers (covers
    // the case where the row badge we were opened from is stale).
    try {
      final meta = await EveProfileApi.getProfileMetadata(_templateId!);
      if (!mounted) return;
      setState(() {
        _profileStatus =
            (meta['profile_status']?.toString() ?? _profileStatus).toLowerCase();
        _jobId = meta['profile_job_id']?.toString() ?? _jobId;
        _profileError = meta['profile_error']?.toString();
      });
      if (_profileStatus == 'needs_clarification') {
        await _handleNeedsClarification();
      } else if (_isInFlight && _jobId != null && _jobId!.isNotEmpty) {
        await _pollUntilSettled();
      }
    } catch (_) {
      // Non-fatal on open — the user can still upload / build manually.
    }
  }

  Future<void> _handleNeedsClarification() async {
    if (_templateId == null) return;

    setState(() {
      _isBusy = true;
      _statusMessage = 'Loading clarification questions…';
      _error = null;
    });

    try {
      final data = await EveProfileApi.getProfileClarifications(
        reportTemplateId: _templateId!,
        jobId: _jobId,
      );
      final questions = (data['questions'] is List)
          ? (data['questions'] as List)
              .whereType<Map>()
              .map(
                (item) => Map<String, dynamic>.from(
                  item.map((k, v) => MapEntry(k.toString(), v)),
                ),
              )
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      if (questions.isEmpty) {
        setState(() {
          _isBusy = false;
          _statusMessage =
              'Waiting for clarification, but no questions were returned yet.';
          _profileStatus = 'needs_clarification';
        });
        return;
      }

      setState(() {
        _isBusy = false;
        _profileStatus = 'needs_clarification';
        _statusMessage = 'Answer the questions to continue building the profile.';
      });

      final answers = await EveProfileClarificationSheet.show(
        context,
        questions: questions,
      );
      if (answers == null || answers.isEmpty) return;

      setState(() {
        _isBusy = true;
        _statusMessage = 'Submitting answers and resuming profile job…';
      });

      final submit = await EveProfileApi.submitProfileClarifications(
        reportTemplateId: _templateId!,
        clarificationAnswers: answers,
        jobId: _jobId ?? data['job_id']?.toString(),
      );

      _jobId = submit['job_id']?.toString() ?? _jobId;
      _profileStatus =
          (submit['status']?.toString() ?? 'running').toLowerCase();

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Profile job resumed.';
      });

      await _pollUntilSettled();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pollUntilSettled() async {
    final templateId = _templateId;
    final jobId = _jobId;
    if (templateId == null ||
        templateId.isEmpty ||
        jobId == null ||
        jobId.isEmpty) {
      return;
    }

    setState(() {
      _isPolling = true;
      _isBusy = true;
      _error = null;
    });

    final deadline = DateTime.now().add(_pollTimeout);

    try {
      while (DateTime.now().isBefore(deadline)) {
        final job = await EveProfileApi.getProfileJobStatus(
          reportTemplateId: templateId,
          jobId: jobId,
        );

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
          _profileStatus = status;
          _statusMessage = _labelForStatus(status);
          _profileError = errorMap['message']?.toString() ??
              errorMap['detail']?.toString() ??
              job['profile_error']?.toString();
        });

        if (status == 'ready') {
          setState(() {
            _isBusy = false;
            _isPolling = false;
            _statusMessage = 'Profile ready — this template can generate Word reports.';
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Word profile ready'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        }

        if (status == 'failed') {
          throw Exception(
            _profileError ??
                'Eve profile job failed. Check the template and try again.',
          );
        }

        if (status == 'needs_clarification') {
          setState(() {
            _isPolling = false;
            _isBusy = false;
          });
          await _handleNeedsClarification();
          return;
        }

        // queued / running / unknown → keep polling.
        await Future.delayed(_pollInterval);
      }

      throw Exception(
        'Timed out waiting for the profile job '
        '(last status: $_profileStatus). You can reopen this screen to keep waiting.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isPolling = false;
        _error = e.toString();
      });
    }
  }

  String _labelForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'none':
        return 'No Word profile yet';
      case 'queued':
        return 'Profile job queued…';
      case 'running':
        return 'Building Word profile…';
      case 'needs_clarification':
        return 'Needs your answers to continue';
      case 'ready':
        return 'Profile ready';
      case 'failed':
        return 'Profile build failed';
      case 'cancelled':
        return 'Profile job cancelled';
      default:
        return 'Checking profile status…';
    }
  }

  // ---------------------------------------------------------------------------
  // Primary actions: create + upload + build
  // ---------------------------------------------------------------------------

  Future<void> _startBuild() async {
    final name = _nameController.text.trim();
    if (_isCreateMode && name.isEmpty) {
      setState(() => _error = 'Enter a template name.');
      return;
    }

    final fileError = _selectedFiles.isEmpty && _isCreateMode
        ? 'Upload at least one example Word report before building a profile.'
        : (_selectedFiles.isNotEmpty ? _validateFiles(_selectedFiles) : null);
    if (fileError != null) {
      setState(() => _error = fileError);
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = _isCreateMode
          ? 'Creating template…'
          : 'Preparing profile build…';
    });

    try {
      // 1) Create shell template when this is a brand-new Word path.
      var templateId = _templateId?.trim() ?? '';
      if (templateId.isEmpty) {
        templateId = await EveProfileApi.createTemplate(name);
        if (!mounted) return;
        setState(() {
          _templateId = templateId;
          _statusMessage = 'Uploading example documents…';
        });
      }

      // 2) Upload newly selected examples (optional on resume if docs
      //    already exist on the template from a previous session).
      if (_selectedFiles.isNotEmpty) {
        setState(() => _statusMessage = 'Uploading example documents…');
        final payloads = <({String name, Uint8List bytes})>[];
        for (final file in _selectedFiles) {
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) {
            throw Exception('Unable to read "${file.name}".');
          }
          payloads.add((name: file.name, bytes: bytes));
        }

        await EveProfileApi.uploadExampleDocuments(
          reportTemplateId: templateId,
          files: payloads,
        );
      } else if (_isCreateMode) {
        throw Exception('Example documents are required for a new template.');
      }

      // 3) Enqueue the Eve profile job (requires ≥1 registered document).
      if (!mounted) return;
      setState(() => _statusMessage = 'Starting Word profile job…');

      final enqueue = await EveProfileApi.generateProfile(templateId);
      final jobId = enqueue['job_id']?.toString() ?? '';
      if (jobId.isEmpty) {
        throw Exception('Profile generate response missing job_id.');
      }

      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _profileStatus =
            (enqueue['status']?.toString() ?? 'queued').toLowerCase();
        _statusMessage = _labelForStatus(_profileStatus);
        _selectedFiles = [];
      });

      await _pollUntilSettled();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _isPolling = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _refreshMetadata() async {
    if (_templateId == null || _templateId!.isEmpty) return;
    setState(() {
      _isBusy = true;
      _error = null;
      _statusMessage = 'Refreshing profile status…';
    });
    try {
      final meta = await EveProfileApi.getProfileMetadata(_templateId!);
      if (!mounted) return;
      setState(() {
        _profileStatus =
            (meta['profile_status']?.toString() ?? 'none').toLowerCase();
        _jobId = meta['profile_job_id']?.toString() ?? _jobId;
        _profileError = meta['profile_error']?.toString();
        _statusMessage = _labelForStatus(_profileStatus);
        _isBusy = false;
      });
      if (_profileStatus == 'needs_clarification') {
        await _handleNeedsClarification();
      } else if (_isInFlight && _jobId != null && _jobId!.isNotEmpty) {
        await _pollUntilSettled();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ready':
        return Colors.green.shade700;
      case 'failed':
        return Colors.red.shade700;
      case 'needs_clarification':
        return Colors.orange.shade800;
      case 'queued':
      case 'running':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEditName = _isCreateMode && !_isBusy;
    final canPickFiles = !_isBusy && !_isTerminalReady;
    final canBuild = !_isBusy &&
        !_isPolling &&
        !_isTerminalReady &&
        (_selectedFiles.isNotEmpty || !_isCreateMode);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isCreateMode ? 'Create from Word examples' : 'Word profile',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/templates/reports');
            }
          },
        ),
        actions: [
          if (!_isCreateMode)
            IconButton(
              tooltip: 'Refresh status',
              onPressed: _isBusy ? null : _refreshMetadata,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _isCreateMode
                    ? 'Upload example Word reports. Span will build a reusable profile pack for this company template.'
                    : 'Manage the Eve Word profile for this template. Upload more examples if needed, then build or resume the profile job.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // --- Template name ---
              TextField(
                controller: _nameController,
                enabled: canEditName,
                decoration: const InputDecoration(
                  labelText: 'Template name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Field Report',
                ),
              ),
              const SizedBox(height: 16),

              // --- Status panel ---
              if (!_isCreateMode || _profileStatus != 'none') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _statusColor(_profileStatus).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _statusColor(_profileStatus).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_isPolling || (_isBusy && _isInFlight)) ...[
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _statusColor(_profileStatus),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              _labelForStatus(_profileStatus),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _statusColor(_profileStatus),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                      if (_jobId != null && _jobId!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Job: $_jobId',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      if (_profileError != null &&
                          _profileError!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _profileError!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                      if (_profileStatus == 'needs_clarification') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _isBusy ? null : _handleNeedsClarification,
                          icon: const Icon(Icons.question_answer_outlined),
                          label: const Text('Answer clarifications'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // --- File picker ---
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: canPickFiles ? _pickFiles : null,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      _selectedFiles.isEmpty
                          ? 'Choose example files'
                          : 'Add / replace files',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_selectedFiles.length} selected',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Accepted: .docx (preferred), .doc, .pdf, .txt — 1 to 10 files.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if (_selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...List.generate(_selectedFiles.length, (index) {
                  final file = _selectedFiles[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(file.name, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isBusy ? null : () => _removeFile(index),
                    ),
                  );
                }),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canBuild ? _startBuild : null,
                  icon: _isBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isCreateMode
                        ? 'Create template & build profile'
                        : (_selectedFiles.isNotEmpty
                            ? 'Upload & build profile'
                            : 'Build profile'),
                  ),
                ),
              ),
              if (_isTerminalReady) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/templates/reports'),
                    child: const Text('Back to report templates'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
