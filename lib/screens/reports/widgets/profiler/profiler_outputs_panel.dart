import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:field_report_fe/utils/bytes_download_stub.dart'
    if (dart.library.html) 'package:field_report_fe/utils/bytes_download_web.dart';

import '../../../../services/toast_service.dart';
import '../../../../widgets/button/button.dart';
import '../../../../widgets/confirmation/confirmation_remove.dart';
import '../../../../widgets/form_components/text_area_field.dart';
import '../../../../widgets/tab/tab.dart';
import '../../controllers/report_profiler_api.dart';
import 'docx_preview_stub.dart' if (dart.library.html) 'docx_preview_web.dart';

const String _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Outputs of a finished profile: the Word template (preview, download,
/// replace) and the instructions / style guide (view + edit + save back to
/// the profile pack).
class ProfilerOutputsPanel extends StatefulWidget {
  final String templateId;
  final String templateName;
  final ProfilerPack pack;

  const ProfilerOutputsPanel({
    super.key,
    required this.templateId,
    required this.templateName,
    required this.pack,
  });

  @override
  State<ProfilerOutputsPanel> createState() => _ProfilerOutputsPanelState();
}

class _ProfilerOutputsPanelState extends State<ProfilerOutputsPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<({String label, String? path})> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      (label: 'Template', path: widget.pack.template),
      (label: 'Instructions', path: widget.pack.instructions),
      (label: 'Style guide', path: widget.pack.styleGuide),
      if (widget.pack.uncertaintyReport != null)
        (label: 'Judgment calls', path: widget.pack.uncertaintyReport),
    ];
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTabBar(
            controller: _tabController,
            tabs: _tabs.map((tab) => tab.label).toList(),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: IndexedStack(
              index: _tabController.index,
              sizing: StackFit.loose,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  // Only the visible tab takes part in layout/hit testing.
                  Visibility(
                    visible: i == _tabController.index,
                    maintainState: true,
                    child: i == 0
                        ? _TemplateTab(
                            templateId: widget.templateId,
                            templateName: widget.templateName,
                            pack: widget.pack,
                          )
                        : _MarkdownFileTab(
                            templateId: widget.templateId,
                            path: _tabs[i].path,
                            label: _tabs[i].label,
                            editable: _tabs[i].path != widget.pack.uncertaintyReport,
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Template tab
// -----------------------------------------------------------------------------

class _TemplateTab extends StatefulWidget {
  final String templateId;
  final String templateName;
  final ProfilerPack pack;

  const _TemplateTab({required this.templateId, required this.templateName, required this.pack});

  @override
  State<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends State<_TemplateTab> {
  Uint8List? _docx;
  String? _error;
  bool _loading = true;
  bool _replacing = false;
  bool _showReference = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.pack.template;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = 'This profile has no template.docx.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await ReportProfilerApi.getFileBytes(widget.templateId, path);
      if (!mounted) return;
      setState(() {
        _docx = bytes;
        _loading = false;
        _version++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  String get _downloadName {
    final safe = widget.templateName.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    return '${safe.isEmpty ? 'template' : safe} template.docx';
  }

  Future<void> _download() async {
    final bytes = _docx;
    if (bytes == null) return;
    try {
      await downloadBytesWeb(bytes, fileName: _downloadName, mimeType: _docxMime);
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _replace() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null || !mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Replace Template',
        description:
            "Replace this profile's template.docx with '${file.name}'? Report generation will use the new file. "
            'Keep its {{PLACEHOLDERS}} in line with the instructions.',
        confirmLabel: 'Replace',
        confirmColor: Theme.of(context).colorScheme.primary,
        onConfirm: () async {
          setState(() => _replacing = true);
          try {
            await ReportProfilerApi.saveFile(
              widget.templateId,
              widget.pack.template ?? 'template.docx',
              file.bytes!,
              contentType: _docxMime,
            );
            if (!mounted) return;
            ToastService.show(context, type: ToastType.success, message: 'Template replaced.');
            setState(() => _showReference = false);
            await _load();
          } catch (e) {
            if (mounted) {
              ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
            }
          } finally {
            if (mounted) setState(() => _replacing = false);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReference = widget.pack.referencePages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: 8,
              children: [
                Button(
                  label: 'Template',
                  icon: Icons.description_outlined,
                  variant: _showReference ? ButtonVariant.outline : ButtonVariant.filled,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: () => setState(() => _showReference = false),
                ),
                if (hasReference)
                  Button(
                    label: 'Source example',
                    icon: Icons.image_outlined,
                    variant: _showReference ? ButtonVariant.filled : ButtonVariant.outline,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: () => setState(() => _showReference = true),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                Button(
                  label: 'Replace .docx',
                  icon: Icons.upload_rounded,
                  variant: ButtonVariant.outline,
                  isLoading: _replacing,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: _replacing || _loading ? null : _replace,
                ),
                Button(
                  label: 'Download .docx',
                  icon: Icons.download_rounded,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onPressed: _docx == null ? null : _download,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _showReference
              ? 'Pages rendered from the example report the template was built from.'
              : 'Preview of the generated Word template. Layout in Word may differ slightly. '
                  'To change it, download, edit in Word, and replace.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Container(
          height: 760,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: _showReference ? _buildReferencePages(theme) : _buildPreview(theme),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    }
    if (_error != null || _docx == null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: _error ?? 'Template not available.',
        isError: true,
        onRetry: _load,
      );
    }
    return DocxPreviewView(key: ValueKey('docx-$_version'), bytes: _docx!);
  }

  Widget _buildReferencePages(ThemeData theme) {
    final pages = widget.pack.referencePages;
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: pages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 24),
      itemBuilder: (context, index) => _ReferencePage(
        templateId: widget.templateId,
        path: pages[index],
        label: 'Page ${index + 1}',
      ),
    );
  }
}

class _ReferencePage extends StatefulWidget {
  final String templateId;
  final String path;
  final String label;

  const _ReferencePage({required this.templateId, required this.path, required this.label});

  @override
  State<_ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends State<_ReferencePage> {
  late final Future<Uint8List> _bytes = ReportProfilerApi.getFileBytes(widget.templateId, widget.path);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(widget.label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load ${widget.label.toLowerCase()}',
                  style: TextStyle(color: theme.colorScheme.error));
            }
            if (!snapshot.hasData) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)],
                ),
                child: Image.memory(snapshot.data!, fit: BoxFit.contain),
              ),
            );
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Markdown file tab (instructions / style guide)
// -----------------------------------------------------------------------------

class _MarkdownFileTab extends StatefulWidget {
  final String templateId;
  final String? path;
  final String label;
  final bool editable;

  const _MarkdownFileTab({
    required this.templateId,
    required this.path,
    required this.label,
    required this.editable,
  });

  @override
  State<_MarkdownFileTab> createState() => _MarkdownFileTabState();
}

class _MarkdownFileTabState extends State<_MarkdownFileTab> {
  final TextEditingController _controller = TextEditingController();
  String _saved = '';
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  bool get _dirty => _controller.text != _saved;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await ReportProfilerApi.getFileText(widget.templateId, path);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _controller.text = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    final path = widget.path;
    if (path == null) return;
    setState(() => _saving = true);
    try {
      final text = _controller.text;
      await ReportProfilerApi.saveText(widget.templateId, path, text);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _editing = false;
      });
      ToastService.show(context, type: ToastType.success, message: '${widget.label} saved.');
    } catch (e) {
      if (mounted) {
        ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    setState(() {
      _controller.text = _saved;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.path == null) {
      return _MessageState(icon: Icons.folder_off_outlined, message: 'This profile has no ${widget.label.toLowerCase()} file.');
    }
    if (_loading) {
      return SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
    }
    if (_error != null) {
      return _MessageState(icon: Icons.error_outline, message: _error!, isError: true, onRetry: _load);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _editing
                    ? (_dirty ? 'Unsaved changes' : 'Editing ${widget.path}')
                    : (widget.editable
                        ? 'Span follows this file when it writes reports from this template.'
                        : 'What Span was least sure about while building the profile.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _editing && _dirty ? Colors.orange.shade800 : theme.colorScheme.onSurfaceVariant,
                  fontWeight: _editing && _dirty ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (widget.editable && !_editing)
              Button(
                label: 'Edit',
                icon: Icons.edit_outlined,
                variant: ButtonVariant.outline,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: () => setState(() => _editing = true),
              ),
            if (_editing) ...[
              Button(
                label: 'Discard',
                variant: ButtonVariant.outline,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: _saving ? null : _discard,
              ),
              const SizedBox(width: 8),
              Button(
                label: 'Save',
                icon: Icons.save_outlined,
                isLoading: _saving,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: _saving || !_dirty ? null : _save,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (_editing)
          DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
            child: FormControlTextArea(
              controller: _controller,
              hintText: 'Write ${widget.label.toLowerCase()} in Markdown',
              minLines: 20,
              maxLines: 40,
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: _saved.trim().isEmpty
                ? Text('This file is empty.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
                : MarkdownBody(
                    data: _saved,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      listBullet: TextStyle(color: theme.colorScheme.primary),
                      code: theme.textTheme.bodySmall?.copyWith(backgroundColor: Colors.transparent),
                      codeblockDecoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  const _MessageState({required this.icon, required this.message, this.isError = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: color)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              Button(label: 'Retry', icon: Icons.refresh, variant: ButtonVariant.outline, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
