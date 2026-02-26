import 'package:field_report_fe/screens/projects/widgets/project_documents.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/widgets.dart';
import 'widgets/project_inspections.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final String initialSection;

  const ProjectDetailsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.initialSection,
  });

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _sections = ['inspections', 'documents', 'media', 'reports'];

  @override
  void initState() {
    super.initState();
    // Calculate initial index based on URL
    int initialIndex = _sections.indexOf(widget.initialSection);
    _tabController = TabController(
      length: _sections.length, 
      vsync: this, 
      initialIndex: initialIndex != -1 ? initialIndex : 0,
    );

    // Update URL whenever the tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _updateUrl();
      }
    });
  }

  void _updateUrl() {
    final section = _sections[_tabController.index];
    final name = Uri.encodeComponent(widget.projectName);
    context.go('/projects/details/${widget.projectId}/$name/$section');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. Header with Back Button ---
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => context.pop(),
                  tooltip: "Back to Projects",
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.projectName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      // Text(
                      //   "ID: ${widget.projectId}",
                      //   style: theme.textTheme.bodySmall?.copyWith(
                      //     color: colorScheme.onSurfaceVariant,
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // --- 2. Tab Bar ---
          AppTabBar(
            controller: _tabController,
            tabs: _sections.map((s) => s.toUpperCase()).toList(),
            horizontalPadding: 24.0,
          ),

          // --- 3. Section Content ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ProjectInspectionsTab(projectId: widget.projectId),
                ProjectDocuments(projectId: widget.projectId),
                _buildPlaceholderTab("Project Media Gallery"),
                _buildPlaceholderTab("Analytics & Reports"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB CONTENT BUILDERS ---
  Widget _buildPlaceholderTab(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}