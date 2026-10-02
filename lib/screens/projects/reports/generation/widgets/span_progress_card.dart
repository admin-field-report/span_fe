import 'package:flutter/material.dart';

/// One plain-language step Span works through.
class SpanStep {
  final String label;
  final String? detail;

  const SpanStep(this.label, [this.detail]);
}

const Color _ink = Color(0xFF212529);
const Color _muted = Color(0xFF868E96);
const Color _line = Color(0xFFDEE2E6);

/// The progress card shown while Span writes a report or builds a template:
/// a bar, the steps (done / now / next), and a note that the user can leave.
/// Neutral colors only (no brand teal on these screens).
class SpanProgressCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SpanStep> steps;

  /// Index of the step in progress.
  final int current;

  /// 0..1 overall.
  final double progress;
  final String leaveNote;
  final String backLabel;
  final VoidCallback onBack;
  final VoidCallback? onCancel;
  final bool cancelling;

  const SpanProgressCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.current,
    required this.progress,
    required this.leaveNote,
    required this.backLabel,
    required this.onBack,
    this.onCancel,
    this.cancelling = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: Color(0xFF495057))),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const ValueKey('span-progress-bar'),
              value: progress.clamp(0.04, 1.0),
              minHeight: 8,
              color: _ink,
              backgroundColor: const Color(0xFFE9ECEF),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _step(steps[i], i < current ? _State.done : (i == current ? _State.now : _State.next)),
          ],
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE9ECEF)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(leaveNote, style: const TextStyle(fontSize: 13, color: Color(0xFF495057), height: 1.4))),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _line),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(backLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: cancelling ? null : onCancel,
              style: TextButton.styleFrom(foregroundColor: _muted, padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              child: Text(cancelling ? 'Stopping…' : 'Stop', style: const TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _step(SpanStep step, _State state) {
    final icon = switch (state) {
      _State.done => Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: _ink, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
        ),
      _State.now => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _ink, width: 2)),
          alignment: Alignment.center,
          child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _ink, shape: BoxShape.circle)),
        ),
      _State.next => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFCED4DA), width: 1.5)),
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: state == _State.next ? FontWeight.w400 : FontWeight.w500,
                  color: state == _State.next ? _muted : _ink,
                ),
              ),
              if (step.detail != null && step.detail!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(step.detail!, style: const TextStyle(fontSize: 13, color: _muted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum _State { done, now, next }

/// The four steps of writing a report, from the agent's phases.
const List<SpanStep> reportSteps = [
  SpanStep('Reading the inspection', 'Markups, photos and field notes'),
  SpanStep('Writing the report', 'Observations and recommendations'),
  SpanStep('Placing photos'),
  SpanStep('Final check', 'Layout and fields match your template'),
];

int reportStepFor(String phaseKey) => switch (phaseKey) {
      'starting' || 'reading' => 0,
      'writing' => 1,
      'filling' => 2,
      'qa' || 'visual' || 'finishing' => 3,
      _ => 0,
    };

/// Overall progress for a report run, from its phase.
double reportProgressFor(String phaseKey) => switch (phaseKey) {
      'starting' => 0.05,
      'reading' => 0.15,
      'writing' => 0.35,
      'filling' => 0.55,
      'qa' => 0.7,
      'visual' => 0.85,
      'finishing' => 0.95,
      _ => 0.05,
    };

/// The four steps of building a template, from the agent's phases.
const List<SpanStep> templateSteps = [
  SpanStep('Reading your examples'),
  SpanStep('Building the Word template', 'Headers, tables, and photo layout'),
  SpanStep('Checking it against your examples'),
  SpanStep('Writing instructions and style guide', 'How Span fills and words each section'),
];

int templateStepFor(String phaseKey) => switch (phaseKey) {
      'starting' || 'reading' => 0,
      'building' => 1,
      'checking' => 2,
      'writing' || 'packaging' => 3,
      _ => 0,
    };

double templateProgressFor(String phaseKey) => switch (phaseKey) {
      'starting' => 0.05,
      'reading' => 0.15,
      'building' => 0.4,
      'checking' => 0.6,
      'writing' => 0.8,
      'packaging' => 0.95,
      _ => 0.05,
    };

/// Compact progress for a list row: a short label and a thin bar.
class SpanRowProgress extends StatelessWidget {
  final String label;
  final double progress;

  const SpanRowProgress({super.key, required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF495057))),
        const SizedBox(height: 6),
        SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.04, 1.0),
              minHeight: 6,
              color: _ink,
              backgroundColor: const Color(0xFFE9ECEF),
            ),
          ),
        ),
      ],
    );
  }
}
