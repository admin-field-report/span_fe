import 'package:flutter/material.dart';

class AppColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const AppColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

class _AppColorPickerState extends State<AppColorPicker> {
  late HSVColor _hsvColor;

  // Standard preset colors (Transparent option removed)
  final List<Color> _presetColors = [
    const Color(0xFFF44336), const Color(0xFFFF9800), const Color(0xFFFFEB3B), const Color(0xFFCDDC39),
    const Color(0xFF4CAF50), const Color(0xFF009688), const Color(0xFF00BCD4), const Color(0xFF03A9F4),
    const Color(0xFF2196F3), const Color(0xFF3F51B5), const Color(0xFF9C27B0), const Color(0xFFE91E63),
    const Color(0xFF795548), const Color(0xFF9E9E9E), const Color(0xFF000000), const Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
  }

  // --- Helpers ---
  String get _hexString {
    final color = _hsvColor.toColor();
    final r = color.red.toRadixString(16).padLeft(2, '0');
    final g = color.green.toRadixString(16).padLeft(2, '0');
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    
    if (color.alpha == 255) {
      return '#${(r + g + b).toUpperCase()}';
    } else {
      final a = color.alpha.toRadixString(16).padLeft(2, '0');
      return '#${(a + r + g + b).toUpperCase()}';
    }
  }

  void _onColorChanged(HSVColor color) {
    setState(() => _hsvColor = color);
    widget.onColorChanged(_hsvColor.toColor());
  }

  void _handleSVPickerInteraction(Offset localPosition, Size size) {
    final dx = localPosition.dx.clamp(0.0, size.width);
    final dy = localPosition.dy.clamp(0.0, size.height);
    final saturation = dx / size.width;
    final value = 1.0 - (dy / size.height);
    _onColorChanged(_hsvColor.withSaturation(saturation).withValue(value));
  }

  void _handleHueSliderInteraction(Offset localPosition, Size size) {
    final dx = localPosition.dx.clamp(0.0, size.width);
    final hue = (dx / size.width) * 360.0;
    _onColorChanged(_hsvColor.withHue(hue));
  }

  void _handleOpacitySliderInteraction(Offset localPosition, Size size) {
    final dx = localPosition.dx.clamp(0.0, size.width);
    final alpha = dx / size.width;
    _onColorChanged(_hsvColor.withAlpha(alpha));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. HEADER (Preview Circle & Hex Code)
        Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  CustomPaint(size: const Size(48, 48), painter: _CheckerboardPainter()),
                  Container(color: _hsvColor.toColor()),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Selected Color", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                Text(_hexString, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 2. SATURATION & VALUE PICKER (The big square)
        LayoutBuilder(
          builder: (context, constraints) {
            final boxSize = Size(constraints.maxWidth, 200);
            final thumbX = _hsvColor.saturation * boxSize.width;
            final thumbY = (1.0 - _hsvColor.value) * boxSize.height;

            return GestureDetector(
              onPanDown: (details) => _handleSVPickerInteraction(details.localPosition, boxSize),
              onPanUpdate: (details) => _handleSVPickerInteraction(details.localPosition, boxSize),
              child: Container(
                width: boxSize.width, height: boxSize.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: HSVColor.fromAHSV(1.0, _hsvColor.hue, 1.0, 1.0).toColor(),
                ),
                child: Stack(
                  children: [
                    Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Colors.white, Colors.transparent], begin: Alignment.centerLeft, end: Alignment.centerRight))),
                    Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Colors.transparent, Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
                    Positioned(
                      left: thumbX - 10, top: thumbY - 10,
                      child: Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: _hsvColor.withAlpha(1.0).toColor(), 
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        ),
        const SizedBox(height: 20),

        // 3. HUE SLIDER (The rainbow bar)
        LayoutBuilder(
          builder: (context, constraints) {
            final sliderSize = Size(constraints.maxWidth, 24);
            final thumbX = (_hsvColor.hue / 360.0) * sliderSize.width;

            return GestureDetector(
              onPanDown: (details) => _handleHueSliderInteraction(details.localPosition, sliderSize),
              onPanUpdate: (details) => _handleHueSliderInteraction(details.localPosition, sliderSize),
              child: SizedBox(
                width: sliderSize.width, height: sliderSize.height,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: const LinearGradient(colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)]),
                      ),
                    ),
                    Positioned(
                      left: thumbX - 12,
                      child: Container(
                        width: 24, height: 24,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        ),
        const SizedBox(height: 16),

        // 4. OPACITY SLIDER
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Opacity", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
            Text("${(_hsvColor.alpha * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final sliderSize = Size(constraints.maxWidth, 24);
            final thumbX = _hsvColor.alpha * sliderSize.width;

            return GestureDetector(
              onPanDown: (details) => _handleOpacitySliderInteraction(details.localPosition, sliderSize),
              onPanUpdate: (details) => _handleOpacitySliderInteraction(details.localPosition, sliderSize),
              child: SizedBox(
                width: sliderSize.width, height: sliderSize.height,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(size: Size(sliderSize.width, 16), painter: _CheckerboardPainter()),
                    ),
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          colors: [_hsvColor.withAlpha(0.0).toColor(), _hsvColor.withAlpha(1.0).toColor()],
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbX - 12,
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: _hsvColor.toColor(),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        ),
        const SizedBox(height: 24),

        // 5. PRESET COLORS
        const Center(child: Text("Preset Colors", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12, runSpacing: 12,
          alignment: WrapAlignment.center,
          children: _presetColors.map((color) {
            final isSelected = _hsvColor.toColor().value == color.value;

            return GestureDetector(
              onTap: () => _onColorChanged(HSVColor.fromColor(color)),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: color, 
                  shape: BoxShape.circle,
                  border: isSelected 
                      ? Border.all(color: theme.colorScheme.primary, width: 3)
                      : Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  boxShadow: isSelected ? [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.4), blurRadius: 6)] : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const squareSize = 8.0;
    
    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        paint.color = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0
            ? const Color(0xFFE0E0E0) 
            : Colors.white;
        canvas.drawRect(Rect.fromLTWH(x, y, squareSize, squareSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}