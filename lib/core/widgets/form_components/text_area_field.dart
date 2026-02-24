import 'package:flutter/material.dart';

class FormControlTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int minLines;
  final int? maxLines;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;

  const FormControlTextArea({
    super.key,
    required this.controller,
    required this.hintText,
    this.minLines = 4,
    this.maxLines,
    this.prefixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines ?? 10,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
        prefixIcon: prefixIcon != null 
            ? Padding(
                padding: const EdgeInsets.only(bottom: 60), 
                child: Icon(prefixIcon, color: colorScheme.primary, size: 22),
              ) 
            : null,
        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
        
        // --- BORDERS ---
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error.withOpacity(0.5), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        
        errorStyle: TextStyle(color: colorScheme.error, fontSize: 12),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}