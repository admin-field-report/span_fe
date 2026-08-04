import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../widgets/card/card.dart';
import '../../../widgets/table/table.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/search_field/search_field.dart';
import '../../../utils/app_responsive.dart';
import './controllers/report_controller.dart';
import './widgets/add_report_form.dart';
import './report_templete_details_screen.dart';
import '../../services/toast_service.dart';
import '../../widgets/confirmation/confirmation_remove.dart';

/// Word-profile statuses that mean "this template's Word flow has started" —
/// rows in any of these states open [WordProfileTemplateScreen] instead of
/// the plain HTML-skill details screen, since the Word job status panel is
/// the more useful place to land while a profile build is in progress.
const Set<String> _wordProfileActiveStatuses = {
  'queued',
  'running',
  'needs_clarification',
  'ready',
  'failed',
  'cancelled',
};

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    reportController.getAllReports();
  }

  List<ReportTemplate> _getFilteredReports() {
    return reportController.reports.where((r) {
      return r.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _showAddReport(BuildContext context) {
    final bool isDesktop = AppResponsive.isDesktopScreen(context);

    if (isDesktop) {
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => const Center(
          child: Material(
            color: Colors.transparent,
            child: AddReportForm(isDesktop: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => const AddReportForm(isDesktop: false),
      );
    }
  }

  /// "Create Report" now offers two starting points: the Eve Word-profile
  /// flow (build a profile from example `.docx`/`.pdf` reports) or the
  /// existing PDF/skill-example flow ([AddReportForm]). Shown as a small
  /// centered dialog on both desktop and mobile since it's just two choices.
  void _showCreateReportChooser(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Report Template',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose how Span should learn this template\'s format.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _createOptionTile(
                  theme: theme,
                  icon: Icons.description_outlined,
                  title: 'Create from Word examples',
                  subtitle: 'Eve learns a reusable .docx profile from sample reports.',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.go('/templates/reports/word-profile');
                  },
                ),
                const SizedBox(height: 12),
                _createOptionTile(
                  theme: theme,
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Create from PDF/skill examples',
                  subtitle: 'Existing flow: upload examples and generate an AI skill.',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _showAddReport(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createOptionTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// Small pill showing the Eve Word-profile status next to a template's
  /// name. `null`/`'none'` renders nothing since most templates never
  /// touch the Word flow at all.
  Widget? _profileStatusBadge(ReportTemplate report) {
    final status = (report.profileStatus ?? 'none').toLowerCase();
    if (status.isEmpty || status == 'none') return null;

    late final Color color;
    late final String label;
    switch (status) {
      case 'ready':
        color = Colors.green.shade700;
        label = 'Word ready';
        break;
      case 'failed':
        color = Colors.red.shade700;
        label = 'Word failed';
        break;
      case 'needs_clarification':
        color = Colors.orange.shade800;
        label = 'Needs answers';
        break;
      case 'cancelled':
        color = Colors.grey.shade700;
        label = 'Word cancelled';
        break;
      case 'queued':
      case 'running':
        color = Colors.blue.shade700;
        label = 'Word building…';
        break;
      default:
        color = Colors.grey.shade700;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Rows whose Word profile has ever been started land on the Word job
  /// status screen (resuming with whatever we already know); everything
  /// else keeps opening the plain HTML-skill details screen.
  void _onRowTap(BuildContext context, ReportTemplate report) {
    final status = (report.profileStatus ?? 'none').toLowerCase();
    if (_wordProfileActiveStatuses.contains(status)) {
      context.go(
        Uri(
          path: '/templates/reports/word-profile/${report.id}',
          queryParameters: {
            'title': report.name,
            'status': status,
            if (report.profileJobId != null && report.profileJobId!.isNotEmpty)
              'jobId': report.profileJobId!,
          },
        ).toString(),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportTemplateDetailsScreen(
          templateId: report.id,
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(ReportTemplate report) async {
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Delete Report Template",
        description: "Are you sure you want to delete '${report.name}'?",
        confirmLabel: "Delete",
        cancelLabel: "Cancel",
        confirmColor: theme.colorScheme.error,
        onConfirm: () async {
          try {
            await reportController.deleteReport(report.id);
            if (mounted) {
              ToastService.show(
                context, 
                type: ToastType.success, 
                message: "Report template deleted successfully."
              );
            }
          } catch (e) {
            if (mounted) {
              ToastService.show(
                context, 
                type: ToastType.error, 
                message: e.toString().replaceAll("Exception: ", "")
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: reportController,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text("Reports", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    _buildTopToolbar(theme),
                    
                    Expanded(
                      child: CommonTable<ReportTemplate>(
                        isLoading: reportController.isLoading,
                        data: _getFilteredReports(),
                        showCheckboxes: false,
                        onRowTap: (item) => _onRowTap(context, item),
                        columns: [
                          TableColumn(
                            title: "Report Name",
                            flex: 3,
                            minWidth: 250,
                            sortable: true,
                            sortValue: (r) => r.name,
                            builder: (r) {
                              final badge = _profileStatusBadge(r);
                              return Row(
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.analytics_outlined, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                  ),
                                  if (badge != null) ...[
                                    const SizedBox(width: 8),
                                    badge,
                                  ],
                                ],
                              );
                            },
                          ),
                          TableColumn(
                            title: "Created at",
                            flex: 2,
                            minWidth: 150,
                            sortable: true,
                            sortValue: (r) => r.createDate,
                            builder: (r) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(DateFormat('dd MMM yyyy').format(r.createDate), style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text(DateFormat('hh:mm a').format(r.createDate), style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                              ],
                            ),
                          ),
                          // 🚀 NEW: Action Column with stickyRight
                          // TableColumn(
                          //   title: "Action",
                          //   width: 80,
                          //   stickyRight: true, // Keeps it pinned to the right edge
                          //   align: Alignment.center,
                          //   builder: (r) => IconButton(
                          //     tooltip: "Delete Report",
                          //     icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                          //     onPressed: () {
                          //       _showDeleteConfirmation(r);
                          //     },
                          //   ),
                          // ),
                          TableColumn(
                            title: "Actions",
                            flex: 0,
                            minWidth: 100,
                            isStickyRight: true,
                            builder: (p) => IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  color: colorScheme.error,
                                  tooltip: "Delete Project",
                                  onPressed: () => _showDeleteConfirmation(p),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            )
          ],
        );
      },
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16), 
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              width: 350,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          if (isDesktop) const Spacer(),
          if (isDesktop) 
            Button(
              label: "Create Report",
              icon: Icons.add_rounded,
              onPressed: () => _showCreateReportChooser(context),
            )
          else ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Create Report",
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              style: IconButton.styleFrom(backgroundColor: theme.colorScheme.primaryContainer),
              onPressed: () => _showCreateReportChooser(context),
            )
          ],
        ],
      )
    );
  }
}