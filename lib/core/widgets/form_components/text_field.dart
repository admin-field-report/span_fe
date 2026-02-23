import 'package:flutter/material.dart';

class FormControlTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final IconData? prefixIcon;

  const FormControlTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.prefixIcon,
  });

  @override
  State<FormControlTextField> createState() => _FormControlTextFieldState();
}

class _FormControlTextFieldState extends State<FormControlTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword ? _obscureText : false,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
        prefixIcon: widget.prefixIcon != null 
            ? Icon(widget.prefixIcon, color: colorScheme.primary, size: 22) 
            : null,
        // Show/Hide Password Toggle
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
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
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      validator: widget.validator,
    );
  }
}