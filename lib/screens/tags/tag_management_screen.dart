import 'package:flutter/material.dart';
import '../../../widgets/form_components/text_field.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/card/card.dart';
import '../../../widgets/form_components/color_picker_field.dart';
import './controllers/tag_controller.dart';
import '../../../models/tag_models.dart';
import '../../utils/app_responsive.dart';

enum MobileView { groups, groupDetails, allTags }

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  final TagController _controller = TagController();
  
  String? _selectedGroupId;
  MobileView _currentMobileView = MobileView.groups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchAllData();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ==========================================
  // MOBILE NAVIGATION HELPER
  // ==========================================
  
  Widget _buildMobileHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 17),
            onPressed: () => setState(() => _currentMobileView = MobileView.groups),
            splashRadius: 24,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  // ==========================================
  // DIALOGS & ACTIONS
  // ==========================================

  void _showCreateTagDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    Color selectedColor = const Color(0xFFC9D647); // Default starting color

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.hardEdge, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Create New Tag", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), splashRadius: 20),
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Tag Name", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        FormControlTextField(
                          controller: nameController,
                          hintText: "Enter tag name...",
                          prefixIcon: Icons.local_offer_outlined,
                          validator: (val) => (val == null || val.trim().isEmpty) ? "Tag name is required" : null,
                        ),
                        const SizedBox(height: 24),
                        const Text("Tag Color", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 12),
                        
                        ColorPickerField(
                          currentColor: selectedColor,
                          onColorChanged: (newColor) {
                            setDialogState(() => selectedColor = newColor);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Button(label: "Cancel", variant: ButtonVariant.outline, onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Button(
                        label: "Create Tag",
                        onPressed: () async {
                          if (formKey.currentState?.validate() ?? false) {
                            final success = await _controller.createTag(nameController.text.trim(), selectedColor);
                            if (success && context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final wizard = _CreateGroupWizard(controller: _controller);

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650, maxHeight: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🚀 STANDARDIZED HEADER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Create Tag Group", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), splashRadius: 20),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // --- WIZARD CONTENT ---
                Expanded(child: wizard),
              ],
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🚀 MOBILE HEADER
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Create Tag Group", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: wizard),
            ],
          ),
        ),
      );
    }
  }

  void _showResponsiveManageSelection<T>({
    required String title,
    required List<T> allItems,
    required List<T> selectedItems,
    required String Function(T) getName,
    required String Function(T) getId,
    required void Function(List<T>) onSave,
  }) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final content = _ManageSelectionContent<T>(
      title: title, allItems: allItems, selectedItems: selectedItems,
      getName: getName, getId: getId, isDialog: isDesktop,
      onSave: (items) { onSave(items); Navigator.pop(context); },
    );

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.hardEdge, // 🚀 FIX: Keeps the header inside the rounded borders!
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650), child: content),
        ),
      );
    } else {
      showModalBottomSheet(
        useRootNavigator: true,
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer, 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
          ),
          clipBehavior: Clip.hardEdge, // 🚀 FIX: Clean borders on mobile too
          child: content, 
        ),
      );
    }
  }

  // ==========================================
  // MAIN BUILDER
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = AppResponsive.isDesktopScreen(context); 

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, child) {
        if (_controller.isLoading && _controller.tagGroups.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: const EdgeInsets.all(5.0),
          child: isDesktop 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Tag Management", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Row(
                        // 🚀 FIX 1: This MUST be stretch so the Row passes height down to the panels!
                        crossAxisAlignment: CrossAxisAlignment.stretch, 
                        children: [
                          Expanded(flex: 2, child: _buildTagGroupsList(theme, isDesktop: true)),
                          const SizedBox(width: 16),
                          Expanded(flex: 3, child: _buildSelectedGroupDetails(theme, isDesktop: true)),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: _buildGlobalTagsList(theme)),
                        ],
                      ),
                    ),
                  ],
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _buildMobileCurrentView(theme),
                ),
        );
      }
    );
  }

  Widget _buildMobileCurrentView(ThemeData theme) {
    switch (_currentMobileView) {
      case MobileView.groups:
        return Column(
          key: const ValueKey('groups'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tag Management", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(child: _buildTagGroupsList(theme, isDesktop: false)),
          ],
        );
      case MobileView.groupDetails:
        return Column(
          key: const ValueKey('details'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMobileHeader(_controller.tagGroups.where((g) => g.id == _selectedGroupId).firstOrNull?.name ?? "Details"),
            Expanded(child: _buildSelectedGroupDetails(theme, isDesktop: false)),
          ],
        );
      case MobileView.allTags:
        return Column(
          key: const ValueKey('all_tags'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMobileHeader("All Tags"),
            Expanded(child: _buildGlobalTagsList(theme)),
          ],
        );
    }
  }

  // --- PANELS ---

  Widget _buildTagGroupsList(ThemeData theme, {required bool isDesktop}) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Tag Groups", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), color: theme.colorScheme.primary, onPressed: _showCreateGroupDialog)
              ],
            ),
          ),
          const Divider(height: 1),
          
          if (!isDesktop) ...[
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.local_offer, color: theme.colorScheme.primary, size: 20),
              ),
              title: const Text("Manage All Tags", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${_controller.globalTags.length} total tags available"),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () => setState(() => _currentMobileView = MobileView.allTags),
            ),
            const Divider(height: 1, thickness: 4), 
          ],

          Expanded(
            child: _controller.tagGroups.isEmpty
              ? const Center(child: Text("No groups found.", style: TextStyle(color: Colors.grey)))
              // 🚀 FIX 2: Removed shrinkWrap and NeverScrollablePhysics so it natively scrolls
              : ListView.separated(
                  itemCount: _controller.tagGroups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final group = _controller.tagGroups[index];
                    final isSelected = isDesktop && _selectedGroupId == group.id; 
                    
                    return ListTile(
                      title: Text(group.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text("${group.tags.length} Tags • ${group.templates.length} Templates", style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
                      onTap: () {
                        setState(() {
                          _selectedGroupId = group.id;
                          if (!isDesktop) _currentMobileView = MobileView.groupDetails; 
                        });
                        _controller.fetchTemplatesForGroup(group.id);
                      },
                      trailing: const Icon(Icons.chevron_right, size: 16),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedGroupDetails(ThemeData theme, {required bool isDesktop}) {
    final activeGroup = _controller.tagGroups.where((g) => g.id == _selectedGroupId).firstOrNull;

    if (activeGroup == null) {
      return const AppCard(
        padding: EdgeInsets.all(40),
        child: Center(child: Text("Select a Tag Group to view details")),
      );
    }

    if (_controller.isGroupDetailsLoading) {
      return AppCard(
        padding: const EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop) ...[
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surface,
              child: Text(activeGroup.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
          ],
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Assigned Tags", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Button(
                        label: "Manage Tags",
                        icon: Icons.edit,
                        variant: ButtonVariant.outline,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onPressed: () => _showResponsiveManageSelection<AppTag>(
                          title: "Manage Tags for ${activeGroup.name}",
                          allItems: _controller.globalTags, 
                          selectedItems: activeGroup.tags,
                          getName: (t) => t.name, 
                          getId: (t) => t.id,
                          onSave: (selected) => setState(() => activeGroup.tags = selected),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  activeGroup.tags.isEmpty 
                    ? const Text("No tags assigned.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                    : Wrap(spacing: 8, runSpacing: 8, children: activeGroup.tags.map((t) => _buildTagChip(t)).toList()),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Assigned Templates", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Button(
                        label: "Manage Templates",
                        icon: Icons.edit,
                        variant: ButtonVariant.outline,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        onPressed: () => _showResponsiveManageSelection<AppTemplate>(
                          title: "Manage Templates for ${activeGroup.name}",
                          allItems: _controller.globalTemplates, 
                          selectedItems: activeGroup.templates,
                          getName: (t) => t.name, 
                          getId: (t) => t.id,
                          onSave: (selected) => setState(() => activeGroup.templates = selected),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  activeGroup.templates.isEmpty 
                    ? const Text("No templates assigned.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                    : ListView.builder(
                        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        itemCount: activeGroup.templates.length,
                        itemBuilder: (context, index) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.description_outlined, color: theme.colorScheme.onSurfaceVariant),
                          title: Text(activeGroup.templates[index].name),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalTagsList(ThemeData theme) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("All Tags", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle_outline), color: theme.colorScheme.primary, onPressed: _showCreateTagDialog)
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _controller.globalTags.isEmpty 
                ? const Text("No tags found.")
                : Wrap(spacing: 8, runSpacing: 8, children: _controller.globalTags.map((t) => _buildTagChip(t)).toList()),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: undefined_class
  Widget _buildTagChip(AppTag tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tag.color.withOpacity(0.1), border: Border.all(color: tag.color.withOpacity(0.5)), borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(tag.name, style: TextStyle(color: tag.color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ==========================================
// SELECTION COMPONENTS 
// ==========================================
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

class _ManageSelectionContent<T> extends StatefulWidget {
  final String title;
  final List<T> allItems;
  final List<T> selectedItems;
  final String Function(T) getName;
  final String Function(T) getId;
  final void Function(List<T>) onSave;
  final bool isDialog;

  const _ManageSelectionContent({
    required this.title, required this.allItems, required this.selectedItems,
    required this.getName, required this.getId, required this.onSave, required this.isDialog,
  });

  @override
  State<_ManageSelectionContent<T>> createState() => _ManageSelectionContentState<T>();
}

class _ManageSelectionContentState<T> extends State<_ManageSelectionContent<T>> {
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
        // 🚀 STANDARDIZED HEADER
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: theme.colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              // 🚀 Always show the close button now!
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), splashRadius: 20),
            ],
          ),
        ),
        const Divider(height: 1),
        
        // --- CONTENT ---
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
        
        // --- FOOTER ---
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

// ==========================================
// 3. CREATE GROUP WIZARD (STEPPER)
// ==========================================
class _CreateGroupWizard extends StatefulWidget {
  final TagController controller;
  const _CreateGroupWizard({required this.controller});

  @override
  State<_CreateGroupWizard> createState() => _CreateGroupWizardState();
}

class _CreateGroupWizardState extends State<_CreateGroupWizard> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  Set<String> _selectedTagIds = {};
  Set<String> _selectedTemplateIds = {};

  void _onStepContinue() async {
    if (_currentStep == 0 && !(_formKey.currentState?.validate() ?? false)) return;

    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
    } else {
      final success = await widget.controller.createTagGroup(
        name: _nameController.text.trim(), tagIds: _selectedTagIds.toList(), templateIds: _selectedTemplateIds.toList(),
      );
      if (success && mounted) Navigator.pop(context);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) setState(() => _currentStep -= 1);
    else Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppResponsive.isDesktopScreen(context);

    return Form(
      key: _formKey,
      child: Stepper(
        type: isDesktop ? StepperType.horizontal : StepperType.vertical,
        currentStep: _currentStep,
        elevation: 0,
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(label: _currentStep == 0 ? "Cancel" : "Back", variant: ButtonVariant.outline, onPressed: _onStepCancel),
              const SizedBox(width: 12),
              Button(label: _currentStep == 2 ? "Create Group" : "Continue", onPressed: _onStepContinue),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text("Details"), isActive: _currentStep >= 0, state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Group Name", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                FormControlTextField(controller: _nameController, hintText: "Enter group name...", prefixIcon: Icons.folder_outlined, validator: (val) => (val == null || val.trim().isEmpty) ? "Group name is required" : null),
              ],
            ),
          ),
          Step(
            title: const Text("Tags"), isActive: _currentStep >= 1, state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: SizedBox(
              height: 350,
              child: InlineSelectionFilter<AppTag>(
                allItems: widget.controller.globalTags, selectedIds: _selectedTagIds, getName: (t) => t.name, getId: (t) => t.id,
                onToggle: (id, isSelected) => setState(() => isSelected ? _selectedTagIds.add(id) : _selectedTagIds.remove(id)),
              ),
            ),
          ),
          Step(
            title: const Text("Templates"), isActive: _currentStep >= 2,
            content: SizedBox(
              height: 350,
              child: InlineSelectionFilter<AppTemplate>(
                allItems: widget.controller.globalTemplates, selectedIds: _selectedTemplateIds, getName: (t) => t.name, getId: (t) => t.id,
                onToggle: (id, isSelected) => setState(() => isSelected ? _selectedTemplateIds.add(id) : _selectedTemplateIds.remove(id)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}