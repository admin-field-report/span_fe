import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/canvas_models.dart';

class CustomToolsPanel extends StatelessWidget {
  final List<CustomToolGroup> groups;
  final CustomTool? selectedTool;
  final Function(CustomTool) onToolSelected;
  final VoidCallback onClose;

  const CustomToolsPanel({
    super.key,
    required this.groups,
    required this.selectedTool,
    required this.onToolSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Custom Tools", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onClose, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ],
            ),
          ),
          
          // Tool Groups List
          Expanded(
            child: groups.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return ExpansionTile(
                        title: Text(group.toolGroup, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        initiallyExpanded: index == 0,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: group.tools.length,
                              itemBuilder: (context, toolIndex) {
                                final tool = group.tools[toolIndex];
                                final isSelected = selectedTool?.toolId == tool.toolId;                              

                                return InkWell(
                                  onTap: () => onToolSelected(tool),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, width: isSelected ? 2 : 1),
                                      borderRadius: BorderRadius.circular(8),
                                      color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : Colors.transparent,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: tool.decodedImage != null 
                                              ? RawImage(image: tool.decodedImage, fit: BoxFit.contain)
                                              : const Center(child: Icon(Icons.image_not_supported, size: 20, color: Colors.grey)),
                                        ),
                                        
                                        const SizedBox(height: 4),
                                        Text(tool.toolName, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}