import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'inspections/project_inspections.dart';
import 'documents/project_documents.dart';
import 'reports/project_reports.dart';
import './widgets/project_medias.dart';
import '../../widgets/tab/tab.dart';
import '../../core/api_service.dart';
import './widgets/edit_project_form.dart'; 
import '../../utils/utils.dart';

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
  String? _clientName;
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
            _projectName = resData['data']['name'] ?? 'Unnamed Project';
            
            if (resData['data']['client'] != null && resData['data']['client']['name'] != null) {
              _clientName = resData['data']['client']['name'];
            } else {
              _clientName = null;
            }
            
            _isLoadingProjectName = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _projectName = 'Unknown Project';
            _clientName = null;
            _isLoadingProjectName = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching project details: $e");
      if (mounted) {
        setState(() {
          _projectName = 'Error loading project';
          _clientName = null;
          _isLoadingProjectName = false;
        });
      }
    }
  }

  // 🚀 NEW: Method to open the Edit form and refresh data upon saving
  Future<void> _showEditProject() async {
    final bool isDesktop = AppResponsive.isDesktopScreen(context);
    bool? isUpdated = false;

    if (isDesktop) {
      isUpdated = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: EditProjectForm(projectId: widget.projectId),
          ),
        ),
      );
    } else {
      isUpdated = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => EditProjectForm(projectId: widget.projectId),
      );
    }

    // If the form returned true (meaning a successful save), re-fetch the details!
    if (isUpdated == true) {
      setState(() => _isLoadingProjectName = true);
      _fetchProjectDetails();
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
        // 🚀 IMPORTANT: The parent Column MUST NOT be MainAxisSize.min if it contains an Expanded!
        // Changed to .max so it fills the screen and allows the Expanded child to work.
        mainAxisSize: MainAxisSize.max, 
        children: [
          // 🚀 HEADER SECTION
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, 
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4), 
                
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        Text(
                          _projectName, 
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (_isLoadingProjectName) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 14, height: 14, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                          )
                        ] else ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _showEditProject,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.edit_outlined, 
                                size: 20, 
                                color: theme.colorScheme.primary
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                    
                    if (_clientName != null && _clientName!.isNotEmpty && !_isLoadingProjectName) ...[
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_outline, 
                            size: 13, 
                            color: theme.colorScheme.onSurfaceVariant
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _clientName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                            ),
                          ),
                        ],
                      )
                    ],
                  ],
                ),
              ],
            ),
          ),

          AppTabBar(
            controller: _tabController,
            tabs: _sections.map((s) => s.toUpperCase()).toList(),
            horizontalPadding: 24.0,
          ),

          // 🚀 THE FIX: Wrapped the Tab content in Expanded!
          Expanded(
            child: Padding(
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
          ),
        ],
      ),
    );
  }
}