import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/button/button.dart';
import '../../controllers/report_profiler_api.dart';

/// One step of a profile run, in the order the agent usually reaches them.
class ProfilerPhase {
  final String key;
  final String label;

  /// Share of a typical run spent in this phase (sums to 1). Measured on
  /// real runs: reading the examples (incl. PDF analysis) dominates.
  final double share;

  const ProfilerPhase(this.key, this.label, this.share);
}

const List<ProfilerPhase> profilerPhases = [
  ProfilerPhase('reading', 'Reading examples', 0.50),
  ProfilerPhase('building', 'Building template', 0.17),
  ProfilerPhase('checking', 'Checking template visually', 0.13),
  ProfilerPhase('writing', 'Writing instructions and style guide', 0.16),
  ProfilerPhase('packaging', 'Packaging', 0.04),
];

int profilerPhaseIndex(String key) {
  final index = profilerPhases.indexWhere((phase) => phase.key == key);
  return index; // -1 for "starting"
}

/// Estimated minutes left, from the current phase and how long it has run.
double estimateMinutesLeft({
  required int phaseIndex,
  required Duration elapsed,
  required Duration timeInPhase,
  required int typicalMinutes,
}) {
  final typical = typicalMinutes.toDouble();
  if (phaseIndex < 0) {
    // Session still starting: the whole run is ahead.
    return math.max(typical - elapsed.inSeconds / 60, typical * 0.8);
  }
  final current = profilerPhases[phaseIndex].share * typical;
  final spent = timeInPhase.inSeconds / 60;
  // Never promise the current phase is done: keep at least a quarter of it.
  var left = math.max(current - spent, math.max(current * 0.25, 0.5));
  for (var i = phaseIndex + 1; i < profilerPhases.length; i++) {
    left += profilerPhases[i].share * typical;
  }
  return left;
}

/// Progress view for a running Report Profiler job: current step, elapsed
/// time, estimated time left, step list, and the agent's recent activity.
class ProfilerProgressPanel extends StatelessWidget {
  final String status;
  final String phaseKey;
  final Map<String, DateTime> phaseStartedAt;
  final DateTime startedAt;
  final DateTime now;
  final DateTime? lastEventAt;
  final int typicalMinutes;
  final int maxMinutes;
  final List<ProfilerActivity> activities;
  final int clarificationCount;
  final bool isCancelling;
  final VoidCallback onCancel;
  final VoidCallback onAnswer;

  const ProfilerProgressPanel({
    super.key,
    required this.status,
    required this.phaseKey,
    required this.phaseStartedAt,
    required this.startedAt,
    required this.now,
    required this.lastEventAt,
    required this.typicalMinutes,
    required this.maxMinutes,
    required this.activities,
    required this.clarificationCount,
    required this.isCancelling,
    required this.onCancel,
    required this.onAnswer,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final waiting = status == 'needs_clarification';

    final phaseIndex = profilerPhaseIndex(phaseKey);
    final elapsed = now.difference(startedAt).isNegative ? Duration.zero : now.difference(startedAt);
    final phaseStart = phaseIndex >= 0 ? (phaseStartedAt[phaseKey] ?? startedAt) : startedAt;
    final timeInPhase = now.difference(phaseStart).isNegative ? Duration.zero : now.difference(phaseStart);
    final minutesLeft = estimateMinutesLeft(
      phaseIndex: phaseIndex,
      elapsed: elapsed,
      timeInPhase: timeInPhase,
      typicalMinutes: typicalMinutes,
    );
    final elapsedMinutes = elapsed.inSeconds / 60;
    final progress = (elapsedMinutes / (elapsedMinutes + minutesLeft)).clamp(0.02, 0.98);
    final overdue = elapsedMinutes > typicalMinutes * 1.35;

    final String etaText;
    if (waiting) {
      etaText = 'Paused until you answer';
    } else if (minutesLeft < 1) {
      etaText = 'Less than a minute left';
    } else {
      etaText = 'About ${minutesLeft.ceil()} min left';
    }

    final quietFor = lastEventAt == null ? null : now.difference(lastEventAt!);
    final currentLabel = waiting
        ? 'Waiting for your answers'
        : (phaseIndex >= 0 ? profilerPhases[phaseIndex].label : 'Starting the agent');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Status card ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: waiting
                            ? null
                            : CircularProgressIndicator(color: colorScheme.primary, strokeWidth: 3),
                      ),
                      Icon(
                        waiting ? Icons.question_answer_outlined : Icons.auto_awesome_rounded,
                        color: waiting ? Colors.orange.shade800 : colorScheme.primary,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          waiting ? 'Span needs a few answers' : 'Span is building your template',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Button(
                    label: 'Cancel',
                    icon: Icons.close_rounded,
                    variant: ButtonVariant.outline,
                    color: colorScheme.error,
                    isLoading: isCancelling,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: isCancelling ? null : onCancel,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  _stat(theme, Icons.timer_outlined, 'Elapsed ${_formatDuration(elapsed)}'),
                  _stat(theme, Icons.hourglass_bottom_rounded, etaText),
                  _stat(theme, Icons.schedule_rounded, 'Usually 9–16 min'),
                ],
              ),
              if (overdue && !waiting) ...[
                const SizedBox(height: 12),
                _note(
                  theme,
                  Icons.info_outline_rounded,
                  'Taking longer than usual. Some runs take up to $maxMinutes minutes; '
                  'you can leave this page and come back.',
                ),
              ] else if (!waiting && quietFor != null && quietFor.inMinutes >= 3) ...[
                const SizedBox(height: 12),
                _note(
                  theme,
                  Icons.info_outline_rounded,
                  'No new activity for ${quietFor.inMinutes} min. The agent may be working through a long step.',
                ),
              ],
              if (waiting) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade800.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.help_outline_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          clarificationCount > 0
                              ? 'Span has $clarificationCount question${clarificationCount == 1 ? '' : 's'} about your reports before it can finish the template.'
                              : 'Span is waiting for answers. Questions will appear here shortly.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Button(
                        label: 'Answer questions',
                        icon: Icons.question_answer_outlined,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        onPressed: clarificationCount > 0 ? onAnswer : null,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // --- Steps ---
        _sectionTitle(theme, 'Steps', Icons.checklist_rounded),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: List.generate(profilerPhases.length, (i) {
              final phase = profilerPhases[i];
              final done = i < phaseIndex;
              final active = i == phaseIndex || (phaseIndex < 0 && i == 0);
              final startedAtPhase = phaseStartedAt[phase.key];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: done
                          ? Icon(Icons.check_circle_rounded, size: 22, color: Colors.green.shade600)
                          : active && !waiting
                              ? Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.primary),
                                )
                              : Icon(
                                  active ? Icons.pause_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
                                  size: 22,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        phase.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: done || active ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (startedAtPhase != null && (done || active))
                      Text(
                        DateFormat('h:mm a').format(startedAtPhase),
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),

        // --- Recent activity ---
        _sectionTitle(theme, 'Recent activity', Icons.bolt_rounded),
        const SizedBox(height: 12),
        _buildActivity(theme),
        const SizedBox(height: 12),
        Text(
          'You can leave this page. The profile keeps building, and you can reopen it from Span Report Profiler.',
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildActivity(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(
            'Waiting for the agent to start…',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final recent = activities.length > 8 ? activities.sublist(activities.length - 8) : activities;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            _activityRow(theme, recent[i], isLatest: i == recent.length - 1),
          ],
        ],
      ),
    );
  }

  Widget _activityRow(ThemeData theme, ProfilerActivity activity, {required bool isLatest}) {
    final colorScheme = theme.colorScheme;
    final isError = activity.kind == 'error' || activity.failed;
    final IconData icon;
    switch (activity.kind) {
      case 'message':
        icon = Icons.chat_bubble_outline_rounded;
        break;
      case 'error':
        icon = Icons.error_outline_rounded;
        break;
      case 'status':
        icon = Icons.info_outline_rounded;
        break;
      default:
        icon = Icons.build_outlined;
    }
    final color = isError ? colorScheme.error : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              activity.failed ? '${activity.text} (retrying)' : activity.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isError ? colorScheme.error : colorScheme.onSurface,
                fontWeight: isLatest ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (activity.at != null) ...[
            const SizedBox(width: 12),
            Text(
              DateFormat('h:mm:ss a').format(activity.at!),
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _note(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
