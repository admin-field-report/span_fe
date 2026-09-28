import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../services/toast_service.dart';
import '../../widgets/breadcrumb/breadcrumb.dart';
import '../../widgets/button/button.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../../widgets/form_components/text_field.dart';
import 'controllers/report_profiler_api.dart';
import 'widgets/eve_profile_clarification_sheet.dart';
import 'widgets/profiler/file_drop_stub.dart' if (dart.library.html) 'widgets/profiler/file_drop_web.dart';
import 'widgets/profiler/profiler_outputs_panel.dart';
import 'widgets/profiler/profiler_progress_panel.dart';
import 'widgets/profiler/profiler_status_badge.dart';

/// Report Profiler: create a template from example reports and let Eve
/// build its profile (Word template + instructions + style guide).
///
/// States, driven by the template's profile status:
/// - setup (new / none / failed / cancelled): name, example uploads, Start
/// - running / needs_clarification: live progress with ETA and activity
/// - ready: template preview and editable instructions / style guide
///
/// Backed by the Eve dev tool's Span UI API ([ReportProfilerApi]).
class ReportProfilerDetailScreen extends StatefulWidget {
  /// Null for "new profile".
  final String? templateId;

  const ReportProfilerDetailScreen({super.key, this.templateId});

  @override
  State<ReportProfilerDetailScreen> createState() => _ReportProfilerDetailScreenState();
}

class _PendingFile {
  final String name;
  final Uint8List bytes;

  _PendingFile(this.name, this.bytes);
}

class _ReportProfilerDetailScreenState extends State<ReportProfilerDetailScreen> {
  static const Set<String> _allowedExtensions = {'docx', 'pdf'};
  static const int _maxExamples = 10;
  static const int _maxBytes = 100 * 1024 * 1024;
  static const Duration _pollInterval = Duration(seconds: 4);

  final TextEditingController _nameController = TextEditingController();

  String? _templateId;
  ProfilerDetail? _detail;
  bool _loading = false;
  String? _loadError;

  final List<_PendingFile> _pending = [];
  bool _dragHovering = false;
  void Function()? _stopDropListener;

  bool _starting = false;
  String? _startLabel;
  bool _cancelling = false;
  bool _reopening = false;
  final Set<String> _removingExamples = {};

  // Progress tracking for the current job.
  String? _trackedJobId;
  int? _nextEventIndex;
  final List<ProfilerActivity> _activities = [];
  String _phaseKey = 'starting';
  final Map<String, DateTime> _phaseStartedAt = {};
  DateTime? _lastEventAt;
  Timer? _pollTimer;
  Timer? _clockTimer;
  int _pollTick = 0;
  bool _polling = false;
  String? _promptedClarificationsFor;

  @override
  void initState() {
    super.initState();
    _templateId = widget.templateId;
    _stopDropListener = listenForFileDrops(
      onHover: (hovering) {
        if (mounted && _canEditExamples && _dragHovering != hovering) {
          setState(() => _dragHovering = hovering);
        }
      },
      onDrop: (files) {
        if (!mounted || !_canEditExamples) return;
        _addFiles(files.map((f) => _PendingFile(f.name, f.bytes)).toList());
      },
    );
    if (_templateId != null) _refresh();
  }

  @override
  void dispose() {
    _stopDropListener?.call();
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  String get _status => _detail?.template.status ?? 'none';

  bool get _isRunning => _status == 'running' || _status == 'queued' || _status == 'needs_clarification';

  bool get _isReady => _status == 'ready';

  bool get _canEditExamples => !_isRunning && !_starting && !_isReady;

  String get _title => _detail?.template.name ?? (widget.templateId == null ? 'New profile' : 'Report profile');

  // ---------------------------------------------------------------------------
  // Loading and polling
  // ---------------------------------------------------------------------------

  Future<void> _refresh({bool quiet = false}) async {
    final id = _templateId;
    if (id == null) return;
    if (!quiet) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final detail = await ReportProfilerApi.getTemplate(id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _loadError = null;
      });
      _syncPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet || _detail == null) _loadError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// Start or stop the progress loop to match the template's status.
  void _syncPolling() {
    final job = _detail?.job;
    if (_isRunning && job != null) {
      if (_trackedJobId != job.jobId) {
        _trackedJobId = job.jobId;
        _nextEventIndex = null;
        _activities.clear();
        _phaseKey = 'starting';
        _phaseStartedAt.clear();
        _lastEventAt = null;
      }
      _pollTimer ??= Timer.periodic(_pollInterval, (_) => _poll());
      _clockTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (_nextEventIndex == null) _poll();
      if (_status == 'needs_clarification' &&
          job.clarifications.isNotEmpty &&
          _promptedClarificationsFor != job.jobId) {
        _promptedClarificationsFor = job.jobId;
        WidgetsBinding.instance.addPostFrameCallback((_) => _answerClarifications());
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  Future<void> _poll() async {
    final jobId = _trackedJobId;
    if (_polling || jobId == null) return;
    _polling = true;
    _pollTick++;
    try {
      final events = await ReportProfilerApi.getEvents(jobId, since: _nextEventIndex);
      if (!mounted || jobId != _trackedJobId) return;
      final seen = _activities.map((a) => a.index).toSet();
      setState(() {
        _nextEventIndex = events.nextIndex;
        for (final activity in events.activities) {
          if (!seen.contains(activity.index)) _activities.add(activity);
        }
        if (_activities.length > 200) _activities.removeRange(0, _activities.length - 200);
        events.phaseStartedAt.forEach((key, value) {
          final existing = _phaseStartedAt[key];
          if (existing == null || value.isBefore(existing)) _phaseStartedAt[key] = value;
        });
        // Phases only move forward (the agent revisits earlier kinds of work).
        if (profilerPhaseIndex(events.phaseKey) > profilerPhaseIndex(_phaseKey)) {
          _phaseKey = events.phaseKey;
        }
        _lastEventAt = events.lastEventAt ?? _lastEventAt;
      });
      // Status changed, or every third tick: refresh the template record.
      if (events.status != _status || _pollTick % 3 == 0) {
        await _refresh(quiet: true);
        if (mounted && _isReady) {
          ToastService.show(context, type: ToastType.success, message: 'Profile ready. Review the template and instructions.');
        }
      }
    } catch (_) {
      // Transient network errors: keep polling.
    } finally {
      _polling = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Example files
  // ---------------------------------------------------------------------------

  String? _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : name.substring(dot + 1).toLowerCase();
  }

  void _addFiles(List<_PendingFile> files) {
    final existing = {
      ..._pending.map((f) => f.name),
      ...?_detail?.template.examples.map((e) => e.name),
    };
    final rejected = <String>[];
    var added = 0;
    for (final file in files) {
      if (!_allowedExtensions.contains(_extension(file.name))) {
        rejected.add('${file.name} (only .docx and .pdf)');
        continue;
      }
      if (file.bytes.length > _maxBytes) {
        rejected.add('${file.name} (over 100 MB)');
        continue;
      }
      if (existing.contains(file.name)) continue;
      if (_exampleCount + added >= _maxExamples) {
        rejected.add('${file.name} (limit is $_maxExamples examples)');
        continue;
      }
      _pending.add(file);
      existing.add(file.name);
      added++;
    }
    setState(() {});
    if (rejected.isNotEmpty) {
      ToastService.show(context, type: ToastType.warning, message: 'Skipped: ${rejected.join(', ')}');
    }
  }

  int get _exampleCount => _pending.length + (_detail?.template.examples.length ?? 0);

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.toList(),
      withData: true,
    );
    if (result == null) return;
    _addFiles([
      for (final file in result.files)
        if (file.bytes != null) _PendingFile(file.name, file.bytes!),
    ]);
  }

  Future<void> _removeUploaded(ProfilerExample example) async {
    final id = _templateId;
    if (id == null) return;
    setState(() => _removingExamples.add(example.pathname));
    try {
      await ReportProfilerApi.deleteExample(id, example.pathname);
      await _refresh(quiet: true);
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _removingExamples.remove(example.pathname));
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _startProfiling() async {
    final isNew = _templateId == null;
    final name = _nameController.text.trim();
    if (isNew && name.isEmpty) {
      ToastService.show(context, type: ToastType.error, message: 'Enter a template name.');
      return;
    }
    if (_exampleCount == 0) {
      ToastService.show(context, type: ToastType.error, message: 'Add at least one example report.');
      return;
    }

    setState(() {
      _starting = true;
      _startLabel = isNew ? 'Creating template…' : 'Preparing…';
    });
    try {
      var id = _templateId;
      if (id == null) {
        final created = await ReportProfilerApi.createTemplate(name);
        id = created.id;
        if (!mounted) return;
        setState(() => _templateId = id);
      }

      final total = _pending.length;
      for (var i = 0; i < total; i++) {
        final file = _pending.first;
        if (!mounted) return;
        setState(() => _startLabel = 'Uploading ${i + 1} of $total…');
        await ReportProfilerApi.uploadExample(id, name: file.name, bytes: file.bytes);
        if (!mounted) return;
        setState(() => _pending.removeAt(0));
      }

      if (!mounted) return;
      setState(() => _startLabel = 'Starting Span…');
      await ReportProfilerApi.startProfile(id);
      if (!mounted) return;
      if (isNew) {
        // Move to the template's own URL (reloadable, shows up in history as
        // the profile, not "new"); that screen picks up the running job.
        context.replace('/templates/reports/profiler/$id');
        return;
      }
      await _refresh(quiet: true);
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
        await _refresh(quiet: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
          _startLabel = null;
        });
      }
    }
  }

  Future<void> _confirmCancel() async {
    final jobId = _detail?.job?.jobId;
    if (jobId == null) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Cancel Profiling',
        description: 'Stop Span now? Work done so far is kept, and you can resume the run or start over.',
        confirmLabel: 'Stop profiling',
        cancelLabel: 'Keep running',
        confirmColor: Theme.of(context).colorScheme.error,
        onConfirm: () async {
          setState(() => _cancelling = true);
          try {
            await ReportProfilerApi.cancelJob(jobId);
            await _refresh(quiet: true);
          } catch (e) {
            if (mounted) {
              ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
            }
          } finally {
            if (mounted) setState(() => _cancelling = false);
          }
        },
      ),
    );
  }

  Future<void> _answerClarifications() async {
    final job = _detail?.job;
    if (job == null || job.clarifications.isEmpty || !mounted) return;
    final answers = await EveProfileClarificationSheet.show(context, questions: job.clarifications);
    if (answers == null || answers.isEmpty || !mounted) return;
    try {
      await ReportProfilerApi.answerClarifications(job.jobId, answers);
      if (!mounted) return;
      ToastService.show(context, type: ToastType.success, message: 'Answers sent. Span is continuing.');
      await _refresh(quiet: true);
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _reopen() async {
    final jobId = _detail?.job?.jobId;
    if (jobId == null) return;
    setState(() => _reopening = true);
    try {
      await ReportProfilerApi.reopenJob(jobId);
      await _refresh(quiet: true);
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _reopening = false);
    }
  }

  Future<void> _confirmRerun() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Re-run Profiler',
        description:
            'Build the profile again from the examples? This replaces the current template, instructions and style guide, '
            'including any edits you saved.',
        confirmLabel: 'Re-run',
        confirmColor: Theme.of(context).colorScheme.primary,
        onConfirm: () async {
          final id = _templateId;
          if (id == null) return;
          try {
            await ReportProfilerApi.startProfile(id);
            await _refresh(quiet: true);
          } catch (e) {
            if (mounted) {
              ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
            }
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Reports', onTap: () => context.go('/templates/reports')),
            BreadcrumbItem(label: 'Span Report Profiler', onTap: () => context.go('/templates/reports/profiler')),
            BreadcrumbItem(label: _title),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.go('/templates/reports/profiler'),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (_detail != null) ...[
              const SizedBox(width: 10),
              ProfilerStatusBadge(status: _status),
            ],
            if (_loading) ...[
              const SizedBox(width: 12),
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (!ReportProfilerApi.isConfigured) {
      return _centeredMessage(
        theme,
        icon: Icons.settings_outlined,
        title: 'Report Profiler is not configured',
        message: 'Set EVE_UI_BASE_URL (and EVE_UI_KEY) in the app config, then reload.',
      );
    }
    if (_templateId != null && _detail == null) {
      if (_loadError != null) {
        return _centeredMessage(
          theme,
          icon: Icons.error_outline,
          title: 'Could not load this profile',
          message: _loadError!,
          isError: true,
          action: Button(label: 'Retry', icon: Icons.refresh, onPressed: _refresh),
        );
      }
      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    }

    final Widget content;
    if (_isRunning) {
      content = _buildProgress();
    } else if (_isReady) {
      content = _buildOutputs(theme);
    } else {
      content = _buildSetup(theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 4, bottom: 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _isReady ? 1100 : 820),
          child: content,
        ),
      ),
    );
  }

  // --- Setup ------------------------------------------------------------------

  Widget _buildSetup(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isNew = _templateId == null;
    final template = _detail?.template;
    final job = _detail?.job;
    final failed = _status == 'failed';
    final cancelled = _status == 'cancelled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(
          theme,
          icon: Icons.auto_awesome_rounded,
          title: isNew ? 'Build a template from your reports' : template!.name,
          subtitle:
              'Span studies your example reports and builds a reusable Word template, plus the instructions '
              'and writing style it follows to fill it in.',
        ),
        const SizedBox(height: 20),

        if (failed || cancelled) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: failed ? colorScheme.errorContainer : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                  color: failed ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failed ? 'The last run failed' : 'The last run was cancelled',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: failed ? colorScheme.onErrorContainer : colorScheme.onSurface,
                        ),
                      ),
                      if ((job?.errorDetail ?? job?.errorMessage ?? template?.error) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          (job?.errorDetail ?? job?.errorMessage ?? template?.error)!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: failed ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Resume picks up where Span stopped. Start profiling runs it again from the beginning.',
                        style: TextStyle(
                          fontSize: 12,
                          color: failed ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Button(
                  label: 'Resume run',
                  icon: Icons.play_arrow_rounded,
                  variant: ButtonVariant.outline,
                  isLoading: _reopening,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: _reopening || _starting ? null : _reopen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (isNew) ...[
          const Text('Template Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          AbsorbPointer(
            absorbing: _starting,
            child: FormControlTextField(
              controller: _nameController,
              hintText: 'e.g., Monthly Inspection Report',
              prefixIcon: Icons.description_outlined,
              textInputAction: TextInputAction.done,
            ),
          ),
          const SizedBox(height: 24),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle(theme, 'Example Reports ($_exampleCount/$_maxExamples)', Icons.description_outlined),
            Button(
              label: 'Browse files',
              icon: Icons.upload_file_rounded,
              variant: ButtonVariant.outline,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: _canEditExamples && _exampleCount < _maxExamples ? _pickFiles : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dropZone(theme),
        const SizedBox(height: 12),
        ..._exampleTiles(theme),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Profiling usually takes 9–16 minutes (occasionally up to 30). You can leave the page while it runs.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 16),
            Button(
              label: _startLabel ?? 'Start profiling',
              icon: Icons.auto_awesome_rounded,
              isLoading: _starting,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              onPressed: _starting || _exampleCount == 0 ? null : _startProfiling,
            ),
          ],
        ),
      ],
    );
  }

  Widget _dropZone(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final active = _dragHovering && _canEditExamples;
    return InkWell(
      onTap: _canEditExamples && _exampleCount < _maxExamples ? _pickFiles : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primaryContainer.withValues(alpha: 0.35)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? colorScheme.primary : colorScheme.outlineVariant,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              active ? Icons.file_download_outlined : Icons.cloud_upload_outlined,
              size: 32,
              color: active ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              active ? 'Drop to add these reports' : 'Drag and drop example reports here, or click to browse',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '.docx or .pdf, up to 100 MB each. 2–5 filled-in reports of the same type work best; Word files give the most faithful template.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _exampleTiles(ThemeData theme) {
    final uploaded = _detail?.template.examples ?? const <ProfilerExample>[];
    final tiles = <Widget>[];
    for (final example in uploaded) {
      final removing = _removingExamples.contains(example.pathname);
      tiles.add(_exampleTile(
        theme,
        name: example.name,
        subtitle: 'Uploaded · ${_formatSize(example.size)}',
        trailing: removing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                tooltip: 'Remove example',
                onPressed: _canEditExamples ? () => _removeUploaded(example) : null,
              ),
      ));
    }
    for (final file in List<_PendingFile>.from(_pending)) {
      tiles.add(_exampleTile(
        theme,
        name: file.name,
        subtitle: 'Ready to upload · ${_formatSize(file.bytes.length)}',
        trailing: IconButton(
          icon: Icon(Icons.close_rounded, color: theme.colorScheme.error),
          tooltip: 'Remove',
          onPressed: _starting ? null : () => setState(() => _pending.remove(file)),
        ),
      ));
    }
    return [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        tiles[i],
      ],
    ];
  }

  Widget _exampleTile(ThemeData theme, {required String name, required String subtitle, required Widget trailing}) {
    final isPdf = name.toLowerCase().endsWith('.pdf');
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isPdf
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.5)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
          child: Icon(
            isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
            color: isPdf ? theme.colorScheme.error : theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: trailing,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  // --- Progress ---------------------------------------------------------------

  Widget _buildProgress() {
    final detail = _detail!;
    final job = detail.job;
    return ProfilerProgressPanel(
      status: _status,
      phaseKey: _phaseKey,
      phaseStartedAt: _phaseStartedAt,
      startedAt: job?.createdAt ?? DateTime.now(),
      now: DateTime.now(),
      lastEventAt: _lastEventAt,
      typicalMinutes: detail.typicalMinutes,
      maxMinutes: detail.maxMinutes,
      activities: _activities,
      clarificationCount: job?.clarifications.length ?? 0,
      isCancelling: _cancelling,
      onCancel: _confirmCancel,
      onAnswer: _answerClarifications,
    );
  }

  // --- Outputs ----------------------------------------------------------------

  Widget _buildOutputs(ThemeData theme) {
    final detail = _detail!;
    final template = detail.template;
    final builtAt = template.builtAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerCard(
          theme,
          icon: Icons.check_circle_outline_rounded,
          title: 'Profile ready',
          subtitle:
              'Built from ${template.examples.length} example${template.examples.length == 1 ? '' : 's'}'
              '${builtAt != null ? ' on ${DateFormat('dd MMM yyyy, hh:mm a').format(builtAt)}' : ''}. '
              'Review the template, then adjust the instructions and style guide if needed.',
          action: Button(
            label: 'Re-run profiler',
            icon: Icons.refresh_rounded,
            variant: ButtonVariant.outline,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onPressed: _confirmRerun,
          ),
        ),
        const SizedBox(height: 20),
        ProfilerOutputsPanel(
          key: ValueKey('outputs-${template.id}-${detail.job?.jobId}'),
          templateId: template.id,
          templateName: template.name,
          pack: detail.pack,
        ),
      ],
    );
  }

  // --- Shared pieces ------------------------------------------------------------

  Widget _headerCard(ThemeData theme, {required IconData icon, required String title, required String subtitle, Widget? action}) {
    final narrow = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                // Narrow screens: the action goes under the text.
                if (action != null && narrow) ...[const SizedBox(height: 12), action],
              ],
            ),
          ),
          if (action != null && !narrow) ...[const SizedBox(width: 16), action],
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _centeredMessage(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
    bool isError = false,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}
