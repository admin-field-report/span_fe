import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'inspections/project_inspections.dart';
import 'documents/project_documents.dart';
import 'reports/project_reports.dart';
import './widgets/project_medias.dart';
import '../../widgets/tab/tab.dart';
import '../../core/api_service.dart';

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
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  final List<String> _sections = ['inspections', 'documents', 'media', 'reports'];
  
  String _projectName = "Loading...";
  bool _isLoadingProjectName = true;

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

    _fetchProjectDetails();
  }

  Future<void> _fetchProjectDetails() async {
    try {
      final response = await _apiService.get('/project/${widget.projectId}');
      final resData = jsonDecode(response.body);

      if (resData['success'] == true && resData['data'] != null) {
        if (mounted) {
          setState(() {
            // Adjust the key ('name' or 'project_name') based on your exact API response structure
            _projectName = resData['data']['name'] ?? 'Unnamed Project';
            _isLoadingProjectName = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _projectName = 'Unknown Project';
            _isLoadingProjectName = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching project details: $e");
      if (mounted) {
        setState(() {
          _projectName = 'Error loading project';
          _isLoadingProjectName = false;
        });
      }
    }
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
                  child: Row(
                    children: [
                      // 🚀 NEW: Replaced static text with the dynamic state variable
                      Text(
                        _projectName, 
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)
                      ),
                      // Optional: Show a tiny spinner next to the text while it loads
                      if (_isLoadingProjectName) ...[
                        const SizedBox(width: 12),
                        const SizedBox(
                          width: 12, 
                          height: 12, 
                          child: CircularProgressIndicator(strokeWidth: 2)
                        )
                      ]
                    ],
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