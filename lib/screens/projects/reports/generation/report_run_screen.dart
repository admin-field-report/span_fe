import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../services/toast_service.dart';
import '../../../../span_doc/docx_model.dart';
import '../../../../span_doc/editor_toolbar.dart';
import '../../../../span_doc/fill_binding.dart';
import '../../../../span_doc/fill_values.dart';
import '../../../../span_doc/report_page_view.dart';
import '../../../../span_doc/rich_field_controller.dart';
import '../../../../utils/save_report_file.dart';
import '../../../../widgets/breadcrumb/breadcrumb.dart';
import '../../../../widgets/confirmation/confirmation_remove.dart';
import '../../../reports/controllers/report_profiler_api.dart';
import '../../controllers/project_controller.dart';
import 'report_generation_api.dart';
import 'widgets/report_details_sheet.dart';
import 'widgets/report_photo_sidebar.dart';
import 'widgets/span_progress_card.dart';

const Color _ink = Color(0xFF212529);
const Color _muted = Color(0xFF868E96);
const Color _line = Color(0xFFDEE2E6);

/// Phases in the order a run moves through them (the bar only moves forward).
const List<String> _phaseOrder = ['starting', 'reading', 'writing', 'filling', 'qa', 'visual', 'finishing'];

enum _Save { saved, pending, saving, failed }

/// One report Span writes for an inspection.
///
/// - running: the progress card (plain steps, no agent log). The user can
///   leave; the Reports tab shows the same progress on the report's row.
/// - ready: the report itself as Word pages, edited in place. A fixed toolbar
///   formats the field being edited; the sidebar holds the inspection's
///   photos for swapping. Changes save on their own and the server rebuilds
///   the Word file (and its PDF copy); Download waits for that.
/// - failed / cancelled: what happened and Write again.
class ReportRunScreen extends StatefulWidget {
  final String projectId;
  final String jobId;

  const ReportRunScreen({super.key, required this.projectId, required this.jobId});

  @override
  State<ReportRunScreen> createState() => _ReportRunScreenState();
}

class _ReportRunScreenState extends State<ReportRunScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);
  static const Duration _saveDelay = Duration(milliseconds: 2500);

  ReportRunDetail? _detail;
  String? _loadError;

  // Progress
  String _phaseKey = 'starting';
  Timer? _pollTimer;
  bool _polling = false;
  bool _cancelling = false;

  // Ready
  ReportFillDocument? _document;
  Map<String, dynamic>? _fill;
  DocxDocument? _template;
  DocxDocument? _bound;
  String? _documentError;
  bool _regenerating = false;

  // Editing
  FillPath? _editingPath;
  RichFieldController? _controller;
  final FocusNode _focus = FocusNode();
  PhotoRef? _selectedPhoto;
  final List<String> _undo = [];
  final List<String> _redo = [];
  DateTime? _lastHistoryAt;
  String? _lastHistoryKey;

  // Saving
  _Save _save = _Save.saved;
  Timer? _saveTimer;
  bool _saveInFlight = false;
  bool _saveAgain = false;
  Timer? _rebuildTimer;
  String? _savedJson;
  Completer<bool>? _savedWaiter;
  String? _downloading;
  bool _uploading = false;

  final Map<String, Future<Uint8List>> _photoCache = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _saveTimer?.cancel();
    _rebuildTimer?.cancel();
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _error(Object e) => e.toString().replaceAll('Exception: ', '');

  bool get _isRunning => _detail?.run.isRunning ?? false;

  String get _reportsPath => '/projects/details/${widget.projectId}/reports';

  // ---------------------------------------------------------------------------
  // Loading and progress
  // ---------------------------------------------------------------------------

  Future<void> _refresh({bool quiet = false}) async {
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
      if (detail.run.status == 'ready' && _document == null && _documentError == null) _loadDocument(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!quiet || _detail == null) _loadError = _error(e);
      });
    }
  }

  void _syncPolling() {
    if (_isRunning) {
      _pollTimer ??= Timer.periodic(_pollInterval, (_) => _poll());
      _poll();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final events = await ReportGenerationApi.getEvents(widget.jobId);
      if (!mounted) return;
      if (_phaseOrder.indexOf(events.phaseKey) > _phaseOrder.indexOf(_phaseKey)) {
        setState(() => _phaseKey = events.phaseKey);
      }
      if (events.status != (_detail?.run.status ?? 'running')) await _refresh(quiet: true);
    } catch (_) {
      // Transient network errors: keep polling.
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadDocument(ReportRunDetail detail) async {
    try {
      final results = await Future.wait([
        ReportGenerationApi.getFillMap(widget.jobId),
        ReportProfilerApi.getFileBytes(detail.run.templateId, 'template.docx'),
      ]);
      final document = results[0] as ReportFillDocument;
      final template = DocxDocument.parse(results[1] as Uint8List);
      if (!mounted) return;
      final fill = copyFillMap(document.fillMap);
      setState(() {
        _document = document;
        _template = template;
        _fill = fill;
        _savedJson = jsonEncode(fill);
        _bound = FillBinder(fill).bind(template);
      });
      if (document.edit?.isPending == true) {
        setState(() => _save = _Save.saving);
        _watchRebuild();
      }
    } catch (e) {
      if (mounted) setState(() => _documentError = _error(e));
    }
  }

  void _rebind() {
    final template = _template;
    final fill = _fill;
    if (template == null || fill == null) return;
    _bound = FillBinder(fill).bind(template);
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  String get _editingKey => _editingPath?.join('/') ?? '';

  void _startEdit(DocxSlot slot) {
    final path = slot.path;
    final fill = _fill;
    if (path == null || fill == null) return;
    if (_editingKey == path.join('/')) return;
    _closeEditor();
    final controller = RichFieldController(valueRuns(fillGet(fill, path)));
    controller.addListener(_onEditorChanged);
    setState(() {
      _selectedPhoto = null;
      _editingPath = path;
      _controller = controller;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _closeEditor() {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_onEditorChanged);
    _controller = null;
    _editingPath = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (mounted) setState(() {});
  }

  void _onEditorChanged() {
    final path = _editingPath;
    final fill = _fill;
    final controller = _controller;
    if (path == null || fill == null || controller == null) return;
    final old = fillGet(fill, path);
    final next = valueWithRuns(old, controller.runs);
    if (jsonEncode(old) == jsonEncode(next)) {
      setState(() {}); // selection / toolbar state
      return;
    }
    _pushHistory(path.join('/'));
    fillSet(fill, path, next);
    setState(() {});
    _changed();
  }

  /// Snapshot before a change; typing in one field within a second is one step.
  void _pushHistory(String key) {
    final now = DateTime.now();
    final sameBurst = _lastHistoryKey == key && _lastHistoryAt != null && now.difference(_lastHistoryAt!) < const Duration(seconds: 1);
    _lastHistoryAt = now;
    _lastHistoryKey = key;
    if (sameBurst) return;
    _undo.add(jsonEncode(_fill));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(String snapshot) {
    _closeEditor();
    setState(() {
      _fill = (jsonDecode(snapshot) as Map).cast<String, dynamic>();
      _selectedPhoto = null;
      _lastHistoryKey = null;
      _rebind();
    });
    _changed();
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    _redo.add(jsonEncode(_fill));
    _restore(_undo.removeLast());
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    _undo.add(jsonEncode(_fill));
    _restore(_redo.removeLast());
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  Future<Uint8List> _loadPhoto(String path) => _photoCache.putIfAbsent(path, () => ReportGenerationApi.getPhotoBytes(widget.jobId, path));

  void _selectPhoto(PhotoRef photo) {
    _closeEditor();
    setState(() => _selectedPhoto = photo);
  }

  /// Photos in the report in page order, for "Photo n".
  List<PhotoRef> _reportPhotos() {
    final out = <PhotoRef>[];
    void visit(List<DocxBlock> blocks) {
      for (final b in blocks) {
        switch (b) {
          case DocxParagraph p:
            for (final i in p.inlines) {
              if (i is DocxImage && i.photo != null && !i.removed) out.add(i.photo!);
              if (i is DocxShape) visit(i.blocks);
            }
          case DocxTable t:
            for (final r in t.rows) {
              for (final c in r.cells) {
                visit(c.blocks);
              }
            }
          case DocxGroup g:
            visit(g.blocks);
        }
      }
    }

    visit(_bound?.body ?? const []);
    return out;
  }

  void _structural(void Function(Map<String, dynamic> fill) change, {PhotoRef? select}) {
    final fill = _fill;
    if (fill == null) return;
    _pushHistory('structure-${DateTime.now().microsecondsSinceEpoch}');
    change(fill);
    setState(() {
      _rebind();
      _selectedPhoto = select;
    });
    _changed();
  }

  void _swapPhoto(String path) {
    final photo = _selectedPhoto;
    if (photo == null) return;
    _structural((fill) => fillSet(fill, photo.imagePath, path), select: photo);
  }

  void _setCaption(String text) {
    final photo = _selectedPhoto;
    final fill = _fill;
    final path = photo?.captionPath;
    if (photo == null || fill == null || path == null) return;
    _pushHistory('caption-${photo.id}');
    fillSet(fill, path, valueWithRuns(fillGet(fill, path), [FillRun(text)]));
    setState(() {});
    _changed();
  }

  void _movePhoto(int delta) {
    final photo = _selectedPhoto;
    final listPath = photo?.listPath;
    final index = photo?.index;
    if (photo == null || listPath == null || index == null) return;
    final list = fillGet(_fill, listPath);
    if (list is! List) return;
    final target = index + delta;
    if (target < 0 || target >= list.length) return;
    final moved = PhotoRef(
      imagePath: _reindex(photo.imagePath, listPath, target),
      captionPath: photo.captionPath == null ? null : _reindex(photo.captionPath!, listPath, target),
      listPath: listPath,
      index: target,
    );
    _structural((_) {
      final item = list[index];
      list[index] = list[target];
      list[target] = item;
    }, select: moved);
  }

  FillPath _reindex(FillPath path, FillPath listPath, int index) => [...listPath, index, ...path.sublist(listPath.length + 1)];

  void _removePhoto() {
    final photo = _selectedPhoto;
    if (photo == null) return;
    final listPath = photo.listPath;
    final index = photo.index;
    final list = listPath == null ? null : fillGet(_fill, listPath);
    _structural((fill) {
      if (list is List && index != null && index < list.length) {
        list.removeAt(index);
      } else {
        // A fixed photo frame: leave it empty (removed from the Word file).
        fillSet(fill, photo.imagePath, null);
      }
    });
  }

  Future<void> _uploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final path = await ReportGenerationApi.uploadPhoto(widget.jobId, file.bytes!, file.name);
      final document = _document;
      if (document != null && !document.album.any((p) => p.path == path)) {
        _document = ReportFillDocument(
          fillMap: document.fillMap,
          source: document.source,
          edit: document.edit,
          title: document.title,
          sections: document.sections,
          labels: document.labels,
          blanks: document.blanks,
          album: [...document.album, AlbumPhoto(path: path, caption: file.name)],
        );
      }
      if (_selectedPhoto != null) _swapPhoto(path);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Saving (automatic) and the Word rebuild
  // ---------------------------------------------------------------------------

  void _changed() {
    final dirty = jsonEncode(_fill) != _savedJson;
    if (!dirty && !_saveInFlight) {
      _saveTimer?.cancel();
      if (_save == _Save.pending) setState(() => _save = _Save.saved);
      return;
    }
    if (_save != _Save.saving) setState(() => _save = _Save.pending);
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveNow);
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    final fill = _fill;
    if (fill == null) return;
    if (_saveInFlight) {
      _saveAgain = true;
      return;
    }
    final json = jsonEncode(fill);
    if (json == _savedJson && _save != _Save.failed) {
      _finishSaved();
      return;
    }
    _saveInFlight = true;
    setState(() => _save = _Save.saving);
    try {
      final status = await ReportGenerationApi.saveEdits(widget.jobId, (jsonDecode(json) as Map).cast<String, dynamic>());
      _savedJson = json;
      _document = _document?.copyWith(source: 'edited', edit: status);
      if (status.status == 'rebuild_failed') {
        _failSave();
      } else {
        _watchRebuild();
      }
    } catch (e) {
      final message = _error(e);
      _saveInFlight = false;
      if (message.contains('still being applied')) {
        // The server is finishing the previous save: try again shortly.
        _saveTimer = Timer(const Duration(seconds: 3), _saveNow);
        return;
      }
      _failSave();
    }
  }

  void _watchRebuild() {
    _saveInFlight = true;
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      try {
        final latest = await ReportGenerationApi.getFillMap(widget.jobId);
        final edit = latest.edit;
        if (!mounted || edit == null || edit.isPending) return;
        _rebuildTimer?.cancel();
        _rebuildTimer = null;
        _saveInFlight = false;
        _document = _document?.copyWith(edit: edit);
        if (edit.status == 'rebuild_failed') {
          _failSave();
          return;
        }
        if (_saveAgain || jsonEncode(_fill) != _savedJson) {
          _saveAgain = false;
          _saveNow();
          return;
        }
        _finishSaved();
        // The PDF copy follows the rebuilt Word file.
        _refresh(quiet: true);
      } catch (_) {
        // Keep polling; a later tick may succeed.
      }
    });
  }

  void _finishSaved() {
    if (!mounted) return;
    setState(() => _save = _Save.saved);
    _savedWaiter?.complete(true);
    _savedWaiter = null;
  }

  void _failSave() {
    _saveInFlight = false;
    if (!mounted) return;
    setState(() => _save = _Save.failed);
    _savedWaiter?.complete(false);
    _savedWaiter = null;
  }

  /// Wait until every change is in the Word file.
  Future<bool> _waitUntilSaved() async {
    if (_save == _Save.saved && !_saveInFlight) return true;
    _savedWaiter ??= Completer<bool>();
    final waiter = _savedWaiter!;
    if (_save == _Save.pending || _save == _Save.failed) _saveNow();
    return waiter.future;
  }

  // ---------------------------------------------------------------------------
  // Download, rewrite, cancel
  // ---------------------------------------------------------------------------

  String get _fileName {
    final run = _detail?.run;
    final project = projectController.currentProject?.name;
    return [if (project != null && project.isNotEmpty) project, run?.inspectionName ?? 'Report', run?.templateName ?? 'Span']
        .join(' - ');
  }

  Future<void> _download(String kind) async {
    if (_downloading != null) return;
    setState(() => _downloading = kind);
    try {
      if (!await _waitUntilSaved()) throw Exception("Your latest changes couldn't be saved, so the file would miss them. Try again.");
      final detail = await ReportGenerationApi.getRun(widget.jobId);
      if (mounted) setState(() => _detail = detail);
      final path = kind == 'pdf' ? detail.pdfPath : (detail.reportPath ?? 'generated/filled.docx');
      if (path == null) throw Exception("The PDF isn't ready for this report yet. Download the Word file, or try again in a minute.");
      final bytes = await ReportGenerationApi.getFileBytes(widget.jobId, path);
      final saved = await saveReportFile(bytes, fileName: _fileName, extension: kind == 'pdf' ? 'pdf' : 'docx');
      if (mounted) {
        ToastService.show(context, type: ToastType.success, message: saved.isEmpty ? 'Downloaded.' : 'Saved to $saved');
      }
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _rewrite() async {
    final run = _detail?.run;
    if (run == null || run.inspectionId == null) return;
    setState(() => _regenerating = true);
    try {
      final next = await ReportGenerationApi.startRun(projectId: widget.projectId, templateId: run.templateId, inspectionId: run.inspectionId!);
      if (mounted) context.go('/projects/${widget.projectId}/reports/runs/${next.jobId}');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _confirmRewrite() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Rewrite with Span',
        description: 'Span writes a new report from the inspection. This one, with your edits, stays in the project\'s reports.',
        confirmLabel: 'Rewrite',
        cancelLabel: 'Cancel',
        onConfirm: _rewrite,
      ),
    );
  }

  Future<void> _confirmCancel() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Stop writing',
        description: 'Stop Span now? Nothing is added to the report until it finishes.',
        confirmLabel: 'Stop',
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _title {
    final run = _detail?.run;
    if (run == null) return 'Report';
    return run.inspectionName == null ? (run.templateName ?? 'Report') : '${run.inspectionName} report';
  }

  @override
  Widget build(BuildContext context) {
    final project = projectController.currentProject?.name;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _closeEditor();
          setState(() => _selectedPhoto = null);
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undoChange,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redoChange,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          AppBreadcrumbs(
            items: [
              BreadcrumbItem(label: 'Projects', onTap: () => context.go('/projects')),
              BreadcrumbItem(label: project ?? 'Project', onTap: () => context.go(_reportsPath)),
              BreadcrumbItem(label: 'Reports', onTap: () => context.go(_reportsPath)),
            ],
          ),
          const SizedBox(height: 12),
          _header(),
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    final ready = _detail?.run.status == 'ready' && _bound != null;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('report-back'),
          tooltip: 'Back to reports',
          icon: const Icon(Icons.chevron_left_rounded, size: 26),
          onPressed: () => context.go(_reportsPath),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _ink),
          ),
        ),
        if (ready) ...[const SizedBox(width: 12), _saveStatus()],
        const Spacer(),
        if (_detail?.run.status == 'ready') ...[
          OutlinedButton(
            key: const ValueKey('report-rewrite'),
            onPressed: _regenerating ? null : _confirmRewrite,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _line),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Rewrite with Span', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          _downloadButton(),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded, color: _muted),
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'details' && _detail != null) showReportDetailsSheet(context, _detail!);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'details', child: Text('Details')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _saveStatus() {
    final (IconData icon, String label, Color color) = switch (_save) {
      _Save.saved => (Icons.cloud_done_outlined, 'Saved', _muted),
      _Save.pending || _Save.saving => (Icons.sync_rounded, 'Saving…', _muted),
      _Save.failed => (Icons.error_outline_rounded, "Couldn't save", const Color(0xFFE03131)),
    };
    return Row(
      key: const ValueKey('save-status'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
        if (_save == _Save.failed)
          TextButton(onPressed: _saveNow, child: const Text('Retry')),
      ],
    );
  }

  Widget _downloadButton() {
    final busy = _downloading != null;
    return PopupMenuButton<String>(
      key: const ValueKey('report-download'),
      tooltip: 'Download',
      enabled: !busy,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: _download,
      itemBuilder: (context) => [
        _downloadItem('docx', 'Word (.docx)', 'Editable. Opens in Microsoft Word'),
        _downloadItem('pdf', 'PDF (.pdf)', 'Ready to send. Made from the Word file'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                : const Icon(Icons.download_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(busy ? (_save == _Save.saved ? 'Downloading…' : 'Saving changes…') : 'Download',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _downloadItem(String value, String title, String detail) => PopupMenuItem(
        key: ValueKey('download-$value'),
        value: value,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined, size: 20, color: _ink),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
        ),
      );

  Widget _body() {
    final detail = _detail;
    if (detail == null) {
      if (_loadError != null) return _message('Could not load this report', _loadError!, action: ('Retry', _refresh));
      return const Center(child: CircularProgressIndicator(color: _ink));
    }
    if (detail.run.isRunning) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 48, bottom: 48),
        child: Center(
          child: SpanProgressCard(
            title: 'Span is writing your report',
            subtitle: '${detail.run.templateName ?? 'Report'} · from the ${detail.run.inspectionName ?? 'inspection'}.',
            steps: reportSteps,
            current: reportStepFor(_phaseKey),
            progress: reportProgressFor(_phaseKey),
            leaveNote: "You can leave this page. Span keeps writing, and the report shows up in Reports when it's done.",
            backLabel: 'Back to Reports',
            onBack: () => context.go(_reportsPath),
            onCancel: _confirmCancel,
            cancelling: _cancelling,
          ),
        ),
      );
    }
    if (detail.run.status != 'ready') return _stopped(detail);
    if (_documentError != null) {
      return _message(
        "This report can't be shown here",
        '$_documentError\nYou can still download it.',
        action: ('Download Word', () => _download('docx')),
      );
    }
    final bound = _bound;
    final fill = _fill;
    if (bound == null || fill == null) return const Center(child: CircularProgressIndicator(color: _ink));

    final photos = _reportPhotos();
    final selected = _selectedPhoto;
    final number = selected == null ? null : photos.indexWhere((p) => p.id == selected.id);
    return Column(
      children: [
        ReportEditorToolbar(
          active: _controller,
          canUndo: _undo.isNotEmpty,
          canRedo: _redo.isNotEmpty,
          onUndo: _undoChange,
          onRedo: _redoChange,
          onChanged: () => _focus.requestFocus(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _viewport(bound, fill)),
              const SizedBox(width: 16),
              ReportPhotoSidebar(
                album: _document?.album ?? const [],
                fill: fill,
                selected: selected,
                selectedNumber: number == null || number < 0 ? null : number + 1,
                loadPhoto: _loadPhoto,
                onSwap: _swapPhoto,
                onCaptionChanged: _setCaption,
                onMoveLeft: selected?.index != null && selected!.index! > 0 ? () => _movePhoto(-1) : null,
                onMoveRight: selected?.listPath != null &&
                        selected!.index != null &&
                        selected.index! < ((fillGet(fill, selected.listPath!) as List?)?.length ?? 0) - 1
                    ? () => _movePhoto(1)
                    : null,
                onRemove: _removePhoto,
                onClose: () => setState(() => _selectedPhoto = null),
                onUpload: _uploadPhoto,
                uploading: _uploading,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewport(DocxDocument bound, Map<String, dynamic> fill) {
    return Container(
      key: const ValueKey('report-viewport'),
      decoration: BoxDecoration(color: const Color(0xFFE9ECEF), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _closeEditor();
          setState(() => _selectedPhoto = null);
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: ReportPageView(
            document: bound,
            fill: fill,
            loadPhoto: _loadPhoto,
            editingKey: _editingPath == null ? null : _editingKey,
            editorBuilder: _editor,
            onTapSlot: _startEdit,
            selectedPhoto: _selectedPhoto?.id,
            onTapPhoto: _selectPhoto,
          ),
        ),
      ),
    );
  }

  Widget _editor(DocxSlot slot, TextStyle style, bool wholeParagraph) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final field = TextField(
      key: const ValueKey('report-field-editor'),
      controller: controller,
      focusNode: _focus,
      maxLines: null,
      style: style.copyWith(backgroundColor: Colors.transparent),
      cursorColor: reportSelectionBlue,
      cursorWidth: 1.2,
      decoration: const InputDecoration.collapsed(hintText: 'Type here'),
      onTapOutside: (_) {},
    );
    final boxed = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFF),
        border: Border.all(color: reportSelectionBlue, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: field,
    );
    if (wholeParagraph) return boxed;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 60, maxWidth: 420),
      child: IntrinsicWidth(child: boxed),
    );
  }

  Widget _stopped(ReportRunDetail detail) {
    final failed = detail.run.status == 'failed';
    return _message(
      failed ? "Span couldn't finish this report" : 'This report was stopped',
      detail.run.errorMessage ?? (failed ? 'Something went wrong while writing.' : 'Nothing was added to the report.'),
      action: ('Write again', _regenerating ? null : _rewrite),
    );
  }

  Widget _message(String title, String body, {(String, VoidCallback?)? action}) {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 14, color: Color(0xFF495057), height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: action.$2,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111111), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
