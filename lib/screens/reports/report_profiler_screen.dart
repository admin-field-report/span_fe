import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../utils/app_responsive.dart';
import '../../widgets/breadcrumb/breadcrumb.dart';
import '../../widgets/button/button.dart';
import '../../widgets/card/card.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/table/table.dart';
import 'controllers/report_profiler_api.dart';
import 'widgets/profiler/profiler_status_badge.dart';

/// Templates → Reports → Report Profiler: the profiles Eve has built (or is
/// building) from example reports. Rows open [ReportProfilerDetailScreen].
class ReportProfilerScreen extends StatefulWidget {
  const ReportProfilerScreen({super.key});

  @override
  State<ReportProfilerScreen> createState() => _ReportProfilerScreenState();
}

class _ReportProfilerScreenState extends State<ReportProfilerScreen> {
  List<ProfilerTemplate> _templates = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!ReportProfilerApi.isConfigured) {
      setState(() {
        _loading = false;
        _error = 'Report Profiler is not configured. Set EVE_UI_BASE_URL (and EVE_UI_KEY), then reload.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final templates = await ReportProfilerApi.listTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
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

  List<ProfilerTemplate> get _filtered => _templates
      .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AppBreadcrumbs(
          items: [
            BreadcrumbItem(label: 'Reports', onTap: () => context.go('/templates/reports')),
            BreadcrumbItem(label: 'Span Report Profiler'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => context.go('/templates/reports'),
            ),
            const SizedBox(width: 12),
            Text('Span Report Profiler', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(
            'Span learns a report format from example reports and builds a Word template with writing instructions.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildToolbar(theme),
                if (_error != null)
                  Expanded(child: _buildError(theme))
                else
                  Expanded(
                    child: CommonTable<ProfilerTemplate>(
                      isLoading: _loading,
                      data: _filtered,
                      showCheckboxes: false,
                      onRowTap: (t) => context.go('/templates/reports/profiler/${t.id}'),
                      columns: [
                        TableColumn(
                          title: 'Template Name',
                          flex: 3,
                          minWidth: 260,
                          sortable: true,
                          sortValue: (t) => t.name,
                          builder: (t) => Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.auto_awesome_outlined, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(t.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              ProfilerStatusBadge(status: t.status),
                            ],
                          ),
                        ),
                        TableColumn(
                          title: 'Examples',
                          flex: 1,
                          minWidth: 110,
                          sortable: true,
                          sortValue: (t) => t.examples.length,
                          builder: (t) => Text(
                            '${t.examples.length} file${t.examples.length == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        TableColumn(
                          title: 'Created at',
                          flex: 2,
                          minWidth: 150,
                          sortable: true,
                          sortValue: (t) => t.createdAt,
                          builder: (t) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('dd MMM yyyy').format(t.createdAt),
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(DateFormat('hh:mm a').format(t.createdAt),
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                            ],
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

  Widget _buildToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              width: 350,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
          if (isDesktop) ...[
            const SizedBox(width: 8),
            Button(
              label: 'New Profile',
              icon: Icons.add_rounded,
              onPressed: () => context.go('/templates/reports/profiler/new'),
            ),
          ] else ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'New Profile',
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              style: IconButton.styleFrom(backgroundColor: theme.colorScheme.primaryContainer),
              onPressed: () => context.go('/templates/reports/profiler/new'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            Button(label: 'Retry', icon: Icons.refresh, variant: ButtonVariant.outline, onPressed: _load),
          ],
        ),
      ),
    );
  }
}
