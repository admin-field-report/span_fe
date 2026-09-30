import 'package:flutter/material.dart';

import '../report_generation_api.dart';
import 'generation_badges.dart';

/// Quality check of a generated report: verdict, each check with pass/fail,
/// what Span fixed during QA, the visual review against the company's
/// example, and anything still open for a person to look at.
class ReportQaPanel extends StatelessWidget {
  final ReportQa qa;

  /// Narrow layout for the details side sheet (check details under the label).
  final bool compact;

  const ReportQaPanel({super.key, required this.qa, this.compact = false});

  static String verdictText(String? result) {
    switch ((result ?? '').toUpperCase()) {
      case 'PASS':
        return 'Every check passed. The report matches your template and your example report.';
      case 'PASS WITH NOTES':
        return 'All checks passed. Span left a few notes for you to review below.';
      case 'FAIL':
        return 'Some checks failed. Review the items below before sending this report.';
      default:
        return 'Span did not record a quality check for this report.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final passed = qa.checks.where((c) => c.passed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QaBadge(result: qa.result, large: true),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                verdictText(qa.result),
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (qa.checks.isNotEmpty) ...[
          _heading(theme, 'Checks', '$passed of ${qa.checks.length} passed'),
          const SizedBox(height: 10),
          _box(
            theme,
            Column(
              children: [
                for (var i = 0; i < qa.checks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  _checkRow(theme, qa.checks[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (qa.fixed.isNotEmpty) ...[
          _heading(theme, 'Fixed during QA', '${qa.fixed.length} fix${qa.fixed.length == 1 ? '' : 'es'}'),
          const SizedBox(height: 10),
          _bulletBox(theme, qa.fixed, Icons.build_circle_outlined, Colors.green.shade600),
          const SizedBox(height: 24),
        ],
        if (qa.visualReview.isNotEmpty) ...[
          _heading(theme, 'Visual check against your example', 'page by page'),
          const SizedBox(height: 10),
          _bulletBox(theme, qa.visualReview, Icons.compare_outlined, colorScheme.primary),
          const SizedBox(height: 24),
        ],
        if (qa.open.isNotEmpty) ...[
          _heading(theme, 'Worth a look', 'not errors, but review before sending'),
          const SizedBox(height: 10),
          _bulletBox(theme, qa.open, Icons.visibility_outlined, Colors.orange.shade800),
        ],
      ],
    );
  }

  Widget _heading(ThemeData theme, String title, String trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text(trailing, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _box(ThemeData theme, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _checkRow(ThemeData theme, QaCheck check) {
    final colorScheme = theme.colorScheme;
    final Color color;
    final IconData icon;
    if (!check.passed) {
      color = Colors.red.shade600;
      icon = Icons.cancel_rounded;
    } else if (check.hasNotes) {
      color = Colors.teal.shade500;
      icon = Icons.error_outline_rounded;
    } else {
      color = Colors.green.shade600;
      icon = Icons.check_circle_rounded;
    }
    final details = check.details.toLowerCase() == 'none' ? '' : check.details;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(check.label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Text(check.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              details.isEmpty ? (check.passed ? 'No issues found' : 'Failed') : details,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletBox(ThemeData theme, List<String> items, IconData icon, Color color) {
    return _box(
      theme,
      Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(child: Text(items[i], style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
