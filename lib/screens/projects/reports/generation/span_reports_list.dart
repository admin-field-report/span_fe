import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/widgets.dart';
import 'report_generation_api.dart';
import 'widgets/generation_badges.dart';

/// Project → Reports, for Span-generated reports: one row per report with
/// its status (Writing… / Ready / Failed) and date. Same table and toolbar as
/// the existing Reports tab.
class SpanReportsList extends StatefulWidget {
  final String projectId;
  final String? inspectionId;

  const SpanReportsList({super.key, required this.projectId, this.inspectionId});

  @override
  State<SpanReportsList> createState() => _SpanReportsListState();
}

class _SpanReportsListState extends State<SpanReportsList> {
  List<ReportRun> _runs = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final runs = await ReportGenerationApi.listRuns(inspectionId: widget.inspectionId, limit: 30);
      if (!mounted) return;
      setState(() {
        _runs = runs;
        _loading = false;
        _error = null;
      });
      // Keep "Writing…" rows fresh.
      _refreshTimer?.cancel();
      if (runs.any((r) => r.isRunning)) _refreshTimer = Timer(const Duration(seconds: 10), _load);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  List<ReportRun> get _filtered {
    final q = _query.toLowerCase();
    if (q.isEmpty) return _runs;
    return _runs
        .where((r) => '${r.templateName} ${r.inspectionName}'.toLowerCase().contains(q))
        .toList();
  }

  void _open(ReportRun run) => context.go('/projects/${widget.projectId}/reports/runs/${run.jobId}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Projects', onTap: () => context.go('/projects')),
            BreadcrumbItem(label: 'Project'),
            BreadcrumbItem(label: 'Reports'),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16),
                  child: Row(
                    children: [
                      SearchField(width: 350, onChanged: (value) => setState(() => _query = value)),
                      const Spacer(),
                      Tooltip(
                        message: 'Refresh Reports',
                        child: InkWell(
                          onTap: _loading ? null : _load,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.refresh_rounded, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.7)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Button(
                        label: 'Generate with Span',
                        icon: Icons.auto_awesome_rounded,
                        onPressed: () => context.go(
                          '/projects/${widget.projectId}/reports/generate'
                          '${widget.inspectionId == null ? '' : '?inspectionId=${widget.inspectionId}'}',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: colorScheme.error)),
                  ),
                Expanded(
                  child: CommonTable<ReportRun>(
                    isLoading: _loading && _runs.isEmpty,
                    data: data,
                    showCheckboxes: false,
                    onRowTap: (run) => _open(run),
                    columns: [
                      TableColumn(
                        title: 'Report',
                        flex: 4,
                        minWidth: 280,
                        builder: (run) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(run.templateName ?? 'Report',
                                overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(run.inspectionName ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      TableColumn(
                        title: 'Status',
                        flex: 2,
                        minWidth: 140,
                        builder: (run) => Align(
                          alignment: Alignment.centerLeft,
                          child: ReportRunStatusBadge(status: run.status),
                        ),
                      ),
                      TableColumn(
                        title: 'Created Date',
                        flex: 2,
                        minWidth: 130,
                        sortable: true,
                        sortValue: (run) => run.createdAt,
                        builder: (run) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(DateFormat('dd MMM yyyy').format(run.createdAt),
                                style: const TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(DateFormat('hh:mm a').format(run.createdAt),
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      TableColumn(
                        title: 'Actions',
                        flex: 0,
                        minWidth: 72,
                        isStickyRight: true,
                        builder: (run) => IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          color: colorScheme.primary,
                          tooltip: 'Open report',
                          onPressed: () => _open(run),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
