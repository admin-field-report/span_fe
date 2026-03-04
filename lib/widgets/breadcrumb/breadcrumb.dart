import 'package:flutter/material.dart';

class BreadcrumbItem {
  final String label;
  final VoidCallback? onTap;

  BreadcrumbItem({
    required this.label, 
    this.onTap, 
  });
}

class AppBreadcrumbs extends StatelessWidget {
  final List<BreadcrumbItem> items;

  const AppBreadcrumbs({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isLast = index == items.length - 1;

        return Row(
          children: [
            MouseRegion(
              cursor: item.onTap != null && !isLast 
                  ? SystemMouseCursors.click 
                  : SystemMouseCursors.basic,
              child: InkWell(
                onTap: isLast ? null : item.onTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    item.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isLast 
                          ? colorScheme.onSurface 
                          : colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
            
            // The Dot Separator from your reference
            if (!isLast)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}