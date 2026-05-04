import 'package:flutter/material.dart';
import '../../../widgets/search_field/search_field.dart';
import '../../../widgets/form_components/text_field.dart';
import '../../../widgets/button/button.dart';
import '../models/tool_group.dart';

class ManageToolsPanel extends StatefulWidget {
  final ToolGroup group;
  final List<ToolItem> allMasterTools;
  final Future<bool> Function(String newName, List<String> toolIds) onSave;

  const ManageToolsPanel({
    super.key,
    required this.group,
    required this.allMasterTools,
    required this.onSave,
  });

  @override
  State<ManageToolsPanel> createState() => _ManageToolsPanelState();
}

class _ManageToolsPanelState extends State<ManageToolsPanel> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isLoading = false;

  late Set<String> _selectedToolIds;
  String _searchQuery = '';
  String _filterMode = 'All'; // 'All', 'Selected', 'Unselected'

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _selectedToolIds = widget.group.tools.map((t) => t.id).toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildFilterChip(String label, ThemeData theme) {
    bool isActive = _filterMode == label;

    return InkWell(
      onTap: () => setState(() => _filterMode = label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.transparent,
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    bool success = await widget.onSave(
      _nameController.text.trim(),
      _selectedToolIds.toList(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filteredTools = widget.allMasterTools.where((tool) {
      bool matchesSearch = tool.name.toLowerCase().contains(_searchQuery.toLowerCase());
      bool isSelected = _selectedToolIds.contains(tool.id);
      bool matchesFilter = _filterMode == 'All' ||
          (_filterMode == 'Selected' && isSelected) ||
          (_filterMode == 'Unselected' && !isSelected);

      return matchesSearch && matchesFilter;
    }).toList();

    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: AbsorbPointer(
        absorbing: _isLoading,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.only(left: 24, right: 16, top: 16, bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Manage Tool Set", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Tool Set Name *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    FormControlTextField(
                      controller: _nameController,
                      hintText: "Enter a name for this tool set...",
                      validator: (val) => (val == null || val.trim().isEmpty) ? "Set name is required" : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchField(
                      hintText: "Search master tools...",
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildFilterChip('All', theme),
                        _buildFilterChip('Selected', theme),
                        _buildFilterChip('Unselected', theme),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              Expanded(
                child: filteredTools.isEmpty
                    ? Center(child: Text("No tools match your criteria.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filteredTools.length,
                        itemBuilder: (context, index) {
                          final tool = filteredTools[index];
                          final isSelected = _selectedToolIds.contains(tool.id);

                          return CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            title: Text(tool.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                            subtitle: isSelected ? Text("Assigned", style: TextStyle(color: theme.colorScheme.primary, fontSize: 11)) : null,
                            value: isSelected,
                            controlAffinity: ListTileControlAffinity.trailing,
                            activeColor: theme.colorScheme.primary,
                            onChanged: (bool? checked) {
                              setState(() {
                                checked == true ? _selectedToolIds.add(tool.id) : _selectedToolIds.remove(tool.id);
                              });
                            },
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(
                      label: "Cancel",
                      variant: ButtonVariant.outline,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Button(
                      label: _isLoading ? "Saving..." : "Save Changes",
                      variant: ButtonVariant.filled,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      onPressed: _isLoading ? null : _handleSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}