import 'package:flutter/material.dart';
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
                        onRowTap: (item) => {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReportTemplateDetailsScreen(
                                templateId: item.id,
                              ),
                            ),
                          )
                        },
                        columns: [
                          TableColumn(
                            title: "Report Name",
                            flex: 3,
                            minWidth: 250,
                            sortable: true,
                            sortValue: (r) => r.name,
                            builder: (r) => Row(
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
                                  child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
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
              onPressed: () => _showAddReport(context),
            )
          else ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Create Report",
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              style: IconButton.styleFrom(backgroundColor: theme.colorScheme.primaryContainer),
              onPressed: () => _showAddReport(context),
            )
          ],
        ],
      )
    );
  }
}