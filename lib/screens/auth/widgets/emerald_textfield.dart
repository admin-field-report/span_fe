// import 'package:flutter/material.dart';

// class EmeraldTextField extends StatelessWidget {
//   final TextEditingController controller;
//   final String hint;
//   final IconData icon;
//   final TextInputType keyboardType;
//   final String? Function(String?)? validator;
//   final bool isPassword;
//   final bool isVisible;
//   final VoidCallback? onToggleVisibility;

//   static const Color emerald = Color(0xFF00AB55);
//   static const Color inactiveText = Color(0xFF919EAB);
//   static const Color errorRed = Color(0xFFFF4842);

//   const EmeraldTextField({
//     super.key,
//     required this.controller,
//     required this.hint,
//     required this.icon,
//     this.keyboardType = TextInputType.text,
//     this.validator,
//     this.isPassword = false,
//     this.isVisible = true,
//     this.onToggleVisibility,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return TextFormField(
//       controller: controller,
//       keyboardType: keyboardType,
//       validator: validator,
//       obscureText: isPassword && !isVisible,
//       style: const TextStyle(color: Colors.white, fontSize: 14),
//       decoration: InputDecoration(
//         hintText: hint,
//         hintStyle: const TextStyle(color: inactiveText),
//         prefixIcon: Icon(icon, color: inactiveText, size: 20),
        
//         // Suffix Icon for Passwords (optional)
//         suffixIcon: isPassword
//             ? IconButton(
//                 icon: Icon(
//                   isVisible ? Icons.visibility : Icons.visibility_off,
//                   color: inactiveText,
//                   size: 20,
//                 ),
//                 onPressed: onToggleVisibility,
//               )
//             : null,
            
//         filled: true,
//         fillColor: Colors.white.withOpacity(0.05),
//         contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        
//         // STANDARD BORDERS
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12), 
//           borderSide: BorderSide.none,
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12), 
//           borderSide: BorderSide.none,
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12), 
//           borderSide: const BorderSide(color: emerald, width: 1.5),
//         ),
        
//         // ERROR BORDERS
//         errorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: const BorderSide(color: errorRed, width: 1),
//         ),
//         focusedErrorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: const BorderSide(color: errorRed, width: 1.5),
//         ),
        
//         errorStyle: const TextStyle(color: errorRed),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';

class EmeraldTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final IconData? prefixIcon;

  const EmeraldTextField({
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
  State<EmeraldTextField> createState() => _EmeraldTextFieldtate();
}

class _EmeraldTextFieldtate extends State<EmeraldTextField> {
  bool _obscureText = true;

  static const Color emerald = Color(0xFF00AB55);
  static const Color inactiveText = Color(0xFF919EAB);
  static const Color errorRed = Color(0xFFFF4842);

  @override
  Widget build(BuildContext context) {

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword ? _obscureText : false,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: const TextStyle(color: inactiveText),
        prefixIcon: widget.prefixIcon != null 
            ? Icon(widget.prefixIcon, color: inactiveText, size: 22) 
            : null,
        // Show/Hide Password Toggle
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: inactiveText,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
        filled: true,
        // fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorRed, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      validator: widget.validator,
    );
  }
}