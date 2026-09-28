import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:field_report_fe/utils/bytes_download_stub.dart'
    if (dart.library.html) 'package:field_report_fe/utils/bytes_download_web.dart';

import '../../../../services/toast_service.dart';
import '../../../../widgets/breadcrumb/breadcrumb.dart';
import '../../../../widgets/button/button.dart';
import '../../../../widgets/confirmation/confirmation_remove.dart';
import '../../../reports/widgets/profiler/docx_preview_stub.dart'
    if (dart.library.html) '../../../reports/widgets/profiler/docx_preview_web.dart';
import 'report_generation_api.dart';
import 'widgets/generation_progress_panel.dart';
import 'widgets/report_details_sheet.dart';
import 'widgets/report_document_editor.dart';

const String _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// A fixed state to render instead of loading one (local preview only).
class ReportRunPreviewState {
  final ReportRunDetail detail;
  final GenerationEvents? events;
  final DateTime now;

  const ReportRunPreviewState({required this.detail, this.events, required this.now});
}

/// Local preview only: open a field for editing (after an optional edit to
/// the loaded fill map) and/or the details sheet once the report loads.
class ReportEditPreview {
  final FillPath? editing;
  final void Function(Map<String, dynamic> fillMap)? applyEdit;
  final bool openDetails;

  const ReportEditPreview({this.editing, this.applyEdit, this.openDetails = false});
}

/// One Span-generated report for a project inspection.
///
/// - running: a calm progress card (steps, time left, cancel)
/// - ready: the report itself, editable in place. A slim top bar holds the
///   title and quiet actions (Save when edited, Download .docx, and an
///   overflow menu with Regenerate and Details). Details (Span's checks,
///   generation notes) open in a side sheet.
/// - failed / cancelled: what happened and Generate again
///
/// Backed by the Span UI API ([ReportGenerationApi]).
class ReportRunScreen extends StatefulWidget {
  final String projectId;
  final String jobId;
  final ReportRunPreviewState? preview;
  final ReportEditPreview? editPreview;

  const ReportRunScreen({super.key, required this.projectId, required this.jobId, this.preview, this.editPreview});

  @override
  State<ReportRunScreen> createState() => _ReportRunScreenState();
}

class _ReportRunScreenState extends State<ReportRunScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);

  ReportRunDetail? _detail;
  String? _loadError;

  // Progress
  int? _nextEventIndex;
  final List<GenerationActivity> _activities = [];
  String _phaseKey = 'starting';
  final Map<String, DateTime> _phaseStartedAt = {};
  DateTime? _lastEventAt;
  Timer? _pollTimer;
  Timer? _clockTimer;
  int _pollTick = 0;
  bool _polling = false;
  bool _cancelling = false;

  // Ready: the report as an editable document
  ReportFillDocument? _document;
  Map<String, dynamic>? _saved;
  Map<String, dynamic>? _working;
  int _editorVersion = 0;
  bool _dirty = false;
  bool _saving = false;
  bool _fillMapMissing = false;
  Uint8List? _docx;
  String? _docxError;
  bool _regenerating = false;
  bool _previewApplied = false;

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    if (preview != null) {
      _detail = preview.detail;
      final events = preview.events;
      if (events != null) _applyEvents(events);
    } else {
      _refresh();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _status => _detail?.run.status ?? 'running';

  bool get _isRunning => _detail?.run.isRunning ?? false;

  DateTime get _now => widget.preview?.now ?? DateTime.now();

  String _error(Object e) => e.toString().replaceAll('Exception: ', '');

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _refresh({bool quiet = false}) async {
    if (widget.preview != null) return;
    try {
      final detail = await ReportGenerationApi.getRun(widget.jobId);
      if (!mounted) return;
      final wasRunning = _isRunning;
      setState(() {
        _detail = detail;
        _loadError = null;
      });
      if (wasRunning && detail.run.status == 'ready') {
        ToastService.show(context, type: ToastType.success, message: 'Your report is ready.');
      }
      _syncPolling();
      if (detail.run.status == 'ready' && _document == null && !_fillMapMissing) _loadDocument(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!quiet || _detail == null) _loadError = _error(e);
      });
    }
  }

  Future<void> _loadDocument(ReportRunDetail detail) async {
    try {
      final document = await ReportGenerationApi.getFillMap(widget.jobId);
      if (!mounted) return;
      final working = copyFillMap(document.fillMap);
      final edit = widget.editPreview;
      if (edit?.applyEdit != null && !_previewApplied) {
        edit!.applyEdit!(working);
        _previewApplied = true;
      }
      setState(() {
        _document = document;
        _saved = copyFillMap(document.fillMap);
        _working = working;
        _dirty = !fillMapsEqual(working, _saved!);
      });
      if (edit?.openDetails == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _detail != null) showReportDetailsSheet(context, _detail!);
        });
      }
    } catch (e) {
      // No fill map (older runs): show the Word file read-only instead.
      if (!mounted) return;
      setState(() => _fillMapMissing = true);
      if (detail.reportPath != null) _loadDocx(detail.reportPath!);
    }
  }

  void _syncPolling() {
    if (_isRunning) {
      _pollTimer ??= Timer.periodic(_pollInterval, (_) => _poll());
      _clockTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (_nextEventIndex == null) _poll();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _clockTimer?.cancel();
      _clockTimer = null;
    }
  }

  void _applyEvents(GenerationEvents events) {
    final seen = _activities.map((a) => a.index).toSet();
    _nextEventIndex = events.nextIndex;
    for (final activity in events.activities) {
      if (!seen.contains(activity.index)) _activities.add(activity);
    }
    if (_activities.length > 200) _activities.removeRange(0, _activities.length - 200);
    events.phaseStartedAt.forEach((key, value) {
      final existing = _phaseStartedAt[key];
      if (existing == null || value.isBefore(existing)) _phaseStartedAt[key] = value;
    });
    // Steps only move forward (QA loops back to filling, the UI doesn't).
    if (generationPhaseIndex(events.phaseKey) > generationPhaseIndex(_phaseKey)) _phaseKey = events.phaseKey;
    _lastEventAt = events.lastEventAt ?? _lastEventAt;
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    _pollTick++;
    try {
      final events = await ReportGenerationApi.getEvents(widget.jobId, since: _nextEventIndex);
      if (!mounted) return;
      setState(() => _applyEvents(events));
      if (events.status != _status || _pollTick % 3 == 0) await _refresh(quiet: true);
    } catch (_) {
      // Transient network errors: keep polling.
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadDocx(String path) async {
    try {
      final bytes = await ReportGenerationApi.getFileBytes(widget.jobId, path);
      if (mounted) setState(() => _docx = bytes);
    } catch (e) {
      if (mounted) setState(() => _docxError = _error(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  String get _title => _detail?.run.templateName ?? 'Report';

  String get _downloadName {
    final run = _detail?.run;
    final base = '${run?.inspectionName ?? 'Report'} - ${run?.templateName ?? 'Span'}';
    final safe = base.replaceAll(RegExp(r'[^\w\- ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${safe.isEmpty ? 'report' : safe}.docx';
  }

  Future<void> _download() async {
    try {
      // The rebuilt Word file once an edit has been applied, else the generated one.
      final edited = _document?.edit?.status == 'rebuilt' ? _document?.edit?.report : null;
      final path = edited ?? _detail?.reportPath ?? 'generated/filled.docx';
      final bytes = path == _detail?.reportPath && _docx != null ? _docx! : await ReportGenerationApi.getFileBytes(widget.jobId, path);
      await downloadBytesWeb(bytes, fileName: _downloadName, mimeType: _docxMime);
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    }
  }

  void _openRun(String jobId) => context.go('/projects/${widget.projectId}/reports/runs/$jobId');

  Future<void> _confirmCancel() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Cancel Report',
        description: 'Stop Span now? Nothing is added to the project until a report finishes.',
        confirmLabel: 'Stop writing',
        cancelLabel: 'Keep going',
        confirmColor: Theme.of(context).colorScheme.error,
        onConfirm: () async {
          setState(() => _cancelling = true);
          try {
            await ReportGenerationApi.cancelRun(widget.jobId);
            await _refresh(quiet: true);
          } catch (e) {
            if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
          } finally {
            if (mounted) setState(() => _cancelling = false);
          }
        },
      ),
    );
  }

  Future<void> _regenerate() async {
    final run = _detail?.run;
    if (run == null || run.inspectionId == null) return;
    setState(() => _regenerating = true);
    try {
      final next = await ReportGenerationApi.startRun(templateId: run.templateId, inspectionId: run.inspectionId!);
      if (mounted) _openRun(next.jobId);
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _confirmRegenerate() async {
    if (widget.preview != null) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Regenerate Report',
        description: _dirty
            ? 'Span writes a new report from the inspection. Your unsaved changes here are not carried over.'
            : 'Span writes a new report from the inspection. This one stays in the project\'s reports.',
        confirmLabel: 'Regenerate',
        cancelLabel: 'Cancel',
        onConfirm: _regenerate,
      ),
    );
  }

  void _onEdited() {
    final working = _working;
    final saved = _saved;
    if (working == null || saved == null) return;
    final dirty = !fillMapsEqual(working, saved);
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  void _discard() {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      _working = copyFillMap(saved);
      _dirty = false;
      _editorVersion++;
    });
  }

  Future<void> _save() async {
    final working = _working;
    if (working == null) return;
    if (widget.preview != null || widget.editPreview != null) {
      ToastService.show(context, type: ToastType.info, message: 'Preview: changes are not saved.');
      return;
    }
    setState(() => _saving = true);
    try {
      final status = await ReportGenerationApi.saveEdits(widget.jobId, working);
      if (!mounted) return;
      final document = _document!;
      setState(() {
        _saved = copyFillMap(working);
        _dirty = false;
        _document = ReportFillDocument(
          fillMap: _saved!,
          source: 'edited',
          edit: status,
          title: document.title,
          sections: document.sections,
          labels: document.labels,
          blanks: document.blanks,
        );
      });
      ToastService.show(context, type: ToastType.success, message: 'Changes saved. The Word file is being updated.');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _pickPhoto() async {
    if (widget.preview != null || widget.editPreview != null) {
      ToastService.show(context, type: ToastType.info, message: 'Preview: photos are not uploaded.');
      return null;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return null;
    try {
      return await ReportGenerationApi.uploadPhoto(widget.jobId, file.bytes!, file.name);
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = _detail?.run;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Projects', onTap: () => context.go('/projects')),
            BreadcrumbItem(label: run?.inspectionName ?? 'Project', onTap: () => context.go('/projects/${widget.projectId}/reports')),
            BreadcrumbItem(label: 'Reports', onTap: () => context.go('/projects/${widget.projectId}/reports')),
            BreadcrumbItem(label: _title),
          ],
        ),
        const SizedBox(height: 12),
        _topBar(theme),
        const SizedBox(height: 16),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _topBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final detail = _detail;
    final ready = detail?.run.status == 'ready';
    final edit = _document?.edit;
    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Back to reports',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/projects/${widget.projectId}/reports'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (detail?.run.inspectionName != null)
                Text(
                  detail!.run.inspectionName!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        if (ready) ...[
          if (_dirty) ...[
            Text('Unsaved changes', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            TextButton(onPressed: _saving ? null : _discard, child: const Text('Discard')),
            const SizedBox(width: 4),
            Button(
              label: 'Save',
              icon: Icons.check_rounded,
              isLoading: _saving,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(width: 8),
          ] else if (edit != null && edit.isPending) ...[
            Icon(Icons.sync_rounded, size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Saved · updating Word file', style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
          ],
          Button(
            label: 'Download .docx',
            icon: Icons.download_rounded,
            variant: _dirty ? ButtonVariant.outline : ButtonVariant.filled,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onPressed: detail?.reportPath == null ? null : _download,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_horiz_rounded, color: colorScheme.onSurfaceVariant),
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'regenerate') _confirmRegenerate();
              if (value == 'details' && _detail != null) showReportDetailsSheet(context, _detail!);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'regenerate',
                enabled: !_regenerating,
                child: const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded, size: 18),
                  title: Text('Regenerate'),
                ),
              ),
              const PopupMenuItem(
                value: 'details',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline_rounded, size: 18),
                  title: Text('Details'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (widget.preview == null && !ReportGenerationApi.isConfigured) {
      return _centeredMessage(
        theme,
        icon: Icons.settings_outlined,
        title: 'Report generation is not configured',
        message: 'Set EVE_UI_BASE_URL (and EVE_UI_KEY) in the app config, then reload.',
      );
    }
    final detail = _detail;
    if (detail == null) {
      if (_loadError != null) {
        return _centeredMessage(
          theme,
          icon: Icons.error_outline,
          title: 'Could not load this report',
          message: _loadError!,
          isError: true,
          action: Button(label: 'Retry', icon: Icons.refresh, onPressed: _refresh),
        );
      }
      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    }

    if (detail.run.isRunning) {
      return _scroll(
        maxWidth: 640,
        topPadding: 24,
        child: GenerationProgressPanel(
          templateName: detail.run.templateName ?? 'Report template',
          inspectionName: detail.run.inspectionName ?? 'Inspection',
          phaseKey: _phaseKey,
          phaseStartedAt: _phaseStartedAt,
          startedAt: detail.run.createdAt,
          now: _now,
          lastEventAt: _lastEventAt,
          typicalMinutes: detail.typicalMinutes,
          maxMinutes: detail.maxMinutes,
          latestActivity: _activities.isEmpty ? null : _activities.last,
          isCancelling: _cancelling,
          onCancel: _confirmCancel,
        ),
      );
    }
    if (detail.run.status == 'ready') return _buildReport(theme, detail);
    return _scroll(maxWidth: 640, topPadding: 24, child: _buildStopped(theme, detail));
  }

  Widget _scroll({required double maxWidth, required Widget child, double topPadding = 0}) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: topPadding, right: 4, bottom: 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }

  // --- Ready: the report is the page -------------------------------------------

  Widget _buildReport(ThemeData theme, ReportRunDetail detail) {
    final document = _document;
    final working = _working;
    if (document != null && working != null) {
      return _scroll(
        maxWidth: 860,
        topPadding: 8,
        child: ReportDocumentEditor(
          key: ValueKey('${widget.jobId}-$_editorVersion'),
          document: document,
          fillMap: working,
          title: _title,
          onChanged: _onEdited,
          loadPhoto: (path) => ReportGenerationApi.getPhotoBytes(widget.jobId, path),
          pickPhoto: _pickPhoto,
          initialEditing: widget.editPreview?.editing,
        ),
      );
    }
    if (!_fillMapMissing) return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));

    // Read-only fallback: the Word file as generated.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(color: const Color(0xFFF4F6F8), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: _docx != null
              ? DocxPreviewView(key: ValueKey(widget.jobId), bytes: _docx!)
              : Center(
                  child: _docxError != null
                      ? Text(_docxError!, style: TextStyle(color: theme.colorScheme.error))
                      : detail.reportPath == null
                          ? const Text('No report file was saved for this run.')
                          : const CircularProgressIndicator(),
                ),
        ),
      ),
    );
  }

  // --- Failed / cancelled -------------------------------------------------------

  Widget _buildStopped(ThemeData theme, ReportRunDetail detail) {
    final failed = detail.run.status == 'failed';
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed ? 'Span couldn\'t finish this report' : 'This report was cancelled',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (detail.run.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              detail.run.errorMessage!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          Button(
            label: 'Generate again',
            icon: Icons.refresh_rounded,
            isLoading: _regenerating,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onPressed: _regenerating ? null : _regenerate,
          ),
        ],
      ),
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
