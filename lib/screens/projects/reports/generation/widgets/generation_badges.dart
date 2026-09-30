import 'package:flutter/material.dart';

/// Pill shared by the generation badges (same shape and palette as the
/// Report Profiler status badge).
class _Pill extends StatelessWidget {
  final Color color;
  final String label;
  final IconData? icon;
  final bool large;

  const _Pill({required this.color, required this.label, this.icon, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: large ? 14 : 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(color: color, fontSize: large ? 12 : 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// QA verdict of a generated report: PASS / PASS WITH NOTES / FAIL.
class QaBadge extends StatelessWidget {
  final String? result;
  final bool large;

  const QaBadge({super.key, required this.result, this.large = false});

  static ({Color color, String label, IconData icon}) styleFor(String? result) {
    switch ((result ?? '').toUpperCase()) {
      case 'PASS':
        return (color: Colors.green.shade700, label: 'QA passed', icon: Icons.verified_outlined);
      case 'PASS WITH NOTES':
        return (color: Colors.teal.shade600, label: 'QA passed with notes', icon: Icons.fact_check_outlined);
      case 'FAIL':
        return (color: Colors.red.shade700, label: 'QA failed', icon: Icons.gpp_bad_outlined);
      default:
        return (color: Colors.grey.shade700, label: 'QA not run', icon: Icons.help_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(result);
    return _Pill(color: style.color, label: style.label, icon: style.icon, large: large);
  }
}

/// Status of a report run (Writing… / Ready / Failed / Cancelled).
class ReportRunStatusBadge extends StatelessWidget {
  final String status;

  const ReportRunStatusBadge({super.key, required this.status});

  static ({Color color, String label}) styleFor(String status) {
    switch (status.toLowerCase()) {
      case 'ready':
        return (color: Colors.green.shade700, label: 'Ready');
      case 'failed':
        return (color: Colors.red.shade700, label: 'Failed');
      case 'needs_clarification':
        return (color: Colors.orange.shade800, label: 'Needs answers');
      case 'cancelled':
        return (color: Colors.grey.shade700, label: 'Cancelled');
      default:
        return (color: Colors.blue.shade700, label: 'Writing…');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(status);
    return _Pill(color: style.color, label: style.label);
  }
}
