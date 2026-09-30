import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../report_generation_api.dart';

/// One step of a report run, in the order Span usually reaches them.
class GenerationPhase {
  final String key;
  final String label;

  /// Share of a typical run spent in this step (sums to 1).
  final double share;

  const GenerationPhase(this.key, this.label, this.share);
}

const List<GenerationPhase> generationPhases = [
  GenerationPhase('reading', 'Reading template & inspection', 0.15),
  GenerationPhase('writing', 'Writing report', 0.25),
  GenerationPhase('filling', 'Filling template', 0.12),
  GenerationPhase('qa', 'Checking the report', 0.18),
  GenerationPhase('visual', 'Comparing pages with your examples', 0.20),
  GenerationPhase('finishing', 'Finishing', 0.10),
];

int generationPhaseIndex(String key) => generationPhases.indexWhere((phase) => phase.key == key);

double _minutesLeft({
  required int phaseIndex,
  required Duration elapsed,
  required Duration timeInPhase,
  required int typicalMinutes,
}) {
  final typical = typicalMinutes.toDouble();
  if (phaseIndex < 0) return math.max(typical - elapsed.inSeconds / 60, typical * 0.8);
  final current = generationPhases[phaseIndex].share * typical;
  var left = math.max(current - timeInPhase.inSeconds / 60, math.max(current * 0.25, 0.3));
  for (var i = phaseIndex + 1; i < generationPhases.length; i++) {
    left += generationPhases[i].share * typical;
  }
  return left;
}

/// Progress of a running report as one calm card: what Span is doing now,
/// a progress bar with time left, and the steps. You can leave the page.
class GenerationProgressPanel extends StatelessWidget {
  final String templateName;
  final String inspectionName;
  final String phaseKey;
  final Map<String, DateTime> phaseStartedAt;
  final DateTime startedAt;
  final DateTime now;
  final DateTime? lastEventAt;
  final int typicalMinutes;
  final int maxMinutes;
  final GenerationActivity? latestActivity;
  final bool isCancelling;
  final VoidCallback onCancel;

  const GenerationProgressPanel({
    super.key,
    required this.templateName,
    required this.inspectionName,
    required this.phaseKey,
    required this.phaseStartedAt,
    required this.startedAt,
    required this.now,
    required this.lastEventAt,
    required this.typicalMinutes,
    required this.maxMinutes,
    required this.isCancelling,
    required this.onCancel,
    this.latestActivity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final phaseIndex = generationPhaseIndex(phaseKey);
    final elapsed = now.difference(startedAt).isNegative ? Duration.zero : now.difference(startedAt);
    final phaseStart = phaseIndex >= 0 ? (phaseStartedAt[phaseKey] ?? startedAt) : startedAt;
    final timeInPhase = now.difference(phaseStart).isNegative ? Duration.zero : now.difference(phaseStart);
    final minutesLeft = _minutesLeft(
      phaseIndex: phaseIndex,
      elapsed: elapsed,
      timeInPhase: timeInPhase,
      typicalMinutes: typicalMinutes,
    );
    final elapsedMinutes = elapsed.inSeconds / 60;
    final progress = (elapsedMinutes / (elapsedMinutes + minutesLeft)).clamp(0.02, 0.98);
    final overdue = elapsedMinutes > 9 * 1.35;
    final etaText = minutesLeft < 1 ? 'Less than a minute left' : 'About ${minutesLeft.ceil()} min left';
    final quietFor = lastEventAt == null ? null : now.difference(lastEventAt!);
    final currentLabel = phaseIndex >= 0 ? generationPhases[phaseIndex].label : 'Starting';

    String? note;
    if (overdue) {
      note = 'Taking longer than usual. Some reports take up to $maxMinutes minutes.';
    } else if (quietFor != null && quietFor.inMinutes >= 3) {
      note = 'Span is working through a long step.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Span is writing your report', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '$templateName · $inspectionName',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(currentLabel, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(etaText, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < generationPhases.length; i++) _step(theme, i, phaseIndex),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(note, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 18),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Usually 4–9 minutes. You can leave this page; the report appears in Reports when it is done.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: isCancelling ? null : onCancel,
                style: TextButton.styleFrom(foregroundColor: colorScheme.onSurfaceVariant),
                child: Text(isCancelling ? 'Cancelling…' : 'Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(ThemeData theme, int i, int phaseIndex) {
    final colorScheme = theme.colorScheme;
    final phase = generationPhases[i];
    final done = i < phaseIndex;
    final active = i == phaseIndex || (phaseIndex < 0 && i == 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: done
                ? Icon(Icons.check_rounded, size: 18, color: colorScheme.primary)
                : active
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                      )
                    : Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
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
        ],
      ),
    );
  }
}
