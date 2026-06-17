import 'package:flutter/material.dart';

class SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final double? width;

  const SearchField({
    super.key,
    required this.onChanged,
    this.hintText = "Search...",
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: TextField(
            onChanged: onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              icon: const Icon(Icons.search, size: 20),
              hintText: hintText,
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 11), 
            ),
          ),
        ),
      ),
    );
  }
}