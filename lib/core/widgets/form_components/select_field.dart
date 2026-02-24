import 'package:flutter/material.dart';

abstract class SelectableItem<T> {
  T get id;
  String get name;
}

// class FormControlSelect<T> extends StatelessWidget {
//   final T? value;
//   final List<SelectableItem<T>> items;
//   final String hintText;
//   final IconData? prefixIcon;
//   final bool isLoading;
//   final Function(T?) onChanged;
//   final String? Function(T?)? validator;

//   const FormControlSelect({
//     super.key,
//     required this.value,
//     required this.items,
//     required this.hintText,
//     required this.onChanged,
//     this.isLoading = false,
//     this.prefixIcon,
//     this.validator,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final colorScheme = theme.colorScheme;

//     final T? effectiveValue = isLoading ? null : value;

//     return DropdownButtonFormField<T>(
//       value: effectiveValue,
//       onChanged: isLoading ? null : onChanged,
//       validator: validator,
//       autovalidateMode: AutovalidateMode.onUserInteraction,
//       dropdownColor: theme.cardColor,
//       icon: isLoading 
//           ? const SizedBox.shrink() 
//           : Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.onSurfaceVariant),
//       style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
//       decoration: InputDecoration(
//         hintText: isLoading ? "Fetching data..." : hintText,
//         hintStyle: TextStyle(
//           color: colorScheme.onSurfaceVariant.withOpacity(isLoading ? 1.0 : 0.7),
//           fontStyle: isLoading ? FontStyle.italic : FontStyle.normal,
//         ),
//         prefixIcon: prefixIcon != null 
//             ? Icon(prefixIcon, color: colorScheme.primary, size: 22) 
//             : null,
        
//         // --- THE LOADER ---
//         suffixIcon: isLoading 
//             ? Container(
//                 width: 20,
//                 height: 20,
//                 padding: const EdgeInsets.only(right: 16),
//                 alignment: Alignment.centerRight,
//                 child: SizedBox(
//                   width: 18,
//                   height: 18,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2,
//                     valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
//                   ),
//                 ),
//               ) 
//             : null,

//         filled: true,
//         fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: BorderSide.none,
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
//         ),
//         errorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: BorderSide(color: colorScheme.error, width: 1),
//         ),
//         focusedErrorBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//           borderSide: BorderSide(color: colorScheme.error, width: 1.5),
//         ),

//         errorStyle: TextStyle(color: colorScheme.error, fontSize: 12),
//         contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
//       ),
//       items: isLoading 
//           ? null 
//           : items.map((item) => DropdownMenuItem<T>(
//               value: item.id,
//               child: Text(item.name),
//             )).toList(),
//     );
//   }
// }

class FormControlSelect<T> extends StatelessWidget {
  final T? value;
  final List<SelectableItem<T>> items;
  final String hintText;
  final String emptyText;
  final IconData? prefixIcon;
  final bool isLoading;
  final Function(T?) onChanged;
  final String? Function(T?)? validator;

  const FormControlSelect({
    super.key,
    required this.value,
    required this.items,
    required this.hintText,
    this.emptyText = "No data available",
    required this.onChanged,
    this.isLoading = false,
    this.prefixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool hasData = items.isNotEmpty;
    final bool isDisabled = isLoading || !hasData;

    return DropdownButtonFormField<T>(
      value: (isLoading || !hasData) ? null : value,
      onChanged: isDisabled ? null : onChanged,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      dropdownColor: theme.cardColor,
      icon: isDisabled
          ? const SizedBox.shrink()
          : Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.onSurfaceVariant),
      style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
      decoration: InputDecoration(
        hintText: isLoading 
            ? "Fetching data..." 
            : (!hasData ? emptyText : hintText),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withOpacity(isDisabled ? 0.5 : 0.7),
          fontStyle: isDisabled ? FontStyle.italic : FontStyle.normal,
        ),
        prefixIcon: prefixIcon != null 
            ? Icon(prefixIcon, color: colorScheme.primary.withOpacity(isDisabled ? 0.5 : 1.0), size: 22) 
            : null,
        
        // --- SUFFIX LOGIC ---
        suffixIcon: isLoading 
            ? _buildLoader(colorScheme)
            : (!hasData 
                ? Icon(Icons.info_outline_rounded, size: 20, color: colorScheme.onSurfaceVariant.withOpacity(0.5))
                : null),

        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
      items: isDisabled
          ? null 
          : items.map((item) => DropdownMenuItem<T>(
              value: item.id,
              child: Text(item.name),
            )).toList(),
    );
  }

  Widget _buildLoader(ColorScheme colorScheme) {
    return Container(
      width: 20,
      height: 20,
      padding: const EdgeInsets.only(right: 16),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        ),
      ),
    );
  }
}