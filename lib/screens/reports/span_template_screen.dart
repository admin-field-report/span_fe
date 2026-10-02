import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/toast_service.dart';
import '../../span_doc/docx_model.dart';
import '../../span_doc/report_page_view.dart';
import '../../utils/save_report_file.dart';
import '../../widgets/breadcrumb/breadcrumb.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../projects/reports/generation/widgets/span_progress_card.dart';
import 'controllers/report_profiler_api.dart';
import 'widgets/profiler/file_drop_stub.dart' if (dart.library.html) 'widgets/profiler/file_drop_web.dart';

const Color _ink = Color(0xFF212529);
const Color _muted = Color(0xFF868E96);
const Color _line = Color(0xFFDEE2E6);

const List<String> _phaseOrder = ['starting', 'reading', 'building', 'checking', 'writing', 'packaging'];

/// A report template Span builds from example reports.
///
/// - setup (new, or not built yet): name, 2–5 example reports, Build.
/// - building: the progress card (plain steps). The user can leave; the
///   Report Templates list shows the same progress on the template's row.
///   Span never stops to ask questions.
/// - ready: the template as Word pages with its fields as chips and repeating
///   blocks outlined, and a sidebar with the fields (and where each comes
///   from), the instructions and the style guide, which are editable.
class SpanTemplateScreen extends StatefulWidget {
  final String? templateId;

  const SpanTemplateScreen({super.key, this.templateId});

  @override
  State<SpanTemplateScreen> createState() => _SpanTemplateScreenState();
}

class _PickedExample {
  final String name;
  final Uint8List bytes;

  _PickedExample(this.name, this.bytes);
}

class _Section {
  String heading;
  String body;

  /// Markdown heading level (# = 1), kept when the file is saved.
  final int level;

  _Section(this.heading, this.body, [this.level = 2]);
}

class _SpanTemplateScreenState extends State<SpanTemplateScreen> {
  ProfilerDetail? _detail;
  String? _loadError;

  // Setup
  final TextEditingController _name = TextEditingController();
  final List<_PickedExample> _picked = [];
  bool _starting = false;
  bool _dragging = false;
  void Function()? _unlistenDrops;

  // Building
  String _phaseKey = 'starting';
  Timer? _poll;
  bool _cancelling = false;

  // Ready
  DocxDocument? _template;
  Map<String, dynamic> _spec = {};
  final Map<String, List<_Section>> _texts = {};
  String _tab = 'fields';
  String? _highlightToken;
  String? _highlightGroup;
  String? _highlightSection;
  String? _readyError;
  final Map<String, Timer> _saveTimers = {};
  final Set<String> _unsaved = {};
  int _inFlight = 0;
  bool _saveFailed = false;

  bool get _isSaving => _unsaved.isNotEmpty || _inFlight > 0;
  bool _rebuilding = false;

  String? get _id => widget.templateId ?? _detail?.template.id;

  @override
  void initState() {
    super.initState();
    _unlistenDrops = listenForFileDrops(
      onHover: (hovering) {
        if (mounted && _isSetup) setState(() => _dragging = hovering);
      },
      onDrop: (files) {
        if (!mounted || !_isSetup) return;
        setState(() {
          _dragging = false;
          _addFiles([for (final f in files) _PickedExample(f.name, f.bytes)]);
        });
      },
    );
    if (widget.templateId != null) _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _unlistenDrops?.call();
    _name.dispose();
    super.dispose();
  }

  String _error(Object e) => e.toString().replaceAll('Exception: ', '');

  String get _status => _detail?.template.status ?? 'none';

  bool get _isBuilding => const {'queued', 'running', 'needs_clarification'}.contains(_status);

  bool get _isSetup => widget.templateId == null || const {'none', 'failed', 'cancelled'}.contains(_status);

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    final id = _id;
    if (id == null) return;
    try {
      final detail = await ReportProfilerApi.getTemplate(id);
      if (!mounted) return;
      final wasBuilding = _isBuilding;
      setState(() {
        _detail = detail;
        _loadError = null;
        if (_name.text.isEmpty) _name.text = detail.template.name;
      });
      if (_isBuilding) {
        _poll ??= Timer.periodic(const Duration(seconds: 4), (_) => _pollEvents());
        _pollEvents();
      } else {
        _poll?.cancel();
        _poll = null;
      }
      if (_status == 'ready' && (_template == null || wasBuilding)) _loadReady();
    } catch (e) {
      if (mounted) setState(() => _loadError = _error(e));
    }
  }

  Future<void> _pollEvents() async {
    final jobId = _detail?.template.jobId ?? _detail?.job?.jobId;
    if (jobId == null) return;
    try {
      final events = await ReportProfilerApi.getEvents(jobId);
      if (!mounted) return;
      if (_phaseOrder.indexOf(events.phaseKey) > _phaseOrder.indexOf(_phaseKey)) setState(() => _phaseKey = events.phaseKey);
      if (events.status != _status) {
        await _load();
        if (mounted && _status == 'ready') {
          ToastService.show(context, type: ToastType.success, message: 'Your template is ready.');
        }
      }
    } catch (_) {
      // Keep polling.
    }
  }

  Future<void> _loadReady() async {
    final id = _id!;
    try {
      final results = await Future.wait([
        ReportProfilerApi.getFileBytes(id, 'template.docx'),
        ReportProfilerApi.getFileText(id, 'template-spec.json').catchError((_) => '{}'),
        ReportProfilerApi.getFileText(id, 'instructions.md').catchError((_) => ''),
        ReportProfilerApi.getFileText(id, 'style-guide.md').catchError((_) => ''),
      ]);
      final template = DocxDocument.parse(results[0] as Uint8List);
      Map<String, dynamic> spec = {};
      try {
        spec = (jsonDecode(results[1] as String) as Map).cast<String, dynamic>();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _template = template;
        _spec = spec;
        _texts['instructions.md'] = _sections(results[2] as String);
        _texts['style-guide.md'] = _sections(results[3] as String);
        _readyError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _readyError = _error(e));
    }
  }

  /// Markdown split at its headings into editable sections.
  List<_Section> _sections(String markdown) {
    final out = <_Section>[];
    var heading = '';
    var level = 2;
    final body = StringBuffer();
    void flush() {
      final text = body.toString().trim();
      if (heading.isNotEmpty || text.isNotEmpty) out.add(_Section(heading, text, level));
      body.clear();
    }

    for (final line in const LineSplitter().convert(markdown)) {
      final m = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (m != null) {
        flush();
        level = m.group(1)!.length;
        heading = m.group(2)!.trim();
      } else {
        body.writeln(line);
      }
    }
    flush();
    return out;
  }

  String _markdown(List<_Section> sections) => sections
      .map((s) => [if (s.heading.isNotEmpty) '${'#' * s.level} ${s.heading}', if (s.body.isNotEmpty) s.body].join('\n\n'))
      .join('\n\n');

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  void _addFiles(List<_PickedExample> files) {
    for (final f in files) {
      final lower = f.name.toLowerCase();
      if (!(lower.endsWith('.docx') || lower.endsWith('.pdf'))) {
        ToastService.show(context, type: ToastType.error, message: '${f.name}: only Word (.docx) or PDF reports can be used.');
        continue;
      }
      if (_picked.any((p) => p.name == f.name)) continue;
      _picked.add(f);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['docx', 'pdf'],
      withData: true,
    );
    if (result == null) return;
    setState(() => _addFiles([for (final f in result.files) if (f.bytes != null) _PickedExample(f.name, f.bytes!)]));
  }

  int get _exampleCount => _picked.length + (_detail?.template.examples.length ?? 0);

  Future<void> _build() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ToastService.show(context, type: ToastType.error, message: 'Give the template a name.');
      return;
    }
    if (_exampleCount == 0) {
      ToastService.show(context, type: ToastType.error, message: 'Add at least one example report.');
      return;
    }
    setState(() => _starting = true);
    try {
      final id = _id ?? (await ReportProfilerApi.createTemplate(name)).id;
      for (final f in _picked) {
        await ReportProfilerApi.uploadExample(id, name: f.name, bytes: f.bytes);
      }
      await ReportProfilerApi.startProfile(id);
      if (!mounted) return;
      _picked.clear();
      if (widget.templateId == id) {
        _phaseKey = 'starting';
        await _load();
      } else {
        context.go('/templates/reports/profiler/$id');
      }
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _removeSaved(ProfilerExample example) async {
    final id = _id;
    if (id == null) return;
    try {
      await ReportProfilerApi.deleteExample(id, example.pathname);
      await _load();
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------------------

  Future<void> _confirmStop() async {
    final jobId = _detail?.template.jobId ?? _detail?.job?.jobId;
    if (jobId == null) return;
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Stop building',
        description: 'Stop Span now? You can build the template again later.',
        confirmLabel: 'Stop',
        cancelLabel: 'Keep going',
        confirmColor: Theme.of(context).colorScheme.error,
        onConfirm: () async {
          setState(() => _cancelling = true);
          try {
            await ReportProfilerApi.cancelJob(jobId);
            await _load();
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
  // Ready
  // ---------------------------------------------------------------------------

  void _editSection(String file, int index, String text, {bool heading = false}) {
    final sections = _texts[file];
    if (sections == null || index >= sections.length) return;
    if (heading) {
      sections[index].heading = text;
    } else {
      sections[index].body = text;
    }
    _saveTimers[file]?.cancel();
    setState(() => _unsaved.add(file));
    _saveTimers[file] = Timer(const Duration(milliseconds: 1500), () => _saveText(file));
  }

  Future<void> _saveText(String file) async {
    final id = _id;
    final sections = _texts[file];
    if (id == null || sections == null) return;
    setState(() {
      _unsaved.remove(file);
      _inFlight++;
      _saveFailed = false;
    });
    try {
      await ReportProfilerApi.saveText(id, file, _markdown(sections));
    } catch (e) {
      if (mounted) {
        setState(() => _saveFailed = true);
        ToastService.show(context, type: ToastType.error, message: _error(e));
      }
    } finally {
      if (mounted) setState(() => _inFlight--);
    }
  }

  Future<void> _downloadWord() async {
    final id = _id;
    if (id == null) return;
    try {
      final bytes = await ReportProfilerApi.getFileBytes(id, 'template.docx');
      final saved = await saveReportFile(bytes, fileName: '${_detail?.template.name ?? 'Report template'} - template', extension: 'docx');
      if (mounted) ToastService.show(context, type: ToastType.success, message: saved.isEmpty ? 'Downloaded.' : 'Saved to $saved');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    }
  }

  Future<void> _replaceWord() async {
    final id = _id;
    if (id == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['docx'], withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    try {
      DocxDocument.parse(file!.bytes!); // must be a readable Word file
      await ReportProfilerApi.saveFile(
        id,
        'template.docx',
        file.bytes!,
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      await _loadReady();
      if (mounted) ToastService.show(context, type: ToastType.success, message: 'Template replaced.');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    }
  }

  Future<void> _confirmRebuild() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Rebuild with Span',
        description: 'Span builds this template again from its example reports. Your edits to the instructions and style guide are replaced.',
        confirmLabel: 'Rebuild',
        cancelLabel: 'Cancel',
        onConfirm: () async {
          final id = _id;
          if (id == null) return;
          setState(() => _rebuilding = true);
          try {
            await ReportProfilerApi.startProfile(id);
            _phaseKey = 'starting';
            _template = null;
            await _load();
          } catch (e) {
            if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
          } finally {
            if (mounted) setState(() => _rebuilding = false);
          }
        },
      ),
    );
  }

  /// Fields in page order, with a label and where the value comes from.
  List<({String token, String label, String source})> _fields() {
    final template = _template;
    if (template == null) return const [];
    final sources = _spec['field_sources'] is Map ? (_spec['field_sources'] as Map) : const {};
    final out = <({String token, String label, String source})>[];
    for (final token in template.tokens) {
      if (token.startsWith('{{BLOCK_') || token == '{{KEEP_WITH_NEXT}}' || RegExp(r'SIGN|SEAL|STAMP|INITIAL').hasMatch(token)) continue;
      final bare = token.replaceAll(RegExp(r'[{}]'), '');
      final source = sources[bare];
      out.add((token: token, label: humanizeField(token), source: _sourceLabel(source)));
    }
    return out;
  }

  String _sourceLabel(dynamic source) {
    final from = source is Map ? source['from']?.toString() : null;
    if (source is Map && source['derived'] != null) return 'Worked out';
    if (from == null || from.isEmpty || from == 'null') return 'Asked if missing';
    final head = from.split('.').first.toLowerCase();
    return switch (head) {
      'project' => 'Project',
      'inspection' || 'inspections' => 'Inspection',
      'report' => 'Report',
      'company' => 'Company',
      'photos' || 'photo' => 'Photos',
      'tools' || 'markups' || 'findings' => 'Markups',
      _ => from.contains('derived') ? 'Worked out' : 'Inspection',
    };
  }

  void _tapGroup(String name) {
    final words = name.toLowerCase().split('_').where((w) => w.length > 2).toList();
    String? match;
    final sections = _texts['instructions.md'] ?? const [];
    for (final s in sections) {
      final h = s.heading.toLowerCase();
      if (words.any(h.contains)) {
        match = s.heading;
        break;
      }
    }
    setState(() {
      _tab = 'instructions';
      _highlightGroup = name;
      _highlightSection = match;
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _title => widget.templateId == null ? 'New Report Template' : (_detail?.template.name ?? 'Report template');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Templates', onTap: () => context.go('/templates/reports')),
            BreadcrumbItem(label: 'Report Templates', onTap: () => context.go('/templates/reports')),
            BreadcrumbItem(label: widget.templateId == null ? 'New' : (_detail?.template.name ?? '…')),
          ],
        ),
        const SizedBox(height: 12),
        _header(),
        const SizedBox(height: 16),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _header() {
    final ready = _status == 'ready' && _template != null;
    return Row(
      children: [
        IconButton(
          tooltip: 'Back to report templates',
          icon: const Icon(Icons.chevron_left_rounded, size: 26),
          onPressed: () => context.go('/templates/reports'),
        ),
        const SizedBox(width: 4),
        Flexible(child: Text(_title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _ink))),
        if (ready) ...[
          const SizedBox(width: 12),
          Icon(_saveFailed ? Icons.error_outline_rounded : (_isSaving ? Icons.sync_rounded : Icons.cloud_done_outlined), size: 16, color: _saveFailed ? const Color(0xFFE03131) : _muted),
          const SizedBox(width: 5),
          Text(_saveFailed ? "Couldn't save" : (_isSaving ? 'Saving…' : 'Saved'), style: TextStyle(fontSize: 13, color: _saveFailed ? const Color(0xFFE03131) : _muted)),
        ],
        const Spacer(),
        if (ready) ...[
          OutlinedButton(
            onPressed: _rebuilding ? null : _confirmRebuild,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _line),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Rebuild with Span', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _downloadWord,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download Word'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _body() {
    if (widget.templateId != null && _detail == null) {
      if (_loadError != null) return _message('Could not load this template', _loadError!, ('Retry', _load));
      return const Center(child: CircularProgressIndicator(color: _ink));
    }
    if (_isBuilding) {
      final count = _detail?.template.examples.length ?? 0;
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SpanProgressCard(
            title: 'Span is building your template',
            subtitle: 'From $count example report${count == 1 ? '' : 's'}. Usually 10 to 15 minutes.',
            steps: templateSteps,
            current: templateStepFor(_phaseKey),
            progress: templateProgressFor(_phaseKey),
            leaveNote: "You can leave this page. Span keeps building, and the template shows up in Report Templates when it's done.",
            backLabel: 'Back to Templates',
            onBack: () => context.go('/templates/reports'),
            onCancel: _confirmStop,
            cancelling: _cancelling,
          ),
        ),
      );
    }
    if (_isSetup) return _setup();
    if (_readyError != null) return _message("This template can't be shown here", _readyError!, ('Download Word', _downloadWord));
    if (_template == null) return const Center(child: CircularProgressIndicator(color: _ink));
    return _ready();
  }

  Widget _setup() {
    final saved = _detail?.template.examples ?? const <ProfilerExample>[];
    final failed = _status == 'failed';
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failed) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFF5F5), border: Border.all(color: const Color(0xFFFFC9C9)), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    "Span couldn't build this template${_detail?.template.error == null ? '.' : ': ${_detail!.template.error}'} Check the examples and build again.",
                    style: const TextStyle(color: Color(0xFFC92A2A), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('TEMPLATE NAME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF495057), letterSpacing: 0.3)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('template-name'),
                controller: _name,
                enabled: widget.templateId == null,
                decoration: InputDecoration(
                  hintText: 'Template name',
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _ink)),
                ),
              ),
              const SizedBox(height: 24),
              const Text('EXAMPLE REPORTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF495057), letterSpacing: 0.3)),
              const SizedBox(height: 6),
              const Text('Add 2 to 5 finished reports, Word or PDF. Span copies their layout, sections, and writing style.',
                  style: TextStyle(fontSize: 13, color: _muted)),
              const SizedBox(height: 10),
              InkWell(
                onTap: _browse,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  decoration: BoxDecoration(
                    color: _dragging ? const Color(0xFFF1F3F5) : Colors.white,
                    border: Border.all(color: _dragging ? _ink : const Color(0xFFCED4DA), width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.upload_rounded, size: 22, color: _ink),
                      SizedBox(height: 8),
                      Text('Drag example reports here, or browse', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _ink)),
                      SizedBox(height: 2),
                      Text('.docx or .pdf', style: TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
              ),
              if (saved.isNotEmpty || _picked.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      for (final e in saved) _exampleRow(e.name, '${_size(e.size)} · uploaded', () => _removeSaved(e)),
                      for (final p in _picked)
                        _exampleRow(p.name, '${p.name.toLowerCase().endsWith('.pdf') ? 'PDF' : 'Word'} · ${_size(p.bytes.length)}',
                            () => setState(() => _picked.remove(p))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => context.go('/templates/reports'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const ValueKey('build-template'),
                    onPressed: _starting ? null : _build,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(_starting ? 'Starting…' : 'Build template with Span'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _size(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  Widget _exampleRow(String name, String detail, VoidCallback onRemove) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5)))),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 20, color: _ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _ink)),
                  Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ),
            TextButton(onPressed: onRemove, style: TextButton.styleFrom(foregroundColor: _muted), child: const Text('Remove')),
          ],
        ),
      );

  Widget _ready() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 18, color: _muted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Blue chips are fields Span fills from each inspection. To change the layout or wording, download the Word file, edit it in Word, and upload it here.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF495057)),
                ),
              ),
              TextButton.icon(
                onPressed: _replaceWord,
                icon: const Icon(Icons.upload_rounded, size: 16),
                label: const Text('Upload edited Word file'),
                style: TextButton.styleFrom(foregroundColor: _ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFE9ECEF), borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                    child: ReportPageView(
                      document: _template!,
                      fill: const {},
                      mode: ReportPageMode.template,
                      highlightedToken: _highlightToken,
                      highlightedGroup: _highlightGroup,
                      onTapGroup: _tapGroup,
                      onTapToken: (token) => setState(() {
                        _tab = 'fields';
                        _highlightToken = token;
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _sidebar(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebar() {
    return Container(
      width: 340,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE9ECEF)))),
            child: Row(
              children: [
                for (final (key, label) in const [('fields', 'Fields'), ('instructions', 'Instructions'), ('style', 'Style guide')]) ...[
                  InkWell(
                    key: ValueKey('tab-$key'),
                    onTap: () => setState(() => _tab = key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _tab == key ? _ink : Colors.transparent, width: 2)),
                      ),
                      child: Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: _tab == key ? FontWeight.w600 : FontWeight.w500, color: _tab == key ? _ink : _muted)),
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch (_tab) {
              'fields' => _fieldsTab(),
              'instructions' => _textTab('instructions.md', 'How Span fills and words each section. Selecting a block on the page jumps here.'),
              _ => _textTab('style-guide.md', 'How reports from this template are written: tone, wording and formats.'),
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldsTab() {
    final fields = _fields();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Fields are filled from the inspection when Span writes a report. Select one to see where it is on the page.',
            style: TextStyle(fontSize: 13, color: Color(0xFF495057), height: 1.4)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE9ECEF)), borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              for (final f in fields)
                InkWell(
                  onTap: () => setState(() => _highlightToken = _highlightToken == f.token ? null : f.token),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: _highlightToken == f.token ? const Color(0xFFF5FAFF) : null,
                      border: const Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _highlightToken == f.token ? reportSelectionBlue : const Color(0xFFE7F5FF),
                            border: Border.all(color: _highlightToken == f.token ? reportSelectionBlue : const Color(0xFFA5D8FF)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(f.label,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _highlightToken == f.token ? Colors.white : reportSelectionBlue)),
                        ),
                        const Spacer(),
                        Text(f.source, style: const TextStyle(fontSize: 12, color: _muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _textTab(String file, String help) {
    final sections = _texts[file] ?? const <_Section>[];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(help, style: const TextStyle(fontSize: 13, color: Color(0xFF495057), height: 1.4)),
        const SizedBox(height: 14),
        if (sections.isEmpty) const Text('Nothing here yet.', style: TextStyle(fontSize: 13, color: _muted)),
        for (var i = 0; i < sections.length; i++) ...[
          Container(
            key: ValueKey('$file-$i'),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: file == 'instructions.md' && _highlightSection != null && sections[i].heading == _highlightSection ? reportSelectionBlue : const Color(0xFFE9ECEF),
                width: file == 'instructions.md' && sections[i].heading == _highlightSection ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sections[i].heading.isNotEmpty)
                  Text(sections[i].heading, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                if (sections[i].body.isNotEmpty || sections[i].heading.isEmpty) ...[
                const SizedBox(height: 6),
                TextFormField(
                  key: ValueKey('$file-body-$i-${sections[i].heading}'),
                  initialValue: sections[i].body,
                  minLines: 2,
                  maxLines: null,
                  onChanged: (text) => _editSection(file, i, text),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF495057), height: 1.45),
                  decoration: const InputDecoration.collapsed(hintText: 'Write instructions'),
                ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _message(String title, String body, (String, VoidCallback)? action) {
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
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111111)),
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
