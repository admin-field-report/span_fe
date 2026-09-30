import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../widgets/button/button.dart';
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../models/tag_models.dart';
import '../../../utils/app_responsive.dart';
import '../../tools/models/tool_group.dart';
import '../../canvas/widgets/custom_tools_panel.dart' show CenteredPreviewPainter;
import '../controllers/project_setting_controller.dart';
import '../../../services/toast_service.dart';

/// Which selection the manager shows. `null` shows both as tabs.
enum ProjectSettingsMode { tags, tools }

enum _ManagerResult { saved, createTagGroup, createToolSet }

class ProjectSettingsManager extends StatefulWidget {
  final String projectId;
  final ProjectSettingsMode? mode;

  const ProjectSettingsManager({
    super.key,
    required this.projectId,
    this.mode,
  });

  /// Opens the manager as a dialog (desktop) or bottom sheet (mobile).
  /// Returns true when the project's tag groups / tool sets may have changed.
  /// [confirmCreate] runs before navigating to a create page; returning false cancels it.
  static Future<bool> show(
    BuildContext context, {
    required String projectId,
    ProjectSettingsMode? mode,
    Future<bool> Function(ProjectSettingsMode mode)? confirmCreate,
  }) async {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final theme = Theme.of(context);
    final router = GoRouter.of(context);
    final managerWidget = ProjectSettingsManager(projectId: projectId, mode: mode);

    _ManagerResult? result;
    if (isDesktop) {
      result = await showDialog<_ManagerResult>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: managerWidget,
            ),
          ),
        ),
      );
    } else {
      result = await showModalBottomSheet<_ManagerResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: managerWidget,
          ),
        ),
      );
    }

    // Navigate only after the dialog closes, otherwise the page would open beneath it.
    // go() (not push) so the browser URL reflects the new page.
    switch (result) {
      case _ManagerResult.createTagGroup:
        if (confirmCreate != null && !await confirmCreate(ProjectSettingsMode.tags)) return false;
        router.go('/templates/tags');
        return true;
      case _ManagerResult.createToolSet:
        if (confirmCreate != null && !await confirmCreate(ProjectSettingsMode.tools)) return false;
        router.go('/templates/tools');
        return true;
      case _ManagerResult.saved:
        return true;
      case null:
        return false;
    }
  }

  @override
  State<ProjectSettingsManager> createState() => _ProjectSettingsManagerState();
}

class _ProjectSettingsManagerState extends State<ProjectSettingsManager> with SingleTickerProviderStateMixin {
  TabController? _tabController;

  late final List<ProjectSettingsMode> _modes =
      widget.mode != null ? [widget.mode!] : ProjectSettingsMode.values;

  bool _isLoading = true;
  bool _isSaving = false;

  bool _tagsLoaded = false;
  bool _toolsLoaded = false;

  List<AppTagGroup> _allTagGroups = [];
  List<ToolGroup> _allToolGroups = [];

  // Parsed tool drawings of each tool set, keyed by group id.
  final Map<String, List<List<DrawingObject>>> _toolPreviews = {};

  List<String> _initialTagIds = [];
  List<String> _initialToolIds = [];

  List<String> _selectedTagIds = [];
  List<String> _selectedToolIds = [];

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  ProjectSettingsMode get _activeMode => _modes[_tabController?.index ?? 0];

  @override
  void initState() {
    super.initState();
    if (_modes.length > 1) {
      _tabController = TabController(length: _modes.length, vsync: this);
      _tabController!.addListener(_handleTabSelection);
    }
    _loadDataFor(_activeMode);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController!.indexIsChanging) return;

    setState(() {
      _searchQuery = '';
      _searchController.clear();
    });
    _loadDataFor(_activeMode);
  }

  void _loadDataFor(ProjectSettingsMode mode) {
    mode == ProjectSettingsMode.tags ? _loadTagsData() : _loadToolsData();
  }

  Future<void> _loadTagsData() async {
    if (_tagsLoaded) return;
    setState(() => _isLoading = true);

    final tagGroups = await projectController.getCompanyTagGroups();
    await projectController.fetchProjectTags(widget.projectId);

    if (mounted) {
      setState(() {
        _allTagGroups = tagGroups;
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

    final toolGroups = await projectController.getCompanyToolGroups();
    await projectController.fetchProjectTools(widget.projectId);

    if (mounted) {
      setState(() {
        _allToolGroups = toolGroups;
        for (final group in toolGroups) {
          _toolPreviews[group.id] = group.tools.map((t) => _parseToolObjects(t.canvasJson)).toList();
        }
        _initialToolIds = List.from(projectController.assignedToolGroupIds);
        _selectedToolIds = List.from(_initialToolIds);
        _toolsLoaded = true;
        _isLoading = false;
      });
    }
  }

  List<DrawingObject> _parseToolObjects(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      List<dynamic> rawObjects = [];
      if (decoded is List) {
        rawObjects = decoded;
      } else if (decoded is Map) {
        rawObjects = (decoded['objects'] is List) ? decoded['objects'] : [decoded];
      }
      return rawObjects.map((json) => DrawingObject.fromJson(json as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  bool _hasChanged(List<String> initial, List<String> current) =>
      initial.length != current.length || !initial.toSet().containsAll(current);

  bool get _tagsChanged => _tagsLoaded && _hasChanged(_initialTagIds, _selectedTagIds);
  bool get _toolsChanged => _toolsLoaded && _hasChanged(_initialToolIds, _selectedToolIds);

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final saved = <String>[];
    final failures = <String>[];

    if (_tagsChanged) {
      final success = await projectController.manageProjectTagGroups(widget.projectId, _initialTagIds, _selectedTagIds);
      if (success) {
        projectController.assignedTagGroupIds = List.from(_selectedTagIds);
        _initialTagIds = List.from(_selectedTagIds);
        saved.add("Tag Group");
      } else {
        failures.add("Tag Group");
      }
    }

    if (_toolsChanged) {
      final success = await projectController.manageProjectToolGroups(widget.projectId, _initialToolIds, _selectedToolIds);
      if (success) {
        projectController.assignedToolGroupIds = List.from(_selectedToolIds);
        _initialToolIds = List.from(_selectedToolIds);
        saved.add("Tool Group");
      } else {
        failures.add("Tool Group");
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (failures.isEmpty) {
      ToastService.show(context, message: "${saved.join(' & ')} assigned successfully!", type: ToastType.success);
      Navigator.pop(context, _ManagerResult.saved);
    } else {
      ToastService.show(context, message: "Failed to assign ${failures.join(' & ')}!", type: ToastType.error);
    }
  }

  // ==========================================
  // COPY
  // ==========================================

  bool get _isTags => _activeMode == ProjectSettingsMode.tags;

  String get _title => _isTags ? "Add Tag Groups to this project" : "Add Tool Sets to this project";

  String get _subtitle => _isTags
      ? "Tags from these groups show up under Inspection Details. You can change this later."
      : "Tools from these sets show up under Custom Tools. You can change this later.";

  String get _searchHint => _isTags ? "Search Tag Groups and Tags" : "Search Tool Sets and Tools";

  bool get _hasNoData => !_isLoading && (_isTags ? _allTagGroups.isEmpty : _allToolGroups.isEmpty);

  List<String> get _activeSelection => _isTags ? _selectedTagIds : _selectedToolIds;

  String get _saveLabel {
    final count = _activeSelection.length;
    if (_modes.length > 1 || count == 0) return "Save Changes";
    final noun = _isTags ? "Tag Group" : "Tool Set";
    return "Add $count $noun${count == 1 ? '' : 's'}";
  }

  // ==========================================
  // BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = !_isLoading && !_isSaving && (_tagsChanged || _toolsChanged);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          if (!_hasNoData) const Divider(height: 1),
          Flexible(
            child: AbsorbPointer(
              absorbing: _isSaving,
              child: _isLoading
                  ? _buildLoadingState(theme)
                  : _hasNoData
                      ? _buildNoDataState(theme)
                      : _buildList(theme),
            ),
          ),
          const Divider(height: 1),
          _buildFooter(theme, canSave),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: _isSaving ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          if (_tabController != null) ...[
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.only(right: 24),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: theme.colorScheme.onSurface, width: 3.0),
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
          ],
          if (!_hasNoData) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: _searchHint,
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
              prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final cards = _isTags ? _buildTagGroupCards(theme) : _buildToolSetCards(theme);

    if (cards.isEmpty) {
      return SizedBox(
        width: double.infinity,
        height: 200,
        child: Center(
          child: Text(
            "No results found.",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) => cards[index],
    );
  }

  List<Widget> _buildTagGroupCards(ThemeData theme) {
    final groups = _allTagGroups.where((group) {
      if (_searchQuery.isEmpty) return true;
      return group.name.toLowerCase().contains(_searchQuery) ||
          group.tags.any((t) => t.name.toLowerCase().contains(_searchQuery));
    });

    return groups.map((group) {
      final isSelected = _selectedTagIds.contains(group.id);
      return _SelectableCard(
        title: group.name,
        countLabel: "${group.tags.length} Tag${group.tags.length == 1 ? '' : 's'}",
        isSelected: isSelected,
        onTap: () => setState(() => isSelected ? _selectedTagIds.remove(group.id) : _selectedTagIds.add(group.id)),
        child: group.tags.isEmpty
            ? null
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: group.tags.map((tag) => _TagChip(tag: tag)).toList(),
              ),
      );
    }).toList();
  }

  List<Widget> _buildToolSetCards(ThemeData theme) {
    final groups = _allToolGroups.where((group) {
      if (_searchQuery.isEmpty) return true;
      return group.name.toLowerCase().contains(_searchQuery) ||
          group.tools.any((t) => t.name.toLowerCase().contains(_searchQuery));
    });

    return groups.map((group) {
      final isSelected = _selectedToolIds.contains(group.id);
      final previews = _toolPreviews[group.id] ?? const [];
      return _SelectableCard(
        title: group.name,
        countLabel: "${previews.length} Tool${previews.length == 1 ? '' : 's'}",
        isSelected: isSelected,
        onTap: () => setState(() => isSelected ? _selectedToolIds.remove(group.id) : _selectedToolIds.add(group.id)),
        child: previews.isEmpty ? null : _ToolPreviewRow(previews: previews),
      );
    }).toList();
  }

  Widget _buildFooter(ThemeData theme, bool canSave) {
    final noun = _isTags ? "Tag Group" : "Tool Set";
    final cancelButton = Button(
      label: "Cancel",
      variant: ButtonVariant.outline,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: _isSaving ? null : () => Navigator.pop(context),
    );

    if (_hasNoData) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
        child: Align(alignment: Alignment.centerRight, child: cancelButton),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      child: Row(
        children: [
          Button(
            label: "Create new $noun",
            icon: Icons.add,
            variant: ButtonVariant.text,
            onPressed: _isSaving
                ? null
                : () => Navigator.pop(context, _isTags ? _ManagerResult.createTagGroup : _ManagerResult.createToolSet),
          ),
          const Spacer(),
          if (!_isLoading)
            Text(
              "${_activeSelection.length} selected",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(width: 12),
          cancelButton,
          const SizedBox(width: 8),
          Button(
            label: _saveLabel,
            variant: ButtonVariant.filled,
            isLoading: _isSaving,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onPressed: canSave ? _handleSave : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataState(ThemeData theme) {
    final noun = _isTags ? "Tag Group" : "Tool Set";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              _isTags ? Icons.sell_outlined : Icons.category_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "You don't have any ${noun}s yet",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            "${noun}s are created on the ${noun}s page. Create one there, then add it to this project.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Button(
            label: "Create a $noun",
            icon: Icons.add,
            variant: ButtonVariant.filled,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onPressed: () => Navigator.pop(context, _isTags ? _ManagerResult.createTagGroup : _ManagerResult.createToolSet),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 280,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            "Fetching project data...",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// CARD & CONTENT WIDGETS
// ==========================================

class _SelectableCard extends StatelessWidget {
  final String title;
  final String? countLabel;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? child;

  const _SelectableCard({
    required this.title,
    required this.countLabel,
    required this.isSelected,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(10);
    final isDark = theme.brightness == Brightness.dark;
    final checkboxColor = isDark ? Colors.white : Colors.black;

    return Material(
      color: isSelected ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5) : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                visualDensity: VisualDensity.compact,
                // Explicit colours so the app's checkbox theme can't hide it in dark mode.
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? checkboxColor : Colors.transparent,
                ),
                checkColor: isDark ? Colors.black : Colors.white,
                side: WidgetStateBorderSide.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.selected) ? checkboxColor : checkboxColor.withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (countLabel != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              countLabel!,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (child != null) ...[
                      const SizedBox(height: 8),
                      child!,
                    ],
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

class _TagChip extends StatelessWidget {
  final AppTag tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    // Darken the tag colour for text so light colours (e.g. yellow) stay readable.
    final textColor = Color.lerp(tag.color, Colors.black, 0.25)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tag.color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(tag.name, style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ToolPreviewRow extends StatelessWidget {
  final List<List<DrawingObject>> previews;

  static const double _tileWidth = 44;
  static const double _tileHeight = 44;
  static const double _spacing = 6;

  const _ToolPreviewRow({required this.previews});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit as many tiles as the card allows, reserving room for the "+N" label.
        const overflowLabelWidth = 28.0;
        final fitCount = ((constraints.maxWidth + _spacing) / (_tileWidth + _spacing)).floor();
        final visibleCount = previews.length <= fitCount
            ? previews.length
            : ((constraints.maxWidth - overflowLabelWidth + _spacing) / (_tileWidth + _spacing)).floor().clamp(0, previews.length);
        final hiddenCount = previews.length - visibleCount;

        return Row(
          children: [
            for (int i = 0; i < visibleCount; i++) ...[
              if (i > 0) const SizedBox(width: _spacing),
              Container(
                width: _tileWidth,
                height: _tileHeight,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  // Same thumbnail treatment as the canvas Custom Tools panel so tools read the same.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.hardEdge,
                child: previews[i].isEmpty
                    ? const Icon(Icons.extension_outlined, size: 18, color: Colors.grey)
                    : IgnorePointer(
                        child: SizedBox.expand(
                          child: CustomPaint(painter: CenteredPreviewPainter(context, previews[i])),
                        ),
                      ),
              ),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                "+$hiddenCount",
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        );
      },
    );
  }
}
