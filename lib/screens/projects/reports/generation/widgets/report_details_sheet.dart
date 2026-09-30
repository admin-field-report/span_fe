import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../report_generation_api.dart';
import 'report_qa_panel.dart';

/// Opens the report's details (how it was made, Span's checks, generation
/// notes) as a side sheet. Kept off the main view on purpose: the report
/// itself is the page.
Future<void> showReportDetailsSheet(BuildContext context, ReportRunDetail detail) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close details',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: ReportDetailsSheet(detail: detail),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class ReportDetailsSheet extends StatelessWidget {
  final ReportRunDetail detail;

  const ReportDetailsSheet({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final run = detail.run;
    final stats = detail.stats;
    final width = MediaQuery.of(context).size.width;

    String? duration(int? seconds) => seconds == null ? null : '${seconds ~/ 60} min ${(seconds % 60).toString().padLeft(2, '0')} s';

    Widget row(String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500))),
          ],
        ),
      );
    }

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return Material(
      color: colorScheme.surface,
      elevation: 12,
      child: SizedBox(
        width: width < 560 ? width : 480,
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 18),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)))),
              child: Row(
                children: [
                  Expanded(child: Text('Details', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading('About this report'),
                    row('Template', run.templateName),
                    row('Inspection', run.inspectionName),
                    row('Generated', DateFormat('dd MMM yyyy, h:mm a').format(run.createdAt)),
                    row('Took', duration(stats.durationSeconds ?? run.durationSeconds)),
                    row('Pages', stats.pages?.toString()),
                    row('Photos', stats.photosPlaced == null ? null : '${stats.photosPlaced} placed'),
                    heading('Span\'s checks'),
                    ReportQaPanel(qa: detail.qa, compact: true),
                    if ((detail.notes ?? '').trim().isNotEmpty) ...[
                      heading('Generation notes'),
                      Text(
                        'What Span used and how it filled each field.',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      MarkdownBody(
                        data: detail.notes!,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                          listBullet: theme.textTheme.bodySmall,
                          h1: theme.textTheme.titleSmall,
                          h2: theme.textTheme.titleSmall,
                          h3: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
