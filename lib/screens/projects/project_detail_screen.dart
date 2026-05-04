import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'inspections/project_inspections.dart';
import 'documents/project_documents.dart';
import 'reports/project_reports.dart';
import './widgets/project_medias.dart';
import '../../widgets/tab/tab.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String projectId;
  final String initialSection;

  const ProjectDetailsScreen({
    super.key,
    required this.projectId,
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
    int initialIndex = _sections.indexOf(widget.initialSection);
    _tabController = TabController(
      length: _sections.length, 
      vsync: this, 
      initialIndex: initialIndex != -1 ? initialIndex : 0,
    );

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _updateUrl();
      }
    });
  }

  void _updateUrl() {
    final section = _sections[_tabController.index];
    context.go('/projects/details/${widget.projectId}/$section');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

 @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Project Name Here', 
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)
                  ),
                ),
              ],
            ),
          ),


          AppTabBar(
            controller: _tabController,
            tabs: _sections.map((s) => s.toUpperCase()).toList(),
            horizontalPadding: 24.0,
          ),


          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: ListenableBuilder(
              listenable: _tabController,
              builder: (context, _) {
                switch (_tabController.index) {
                  case 0:
                    return ProjectInspectionsTab(projectId: widget.projectId);
                  case 1:
                    return ProjectDocuments(projectId: widget.projectId);
                  case 2:
                    return ProjectMediaTab(projectId: widget.projectId);
                  case 3:
                    return ProjectReports(projectId: widget.projectId);
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}