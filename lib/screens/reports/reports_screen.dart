import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// import 'package:go_router/go_router.dart'; // Add if you need to route on row tap later
import '../../../widgets/card/card.dart';
import '../../../widgets/table/table.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/search_field/search_field.dart';
import '../../../utils/app_responsive.dart';
import './controllers/report_controller.dart';
import './widgets/add_report_form.dart';

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
        builder: (context) => Center(
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