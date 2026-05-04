import 'package:flutter/material.dart';

class PropertiesPanel extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback onClose;

  const PropertiesPanel({
    super.key,
    required this.title,
    required this.content,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: 260, // 🚀 Reduced width from 280 to 260
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12), // 🚀 Tighter top and bottom padding
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title, 
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 1.0, 
                      fontSize: 12, // Slightly smaller text
                    )
                  )
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Dynamic Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16), // 🚀 Reduced overall inner padding from 24 to 16
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}