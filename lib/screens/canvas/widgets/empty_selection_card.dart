import 'package:flutter/material.dart';
import '../../../widgets/button/button.dart';

/// Dashed empty-state card used in the canvas side panels (no tag groups,
/// tool sets or images). The action and link are hidden when their callbacks are null.
class EmptySelectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;
  final String linkLabel;
  final VoidCallback? onLink;

  const EmptySelectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = "Please add or create them here.",
    this.actionLabel = '',
    this.onAction,
    this.linkLabel = '',
    this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomPaint(
      painter: _DashedBorderPainter(
        color: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.3) : theme.colorScheme.outline,
        radius: 12,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 16),
              Button(
                label: actionLabel,
                icon: Icons.add,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: onAction,
              ),
            ],
            if (onLink != null) ...[
              const SizedBox(height: 4),
              Button(
                label: linkLabel,
                variant: ButtonVariant.text,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onPressed: onLink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  static const double dashWidth = 6;
  static const double dashGap = 4;

  _DashedBorderPainter({required this.color, this.radius = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
