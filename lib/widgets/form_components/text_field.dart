import 'package:flutter/material.dart';

enum TextFieldVariant { filled, outlined }

class FormControlTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final String? labelText; 
  final String? errorText; 
  final TextFieldVariant variant; 
  final bool isPassword;
  final bool autofocus; 
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted; 
  final TextInputAction textInputAction;
  final IconData? prefixIcon;

  const FormControlTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.labelText,
    this.errorText,
    this.variant = TextFieldVariant.filled,
    this.isPassword = false,
    this.autofocus = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onFieldSubmitted,
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
    
    final isOutlined = widget.variant == TextFieldVariant.outlined;

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword ? _obscureText : false,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofocus: widget.autofocus, 
      onFieldSubmitted: widget.onFieldSubmitted, 
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(color: colorScheme.onSurface),
      validator: widget.validator,
      
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText, 
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
        
        prefixIcon: widget.prefixIcon != null 
            ? Icon(widget.prefixIcon, color: colorScheme.primary, size: 22) 
            : null,
            
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
            
        // 🚀 Original Fill Logic
        filled: !isOutlined, 
        fillColor: isOutlined ? Colors.transparent : colorScheme.surfaceVariant.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), 
        
        // Uniform 8px Borders
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
    );
  }
}