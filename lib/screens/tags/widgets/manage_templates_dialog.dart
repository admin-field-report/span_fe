import 'package:flutter/material.dart';
import '../../../../widgets/button/button.dart';
import '../controllers/tag_controller.dart';
import '../../../../models/tag_models.dart';
import 'inline_selection_filter.dart'; 

class ManageTemplatesDialog extends StatefulWidget {
  final TagController controller;
  final Set<String> initialSelectedIds;
  
  final Future<bool> Function(List<String> selectedIds) onSave;

  const ManageTemplatesDialog({
    Key? key,
    required this.controller,
    required this.initialSelectedIds,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ManageTemplatesDialog> createState() => _ManageTemplatesDialogState();
}

class _ManageTemplatesDialogState extends State<ManageTemplatesDialog> {
  late Set<String> _selectedTemplateIds;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedTemplateIds = Set.from(widget.initialSelectedIds);
  }

  Future<void> _onSave() async {
    setState(() => _isSubmitting = true);

    final success = await widget.onSave(_selectedTemplateIds.toList());

    if (!mounted) return;

    if (success) {
      Navigator.pop(context); 
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600), // Slightly shorter max height
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: theme.colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Manage Templates", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close), 
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // --- BODY (Selection Only) ---
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AbsorbPointer(
                  absorbing: _isSubmitting,
                  child: InlineSelectionFilter<AppTemplate>(
                    allItems: widget.controller.globalTemplates, 
                    selectedIds: _selectedTemplateIds, 
                    getName: (t) => t.name, 
                    getId: (t) => t.id,
                    onToggle: (id, isSelected) => setState(() => isSelected ? _selectedTemplateIds.add(id) : _selectedTemplateIds.remove(id)),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            
            // --- FOOTER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    label: "Cancel", 
                    variant: ButtonVariant.outline, 
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    label: _isSubmitting ? "Saving..." : "Save Changes",
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _onSave,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}