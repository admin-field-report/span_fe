import 'package:flutter/material.dart';
import '../models/canvas_tab.dart';

class CanvasTabStrip extends StatelessWidget {
  final List<CanvasTab> tabs;
  final String activeDocumentId;
  final List<Map<String, dynamic>> documents;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onAddTab;

  const CanvasTabStrip({
    super.key,
    required this.tabs,
    required this.activeDocumentId,
    required this.documents,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onAddTab,
  });

  String _labelFor(String documentId) {
    try {
      final doc = documents.firstWhere((d) => d['id'].toString() == documentId);
      final name = doc['document_name'];
      return (name != null && name.toString().trim().isNotEmpty) ? name.toString() : 'Document';
    } catch (_) {
      return 'Document';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 35,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ...tabs.map((tab) => _TabChip(
                  label: _labelFor(tab.documentId),
                  isActive: tab.documentId == activeDocumentId,
                  onSelect: () => onTabSelected(tab.documentId),
                  onClose: () => onTabClosed(tab.documentId),
                )),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: "Open another document",
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onAddTab,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _TabChip({
    required this.label,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200, minWidth: 96),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.surface : colorScheme.surfaceVariant.withOpacity(0.15),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          border: isActive
              ? Border.all(color: colorScheme.outlineVariant.withOpacity(0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
                onTap: onSelect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: isActive
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant.withOpacity(0.6),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Tooltip(
                          message: label,
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              color: isActive
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            InkWell(
              borderRadius: const BorderRadius.only(topRight: Radius.circular(8)),
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
