import 'package:flutter/material.dart';

class AuthBackground extends StatelessWidget {
  final Widget child;

  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Grid Painter
        CustomPaint(
          painter: _GridPainter(),
        ),
        // Glow Effect
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 0.8,
              colors: [
                const Color(0xFF1C58F6).withOpacity(0.15), // Blue glow
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        // Actual Content
        child,
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = const Color(0xFF1C58F6).withOpacity(0.12) // Dark blue shade for major lines
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final minorPaint = Paint()
      ..color = const Color(0xFF1C58F6).withOpacity(0.06) // Faint blue for minor lines
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const double minorGridSize = 11.5; // Reduced by another 20%
    const int minorPerMajor = 5; // 5 small squares make up 1 large square

    // Draw vertical lines
    int vCount = 0;
    for (double i = 0; i <= size.width; i += minorGridSize) {
      canvas.drawLine(
        Offset(i, 0), 
        Offset(i, size.height), 
        vCount % minorPerMajor == 0 ? majorPaint : minorPaint
      );
      vCount++;
    }

    // Draw horizontal lines
    int hCount = 0;
    for (double i = 0; i <= size.height; i += minorGridSize) {
      canvas.drawLine(
        Offset(0, i), 
        Offset(size.width, i), 
        hCount % minorPerMajor == 0 ? majorPaint : minorPaint
      );
      hCount++;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
