import 'package:field_report_fe/services/toast_service.dart';
import 'package:flutter/material.dart';
import '../../../widgets/form_components/text_field.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/card/card.dart';
import '../../../widgets/form_components/color_picker_field.dart';
import './controllers/tag_controller.dart';
import '../../../models/tag_models.dart';
import '../../utils/app_responsive.dart';

import 'widgets/manage_tags_dialog.dart';
import 'widgets/manage_templates_dialog.dart';
import 'widgets/create_group_wizard.dart';

enum MobileView { groups, groupDetails, allTags }
enum SortOrder { none, asc, desc }

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  final TagController _controller = TagController();
  
  final TextEditingController _groupSearchController = TextEditingController();
  final TextEditingController _tagSearchController = TextEditingController();
  
  SortOrder _tagSortOrder = SortOrder.none;
  String? _selectedGroupId;
  MobileView _currentMobileView = MobileView.groups;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fetchGroups();
      _controller.fetchTags();
      _controller.fetchTemplates();
    });
    
    _groupSearchController.addListener(() => setState(() {}));
    _tagSearchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _groupSearchController.dispose();
    _tagSearchController.dispose();
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
    Color selectedColor = const Color(0xFFC9D647);
    bool _isCreating = false; 

    showDialog(
      context: context,
      barrierDismissible: false,
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
                      Button(
                        label: "Cancel",
                        variant: ButtonVariant.outline,
                        onPressed: _isCreating ? null : () => Navigator.pop(context)
                      ),
                      const SizedBox(width: 12),
                      Button(
                        label: _isCreating ? "Creating..." : "Create Tag",
                        isLoading: _isCreating,
                        onPressed: _isCreating ? null : () async {
                          if (formKey.currentState?.validate() ?? false) {
                            setDialogState(() => _isCreating = true);

                            final success = await _controller.createTag(nameController.text.trim(), selectedColor);
                            
                            if (!context.mounted) return;
                            
                            if (success) {
                              Navigator.pop(context);
                              ToastService.show(context, message: "Tag created successfully!", type: ToastType.success);
                            } else {
                              ToastService.show(context, message: "Failed to create tag", type: ToastType.error);
                            }
                            setDialogState(() => _isCreating = false);
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

  Future<void> _showCreateGroupDialog() async {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    
    // 🚀 Updated to use the public CreateGroupWizard class from the new file
    final wizard = CreateGroupWizard(controller: _controller);

    String? newGroupId;
    if (isDesktop) {
      newGroupId = await showDialog<String>(
        context: context,
        barrierDismissible: false,
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
                Expanded(child: wizard),
              ],
            ),
          ),
        ),
      );
    } else {
     newGroupId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        isDismissible: false,
        enableDrag: false,
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
    
    if (newGroupId != null && mounted) {
      setState(() {
        _selectedGroupId = newGroupId;
        _groupSearchController.clear();
        
        if (!isDesktop) {
          _currentMobileView = MobileView.groupDetails;
        }
      });
      _controller.fetchTemplatesForGroup(newGroupId);
    }
  }

  Future<void> _showManageTagsDialog(Set<String> currentTagIds) async {
    if (_selectedGroupId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManageTagsDialog(
        controller: _controller,
        initialSelectedIds: currentTagIds,
        
        onSave: (updatedTagIds, newTagsToCreate) async {
          final success = await _controller.updateGroupTags(
            groupId: _selectedGroupId!, 
            tagIds: updatedTagIds, 
            newTags: newTagsToCreate,
          );
          
          if (!context.mounted) return false;

          if (success) {
            ToastService.show(context, message: "Tags updated successfully!", type: ToastType.success);
            return true;
          } else {
            ToastService.show(context, message: "Failed to update tags", type: ToastType.error);
            return false;
          }
        },
      ),
    );
  }

  Future<void> _showManageTemplatesDialog(Set<String> currentTemplateIds) async {
    if (_selectedGroupId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManageTemplatesDialog(
        controller: _controller,
        initialSelectedIds: currentTemplateIds,
        
        onSave: (updatedTemplateIds) async {
          final success = await _controller.updateGroupTemplates(
            groupId: _selectedGroupId!, 
            templateIds: updatedTemplateIds, 
          );
          
          if (!context.mounted) return false;

          if (success) {
            ToastService.show(context, message: "Templates updated successfully!", type: ToastType.success);
            return true; 
          } else {
            ToastService.show(context, message: "Failed to update templates", type: ToastType.error);
            return false; 
          }
        },
      ),
    );
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
    final query = _groupSearchController.text.toLowerCase();
    final filteredGroups = _controller.tagGroups.where((g) {
      return g.name.toLowerCase().contains(query);
    }).toList();

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
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              height: 45, 
              child: FormControlTextField(
                controller: _groupSearchController,
                hintText: "Search groups...",
                prefixIcon: Icons.search,
              ),
            ),
          ),
          const Divider(height: 1),
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
            // 🚀 REMOVED the isEmpty check here!
            child: _controller.isGroupsLoading 
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : filteredGroups.isEmpty
                  ? const Center(child: Text("No groups match search.", style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                  itemCount: filteredGroups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final group = filteredGroups[index];
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

    final Set<String> currentTagIds = activeGroup.tags.map((t) => t.id).toSet();

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
                        onPressed: () => _showManageTagsDialog(currentTagIds), 
                        
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
                        
                        onPressed: () {
                          final Set<String> currentTemplateIds = activeGroup.templates.map((t) => t.id).toSet();
                          _showManageTemplatesDialog(currentTemplateIds);
                        },
                        
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
    final query = _tagSearchController.text.toLowerCase();
    var filteredTags = _controller.globalTags.where((t) {
      return t.name.toLowerCase().contains(query);
    }).toList();

    // 🚀 Apply the 3-state sorting logic
    if (_tagSortOrder != SortOrder.none) {
      filteredTags.sort((a, b) {
        final comp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return _tagSortOrder == SortOrder.asc ? comp : -comp;
      });
    }

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

          // 🚀 All Tags Search & Sort Row
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 45, // 🚀 Forces a compact height!
                    child: FormControlTextField(
                      controller: _tagSearchController,
                      hintText: "Search tags...",
                      prefixIcon: Icons.search,
                    ),
                  ),
                ),
                const SizedBox(width: 8), 
                
                // 🚀 Borderless, Icon-Only Sorting Button
                Container(
                  decoration: BoxDecoration(
                    color: _tagSortOrder == SortOrder.none 
                        ? Colors.transparent 
                        : theme.colorScheme.primaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    tooltip: "Toggle Sort Order",
                    onPressed: () {
                      setState(() {
                        if (_tagSortOrder == SortOrder.none) _tagSortOrder = SortOrder.asc;
                        else if (_tagSortOrder == SortOrder.asc) _tagSortOrder = SortOrder.desc;
                        else _tagSortOrder = SortOrder.none;
                      });
                    },
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 20),
                        const SizedBox(width: 2),
                        Icon(
                          _tagSortOrder == SortOrder.none 
                              ? Icons.unfold_more 
                              : (_tagSortOrder == SortOrder.asc ? Icons.arrow_downward : Icons.arrow_upward), 
                          size: 16, 
                        ),
                      ],
                    ),
                    color: _tagSortOrder == SortOrder.none 
                        ? theme.colorScheme.onSurfaceVariant 
                        : theme.colorScheme.primary,
                  ),
                )
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            // 🚀 REMOVED the isEmpty check here! It now spins on EVERY fetch.
            child: _controller.isTagsLoading 
              ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: filteredTags.isEmpty 
                    ? const Text("No tags match search.", style: TextStyle(color: Colors.grey))
                    : Wrap(spacing: 8, runSpacing: 8, children: filteredTags.map((t) => _buildTagChip(t)).toList()),
                ),
          ),
        ],
      ),
    );
  }

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