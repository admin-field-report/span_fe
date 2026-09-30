import 'package:flutter/material.dart';

enum ButtonVariant { filled, outline, text }

class Button extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
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
    this.trailingIcon,
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

    // Text buttons read as links, so they default to the theme's primary colour.
    final primaryColor = color ?? (variant == ButtonVariant.text ? theme.colorScheme.primary : defaultBgColor);
    final onPrimaryColor = color != null ? Colors.white : defaultTextColor;

    final style = ElevatedButton.styleFrom(
      elevation: 0,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      
      backgroundColor: variant == ButtonVariant.filled ? primaryColor : Colors.transparent,
      
      foregroundColor: variant == ButtonVariant.filled ? onPrimaryColor : primaryColor,
          
      side: variant == ButtonVariant.outline 
          ? BorderSide(color: primaryColor, width: 1.5) 
          : null,
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) && !isLoading && variant != ButtonVariant.text) {
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
        
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold, 
              letterSpacing: 0.5,
              fontSize: 13,
            ),
          ),
        ),
        if (trailingIcon != null && !isLoading) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: 18),
        ],
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
          : variant == ButtonVariant.outline
              ? OutlinedButton(
                  onPressed: isLoading ? () {} : onPressed,
                  style: style,
                  child: content,
                )
              : TextButton(
                  onPressed: isLoading ? () {} : onPressed,
                  style: style,
                  child: content,
                ),
    );
  }
}