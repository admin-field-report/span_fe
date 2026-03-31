import 'dart:math' as math;
import 'package:flutter/material.dart';

class Loader extends StatefulWidget {
  final double size;
  final Color color;
  final int dotCount;
  final Duration duration;

  const Loader({
    super.key,
    this.size = 50.0, 
    this.color = const Color(0xFFFF5252), 
    this.dotCount = 12,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(); 
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _LoaderPainter(
              animationValue: _controller.value,
              color: widget.color,
              dotCount: widget.dotCount,
            ),
          );
        },
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final int dotCount;

  _LoaderPainter({
    required this.animationValue,
    required this.color,
    required this.dotCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final double maxDotRadius = size.width / 12; 
    final Offset center = Offset(radius, radius);

    for (int i = 0; i < dotCount; i++) {
      final double angle = (i * 2 * math.pi) / dotCount - (math.pi / 2);
      final double x = center.dx + (radius - maxDotRadius) * math.cos(angle);
      final double y = center.dy + (radius - maxDotRadius) * math.sin(angle);

      double normalizedIndex = i / dotCount;
      double distance = animationValue - normalizedIndex;
      if (distance < 0) {
        distance += 1.0;
      }
      
      double opacity = 1.0 - distance;

      final Paint paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      final double currentDotRadius = maxDotRadius * (0.4 + 0.6 * opacity);

      canvas.drawCircle(Offset(x, y), currentDotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoaderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.color != color;
  }
}