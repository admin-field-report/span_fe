import 'package:flutter/material.dart';
import '../../../../widgets/form_components/text_field.dart';
import '../../../../widgets/button/button.dart';

enum SelectionFilter { all, selected, unselected }

class InlineSelectionFilter<T> extends StatefulWidget {
  final List<T> allItems;
  final Set<String> selectedIds;
  final String Function(T) getName;
  final String Function(T) getId;
  final void Function(String, bool) onToggle;

  const InlineSelectionFilter({
    super.key, required this.allItems, required this.selectedIds,
    required this.getName, required this.getId, required this.onToggle,
  });

  @override
  State<InlineSelectionFilter<T>> createState() => _InlineSelectionFilterState<T>();
}

class _InlineSelectionFilterState<T> extends State<InlineSelectionFilter<T>> {
  final TextEditingController _searchController = TextEditingController();
  late List<T> _filteredItems;
  SelectionFilter _currentFilter = SelectionFilter.all;

  @override
  void initState() {
    super.initState();
    _filteredItems = List.from(widget.allItems);
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = widget.allItems.where((item) {
        if (!widget.getName(item).toLowerCase().contains(query)) return false;
        final isSelected = widget.selectedIds.contains(widget.getId(item));
        if (_currentFilter == SelectionFilter.selected && !isSelected) return false;
        if (_currentFilter == SelectionFilter.unselected && isSelected) return false;
        return true; 
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormControlTextField(controller: _searchController, hintText: "Search...", prefixIcon: Icons.search, textInputAction: TextInputAction.search),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text("All"), selected: _currentFilter == SelectionFilter.all, onSelected: (val) { if (val) setState(() => _currentFilter = SelectionFilter.all); _applyFilters(); }),
              ChoiceChip(label: const Text("Selected"), selected: _currentFilter == SelectionFilter.selected, onSelected: (val) { if (val) setState(() => _currentFilter = SelectionFilter.selected); _applyFilters(); }),
              ChoiceChip(label: const Text("Unselected"), selected: _currentFilter == SelectionFilter.unselected, onSelected: (val) { if (val) setState(() => _currentFilter = SelectionFilter.unselected); _applyFilters(); }),
            ],
          ),
        ),
        Expanded(
          child: _filteredItems.isEmpty
              ? const Center(child: Text("No items match your filters."))
              : ListView.builder(
                  shrinkWrap: true, itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    final itemId = widget.getId(item);
                    final isSelected = widget.selectedIds.contains(itemId);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero, title: Text(widget.getName(item)), value: isSelected, activeColor: theme.colorScheme.primary,
                      onChanged: (bool? val) { widget.onToggle(itemId, val ?? false); if (_currentFilter != SelectionFilter.all) _applyFilters(); },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ManageSelectionContent<T> extends StatefulWidget {
  final String title;
  final List<T> allItems;
  final List<T> selectedItems;
  final String Function(T) getName;
  final String Function(T) getId;
  final void Function(List<T>) onSave;
  final bool isDialog;

  const ManageSelectionContent({
    super.key, required this.title, required this.allItems, required this.selectedItems,
    required this.getName, required this.getId, required this.onSave, required this.isDialog,
  });

  @override
  State<ManageSelectionContent<T>> createState() => _ManageSelectionContentState<T>();
}

class _ManageSelectionContentState<T> extends State<ManageSelectionContent<T>> {
  late Set<String> _tempSelectedIds;

  @override
  void initState() {
    super.initState();
    _tempSelectedIds = widget.selectedItems.map((item) => widget.getId(item)).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: theme.colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), splashRadius: 20),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            child: InlineSelectionFilter<T>(
              allItems: widget.allItems, selectedIds: _tempSelectedIds, getName: widget.getName, getId: widget.getId,
              onToggle: (id, isSelected) { setState(() { isSelected ? _tempSelectedIds.add(id) : _tempSelectedIds.remove(id); }); },
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, widget.isDialog ? 16 : 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(label: "Cancel", variant: ButtonVariant.outline, onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 12),
              Button(
                label: "Save Changes",
                onPressed: () {
                  final savedItems = widget.allItems.where((e) => _tempSelectedIds.contains(widget.getId(e))).toList();
                  widget.onSave(savedItems);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}