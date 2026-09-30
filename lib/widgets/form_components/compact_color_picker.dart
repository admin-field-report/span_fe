import 'package:flutter/material.dart';

class CompactColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final bool showOpacity;

  const CompactColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    this.showOpacity = true,
  });

  @override
  State<CompactColorPicker> createState() => _CompactColorPickerState();
}

class _CompactColorPickerState extends State<CompactColorPicker> {
  late HSVColor hsvColor;
  late double localOpacity;

  final List<Color> pickerPresets = const [
    Color(0xFFFF5252), Color(0xFFFF9800), Color(0xFFFFEB3B), Color(0xFFCDDC39),
    Color(0xFF4CAF50), Color(0xFF009688), Color(0xFF00BCD4), Color(0xFF03A9F4),
    Color(0xFF2196F3), Color(0xFF3F51B5), Color(0xFF9C27B0), Color(0xFFE91E63),
    Color(0xFF795548), Color(0xFF9E9E9E), Color(0xFF000000), Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    final Color baseColor = widget.initialColor == Colors.transparent ? Colors.red : widget.initialColor;
    hsvColor = HSVColor.fromColor(baseColor.withAlpha(255));
    localOpacity = widget.initialColor == Colors.transparent ? 0.0 : widget.initialColor.alpha / 255.0;
  }

  void updateColor(Color newColor) {
    if (newColor == Colors.transparent) {
      setState(() {
        localOpacity = 0.0;
      });
      widget.onColorChanged(Colors.transparent);
      return;
    }
    
    setState(() {
      hsvColor = HSVColor.fromColor(newColor.withAlpha(255));
    });
    
    // Maintain current opacity when changing colors
    widget.onColorChanged(newColor.withOpacity(localOpacity));
  }

  String colorToHex(Color c) => c == Colors.transparent ? "NONE" : '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const double squareWidth = 236.0;
    const double squareHeight = 140.0;
    final bool showNone = widget.showOpacity;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hex & Preview Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              colorToHex(localOpacity == 0.0 && widget.showOpacity ? Colors.transparent : hsvColor.toColor()),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')
            ),
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: widget.showOpacity ? hsvColor.toColor().withOpacity(localOpacity) : hsvColor.toColor(),
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: localOpacity == 0.0 && widget.showOpacity ? const Icon(Icons.block, color: Colors.red, size: 14) : null,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Saturation/Value Box
        GestureDetector(
          onPanDown: (details) {
            double s = (details.localPosition.dx / squareWidth).clamp(0.0, 1.0);
            double v = (1.0 - (details.localPosition.dy / squareHeight)).clamp(0.0, 1.0);
            updateColor(hsvColor.withSaturation(s).withValue(v).toColor());
          },
          onPanUpdate: (details) {
            double s = (details.localPosition.dx / squareWidth).clamp(0.0, 1.0);
            double v = (1.0 - (details.localPosition.dy / squareHeight)).clamp(0.0, 1.0);
            updateColor(hsvColor.withSaturation(s).withValue(v).toColor());
          },
          child: Stack(
            children: [
              Container(
                width: squareWidth, height: squareHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(colors: [Colors.white, hsvColor.withSaturation(1).withValue(1).toColor()])
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(colors: [Colors.transparent, Colors.black], begin: Alignment.topCenter, end: Alignment.bottomCenter)
                  )
                ),
              ),
              Positioned(
                left: (hsvColor.saturation * squareWidth) - 8,
                top: ((1 - hsvColor.value) * squareHeight) - 8,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                  )
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Hue Slider
        Container(
          width: squareWidth, height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Color(0xFFFF00FF), Colors.red])
          ),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 10,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: hsvColor.hue,
              min: 0,
              max: 360,
              onChanged: (v) => updateColor(hsvColor.withHue(v).toColor())
            )
          ),
        ),
        const SizedBox(height: 14),

        // Opacity Slider
        if (widget.showOpacity) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Opacity", style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
              Text("${(localOpacity * 100).toInt()}%", style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.bold))
            ]
          ),
          const SizedBox(height: 6),
          Container(
            width: squareWidth, height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              gradient: LinearGradient(colors: [Colors.transparent, hsvColor.toColor()])
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: localOpacity, min: 0.0, max: 1.0,
                onChanged: (v) {
                  setState(() => localOpacity = v);
                  widget.onColorChanged(hsvColor.toColor().withOpacity(v));
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Presets
        Text("Presets", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          width: squareWidth,
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              if (showNone)
                GestureDetector(
                  onTap: () => updateColor(Colors.transparent),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      shape: BoxShape.circle,
                      border: localOpacity == 0.0
                          ? Border.all(color: theme.colorScheme.primary, width: 2.0)
                          : Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3), width: 1.0),
                    ),
                    child: const Icon(Icons.block, size: 14, color: Colors.red),
                  )
                ),

              ...pickerPresets.map((color) {
                final isSelected = hsvColor.toColor() == color && localOpacity > 0;
                final isWhite = color == const Color(0xFFFFFFFF);

                return GestureDetector(
                  onTap: () {
                    if (localOpacity == 0.0) {
                      setState(() => localOpacity = 1.0);
                    }
                    updateColor(color);
                  },
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: (isSelected || isWhite)
                          ? Border.all(
                              color: isSelected ? theme.colorScheme.primary : Colors.grey.shade400,
                              width: isSelected ? 2.0 : 1.0
                            )
                          : null,
                      boxShadow: [
                        if (!isSelected)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 3,
                            spreadRadius: 0,
                            offset: const Offset(0, 1.5),
                          )
                      ],
                    )
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
