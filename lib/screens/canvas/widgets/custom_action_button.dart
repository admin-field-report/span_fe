import 'package:flutter/material.dart';

class CanvasToolbarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isDestructive;

  const CanvasToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Keep this close to the Canvas top-toolbar compact sizing.
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double size = isMobile ? 26 : 30;

    final bool isEnabled = onTap != null;

    final Color foregroundColor = !isEnabled
        ? theme.disabledColor.withOpacity(0.55)
        : isDestructive
            ? theme.colorScheme.error
            : isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant;

    final Color backgroundColor = isSelected
        ? theme.colorScheme.primary.withOpacity(0.14)
        : theme.colorScheme.surfaceVariant.withOpacity(isEnabled ? 0.18 : 0.10);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.26)
                    : theme.colorScheme.outlineVariant.withOpacity(
                        isEnabled ? 0.45 : 0.25,
                      ),
              ),
            ),
            child: Icon(
              icon,
              size: isMobile ? 15 : 17,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}