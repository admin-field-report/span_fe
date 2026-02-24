import 'package:flutter/material.dart';

enum ButtonVariant { filled, outline }

class Button extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;
  final Color? color;
  final bool isLoading;
  final double? width;
  final EdgeInsets? padding;

  const Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = ButtonVariant.filled,
    this.color,
    this.isLoading = false,
    this.width,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultBgColor = isDark ? Colors.white : Colors.black;
    final defaultTextColor = isDark ? Colors.black : Colors.white;

    final primaryColor = color ?? defaultBgColor;
    final onPrimaryColor = color != null ? Colors.white : defaultTextColor;

    final style = ElevatedButton.styleFrom(
      elevation: 0,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      
      backgroundColor: variant == ButtonVariant.filled ? primaryColor : Colors.transparent,
      
      foregroundColor: variant == ButtonVariant.filled ? onPrimaryColor : primaryColor,
          
      side: variant == ButtonVariant.outline 
          ? BorderSide(color: primaryColor, width: 1.5) 
          : null,
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) && !isLoading) {
          return theme.colorScheme.onSurface.withOpacity(0.12);
        }
        return variant == ButtonVariant.filled ? primaryColor : Colors.transparent;
      }),
    );

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == ButtonVariant.filled ? onPrimaryColor : primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ] else if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 10),
        ],
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold, 
            letterSpacing: 0.5,
            fontSize: 15,
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      child: variant == ButtonVariant.filled
          ? ElevatedButton(
              onPressed: isLoading ? () {} : onPressed, 
              style: style, 
              child: content,
            )
          : OutlinedButton(
              onPressed: isLoading ? () {} : onPressed, 
              style: style, 
              child: content,
            ),
    );
  }
}