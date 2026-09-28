import 'package:flutter/material.dart';

/// Pill for a Report Profiler template's profile status. Same shape and
/// palette as the Word-profile badge on the Reports list.
class ProfilerStatusBadge extends StatelessWidget {
  final String status;

  const ProfilerStatusBadge({super.key, required this.status});

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
      case 'queued':
      case 'running':
        return (color: Colors.blue.shade700, label: 'Profiling…');
      default:
        return (color: Colors.grey.shade700, label: 'Draft');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        style.label,
        style: TextStyle(color: style.color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
