import 'package:flutter/material.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/search_field/search_field.dart';
import '../controllers/project_setting_controller.dart';
import '../../../services/toast_service.dart';

class ProjectSettingsManager extends StatefulWidget {
  final String projectId;

  const ProjectSettingsManager({
    super.key,
    required this.projectId,
  });

  @override
  State<ProjectSettingsManager> createState() => _ProjectSettingsManagerState();
}

class _ProjectSettingsManagerState extends State<ProjectSettingsManager> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _isLoading = true;
  bool _isSaving = false;

  bool _tagsLoaded = false;
  bool _toolsLoaded = false;

  List<Map<String, dynamic>> _allTags = [];
  List<Map<String, dynamic>> _allTools = [];

  List<String> _initialTagIds = [];
  List<String> _initialToolIds = [];

  List<String> _selectedTagIds = [];
  List<String> _selectedToolIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadTagsData(); 
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    
    setState(() {}); 

    if (_tabController.index == 0) {
      _loadTagsData();
    } else {
      _loadToolsData();
    }
  }

  Future<void> _loadTagsData() async {
    if (_tagsLoaded) return;
    setState(() => _isLoading = true);

    final tagsList = await projectController.getCompanyTagGroups();
    await projectController.fetchProjectTags(widget.projectId);

    if (mounted) {
      setState(() {
        _allTags = tagsList;
        
        // 🚀 Set the initial list, and clone it for the editable selected list
        _initialTagIds = List.from(projectController.assignedTagGroupIds);
        _selectedTagIds = List.from(_initialTagIds);
        
        _tagsLoaded = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadToolsData() async {
    if (_toolsLoaded) return;
    setState(() => _isLoading = true);

    final toolsList = await projectController.getCompanyToolGroups();
    await projectController.fetchProjectTools(widget.projectId);

    if (mounted) {
      setState(() {
        _allTools = toolsList;
        
        // 🚀 Set the initial list, and clone it for the editable selected list
        _initialToolIds = List.from(projectController.assignedToolGroupIds);
        _selectedToolIds = List.from(_initialToolIds);
        
        _toolsLoaded = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    bool success = false;
    String toastMessage = "";

    if (_tabController.index == 0) {
      success = await projectController.manageProjectTagGroups(widget.projectId, _initialTagIds, _selectedTagIds);
      if (success) {
        projectController.assignedTagGroupIds = List.from(_selectedTagIds);
        _initialTagIds = List.from(_selectedTagIds);
        toastMessage = "Project tag groups managed successfully";
      } else {
        toastMessage = "Failed to update tag groups";
      }
    } else {
      success = await projectController.manageProjectToolGroups(widget.projectId, _initialToolIds, _selectedToolIds);
      if (success) {
        projectController.assignedToolGroupIds = List.from(_selectedToolIds);
        _initialToolIds = List.from(_selectedToolIds);
        toastMessage = "Project tool sets managed successfully";
      } else {
        toastMessage = "Failed to update tool sets";
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ToastService.show(context, message: toastMessage, type: success ? ToastType.success : ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonTitle = _tabController.index == 0 ? "Save Tag Groups" : "Save Tool Sets";

    return Container(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        children: [
          // --- HEADER ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Manage Project", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  // 🚀 1. Disable close button while loading or saving
                  onPressed: (_isSaving || _isLoading) ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          Expanded(
            // 🚀 2. Wrap the interactive content in AbsorbPointer
            child: AbsorbPointer(
              absorbing: _isSaving, // Acts as an invisible shield blocking all clicks when saving
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.center,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.only(right: 24), 
                      dividerColor: Colors.transparent, 
                      indicatorSize: TabBarIndicatorSize.label, 
                      indicator: UnderlineTabIndicator(
                        borderSide: BorderSide(
                          color: theme.colorScheme.onSurface,
                          width: 3.0, 
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                      labelColor: theme.colorScheme.onSurface, 
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), 
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                      tabs: const [
                        Tab(height: 40, text: "Tag Groups"),
                        Tab(height: 40, text: "Tool Sets"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  
                  Expanded(
                    child: _isLoading 
                      ? _buildLoadingState(theme)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            ManageTabContent(
                              items: _allTags,
                              selectedIds: _selectedTagIds,
                              onChanged: (id, isSelected) {
                                setState(() {
                                  isSelected ? _selectedTagIds.add(id) : _selectedTagIds.remove(id);
                                });
                              },
                            ),
                            ManageTabContent(
                              items: _allTools,
                              selectedIds: _selectedToolIds,
                              onChanged: (id, isSelected) {
                                setState(() {
                                  isSelected ? _selectedToolIds.add(id) : _selectedToolIds.remove(id);
                                });
                              },
                            ),
                          ],
                        ),
                  ),
                ],
              ),
            ),
          ),
          
          // --- FOOTER ---
          const Divider(height: 0.5),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  label: "Cancel",
                  variant: ButtonVariant.outline,
                  // Cancel is disabled while loading or saving
                  onPressed: (_isSaving || _isLoading) ? null : () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Button(
                  label: buttonTitle,
                  variant: ButtonVariant.filled,
                  isLoading: _isSaving,
                  // 🚀 3. Prevent double-clicking the save button
                  onPressed: (_isLoading || _isSaving) ? null : _handleSave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Fetching project data...",
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 14,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class ManageTabContent extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<String> selectedIds;
  final Function(String, bool) onChanged;

  const ManageTabContent({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<ManageTabContent> createState() => _ManageTabContentState();
}

class _ManageTabContentState extends State<ManageTabContent> {
  String _searchQuery = '';
  String _filterState = 'All';

  List<Map<String, dynamic>> get _filteredItems {
    return widget.items.where((item) {
      final matchesSearch = item['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      final isSelected = widget.selectedIds.contains(item['id']);
      if (_filterState == 'Selected' && !isSelected) return false;
      if (_filterState == 'Unselected' && isSelected) return false;

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(
            hintText: 'Search...',
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildPill('All', theme),
              const SizedBox(width: 6),
              _buildPill('Selected (${widget.selectedIds.length})', theme, value: 'Selected'),
              const SizedBox(width: 6),
              _buildPill('Unselected', theme),
            ],
          ),
        ),
        const SizedBox(height: 15),
        const Divider(height: 0.5),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text("No items found.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final isSelected = widget.selectedIds.contains(item['id']);

                    return ListTile(
                      visualDensity: const VisualDensity(horizontal: 0, vertical: -4), 
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) => widget.onChanged(item['id'], val ?? false),
                      ),
                      onTap: () => widget.onChanged(item['id'], !isSelected),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPill(String label, ThemeData theme, {String? value}) {
    final actualValue = value ?? label;
    final isActive = _filterState == actualValue;

    return InkWell(
      onTap: () => setState(() => _filterState = actualValue),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary.withOpacity(0.15) : theme.colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11, 
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}