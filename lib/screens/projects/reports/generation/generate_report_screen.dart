import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../services/toast_service.dart';
import '../../../../widgets/breadcrumb/breadcrumb.dart';
import '../../../../widgets/button/button.dart';
import '../../../../widgets/form_components/select_field.dart';
import '../../../reports/controllers/report_profiler_api.dart';
import '../../../reports/widgets/profiler/profiler_status_badge.dart';
import 'report_generation_api.dart';
import 'widgets/generation_badges.dart';

class _InspectionItem implements SelectableItem<String> {
  final GenerationInspection inspection;

  _InspectionItem(this.inspection);

  @override
  String get id => inspection.id;

  @override
  String get name => inspection.name;
}

/// Generate a report with Span from one of the project's inspections: pick
/// the inspection and a report template, then start. Opens the run's
/// progress page, and the finished report opens ready to edit.
class GenerateReportScreen extends StatefulWidget {
  final String projectId;
  final String? inspectionId;
  final String? templateId;

  const GenerateReportScreen({super.key, required this.projectId, this.inspectionId, this.templateId});

  @override
  State<GenerateReportScreen> createState() => _GenerateReportScreenState();
}

class _GenerateReportScreenState extends State<GenerateReportScreen> {
  static const int _collapsedTemplates = 5;

  bool _loading = true;
  String? _loadError;
  List<GenerationInspection> _inspections = [];
  List<ProfilerTemplate> _templates = [];
  List<ReportRun> _recentRuns = [];
  String? _inspectionId;
  String? _templateId;
  bool _showAllTemplates = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _inspectionId = widget.inspectionId;
    _templateId = widget.templateId;
    _load();
  }

  String _error(Object e) => e.toString().replaceAll('Exception: ', '');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ReportGenerationApi.listInspections(),
        ReportGenerationApi.listReadyTemplates(),
      ]);
      if (!mounted) return;
      final inspections = results[0] as List<GenerationInspection>;
      final templates = (results[1] as List<ProfilerTemplate>).where((t) => t.status == 'ready').toList();
      setState(() {
        _inspections = inspections;
        _templates = templates;
        _inspectionId ??= inspections.isEmpty ? null : inspections.first.id;
        if (_templateId != null && !templates.any((t) => t.id == _templateId)) _templateId = null;
        _templateId ??= templates.isEmpty ? null : templates.first.id;
        // Keep the chosen template visible even when it sits past the fold.
        final index = templates.indexWhere((t) => t.id == _templateId);
        if (index >= _collapsedTemplates) {
          final chosen = _templates.removeAt(index);
          _templates.insert(0, chosen);
        }
        _loading = false;
      });
      _loadRecentRuns();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _error(e);
      });
    }
  }

  Future<void> _loadRecentRuns() async {
    final id = _inspectionId;
    if (id == null) return;
    try {
      final runs = await ReportGenerationApi.listRuns(inspectionId: id, limit: 3);
      if (mounted && id == _inspectionId) setState(() => _recentRuns = runs);
    } catch (_) {
      // Optional context only.
    }
  }

  GenerationInspection? get _inspection {
    for (final inspection in _inspections) {
      if (inspection.id == _inspectionId) return inspection;
    }
    return null;
  }

  ProfilerTemplate? get _template {
    for (final template in _templates) {
      if (template.id == _templateId) return template;
    }
    return null;
  }

  Future<void> _start() async {
    final inspection = _inspection;
    final template = _template;
    if (inspection == null || template == null) return;
    setState(() => _starting = true);
    try {
      final run = await ReportGenerationApi.startRun(templateId: template.id, inspectionId: inspection.id);
      if (!mounted) return;
      context.go('/projects/${widget.projectId}/reports/runs/${run.jobId}');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: _error(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = _inspection?.projectName ?? 'Project';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Projects', onTap: () => context.go('/projects')),
            BreadcrumbItem(label: projectName, onTap: () => context.go('/projects/${widget.projectId}/reports')),
            BreadcrumbItem(label: 'Reports', onTap: () => context.go('/projects/${widget.projectId}/reports')),
            BreadcrumbItem(label: 'Generate report'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.go('/projects/${widget.projectId}/reports'),
            ),
            const SizedBox(width: 12),
            Text('Generate report', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (!ReportGenerationApi.isConfigured) {
      return Center(
        child: Text(
          'Report generation is not configured: set EVE_UI_BASE_URL (and EVE_UI_KEY), then reload.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_loading) return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            Button(label: 'Retry', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 1100;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(theme, '1', 'Inspection'),
        const SizedBox(height: 10),
        FormControlSelect<String>(
          value: _inspectionId,
          items: _inspections.map(_InspectionItem.new).toList(),
          hintText: 'Choose an inspection',
          emptyText: 'This project has no inspections yet',
          prefixIcon: Icons.fact_check_outlined,
          onChanged: (id) {
            setState(() {
              _inspectionId = id;
              _recentRuns = [];
            });
            _loadRecentRuns();
          },
        ),
        const SizedBox(height: 12),
        if (_inspection != null) _inspectionCard(theme, _inspection!),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: _sectionTitle(theme, '2', 'Report template')),
            TextButton.icon(
              onPressed: () => context.go('/templates/reports/profiler'),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Manage templates'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'The report follows the template\'s layout and your company\'s writing style.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        ..._templateTiles(theme),
      ],
    );
    final right = _summaryCard(theme);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 4, bottom: 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 24),
                    SizedBox(width: 380, child: right),
                  ],
                )
              else ...[
                left,
                const SizedBox(height: 24),
                right,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String step, String title) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
          child: Text(step, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
        ),
        const SizedBox(width: 10),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _inspectionCard(ThemeData theme, GenerationInspection inspection) {
    final colorScheme = theme.colorScheme;
    DateTime? date;
    if (inspection.inspectionDate != null) date = DateTime.tryParse(inspection.inspectionDate!);
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 20,
        runSpacing: 6,
        children: [
          _meta(theme, Icons.inventory_2_outlined,
              '${plural(inspection.findings, 'finding')} · ${plural(inspection.photos, 'photo')}'),
          if (inspection.siteAddress != null) _meta(theme, Icons.place_outlined, inspection.siteAddress!),
          if (inspection.inspectorName != null) _meta(theme, Icons.person_outline_rounded, inspection.inspectorName!),
          if (date != null) _meta(theme, Icons.event_outlined, DateFormat('dd MMM yyyy').format(date)),
          if (inspection.findings == 0)
            Text(
              'No findings yet, so most of the report will be blank.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  List<Widget> _templateTiles(ThemeData theme) {
    if (_templates.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            'No report templates are ready yet. Build one from your example reports in Span Report Profiler.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ];
    }
    final shown = _showAllTemplates ? _templates : _templates.take(_collapsedTemplates).toList();
    return [
      for (final template in shown) ...[
        _templateTile(theme, template),
        const SizedBox(height: 8),
      ],
      if (_templates.length > _collapsedTemplates)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAllTemplates = !_showAllTemplates),
            child: Text(_showAllTemplates ? 'Show fewer' : 'Show all ${_templates.length} templates'),
          ),
        ),
    ];
  }

  Widget _templateTile(ThemeData theme, ProfilerTemplate template) {
    final colorScheme = theme.colorScheme;
    final selected = template.id == _templateId;
    final examples = template.examples.length;
    return InkWell(
      onTap: () => setState(() => _templateId = template.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.25) : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? colorScheme.primary : colorScheme.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
              child: Icon(Icons.description_rounded, color: colorScheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Learned from $examples example report${examples == 1 ? '' : 's'}'
                    '${template.builtAt != null ? ' · ${DateFormat('dd MMM yyyy').format(template.builtAt!)}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ProfilerStatusBadge(status: template.status),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final inspection = _inspection;
    final template = _template;
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your report', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              row(Icons.fact_check_outlined, 'Inspection', inspection?.name ?? 'Choose an inspection'),
              row(Icons.description_outlined, 'Template', template?.name ?? 'Choose a template'),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Usually 4–9 minutes. You can edit the report in the app when it\'s done.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Button(
                label: 'Generate with Span',
                icon: Icons.auto_awesome_rounded,
                isLoading: _starting,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                onPressed: _starting || inspection == null || template == null ? null : _start,
              ),
            ],
          ),
        ),
        if (_recentRuns.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Earlier reports from this inspection',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final run in _recentRuns)
                  InkWell(
                    onTap: () => context.go('/projects/${widget.projectId}/reports/runs/${run.jobId}'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(run.templateName ?? 'Report',
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                Text(DateFormat('dd MMM, h:mm a').format(run.createdAt),
                                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ReportRunStatusBadge(status: run.status),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
