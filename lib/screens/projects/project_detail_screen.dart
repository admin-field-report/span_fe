import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'inspections/project_inspections.dart';
import 'documents/project_documents.dart';
import 'reports/project_reports.dart';
import './widgets/project_medias.dart';
import './widgets/project_settings.dart';
import '../../widgets/tab/tab.dart';
import '../../core/api_service.dart';
import '../../utils/utils.dart';
import './widgets/add_project_form.dart'; 
import '../../models/project.dart';

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
  
  // 🚀 STORE THE FULL PROJECT OBJECT IN STATE
  Project? _currentProject;
  
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
            _currentProject = Project.fromJson(resData['data']);
            
            _projectName = _currentProject!.name;
            _clientName = _currentProject!.clientName.isNotEmpty ? _currentProject!.clientName : null;
            
            _isLoadingProjectName = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _projectName = 'Unknown Project';
            _clientName = null;
            _currentProject = null;
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
          _currentProject = null;
          _isLoadingProjectName = false;
        });
      }
    }
  }

  Future<void> _showEditProject() async {
    if (_currentProject == null) return; // Safety check

    final bool isDesktop = AppResponsive.isDesktopScreen(context);
    bool? isUpdated = false;

    if (isDesktop) {
      isUpdated = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: AddProjectForm(
              isDesktop: true, 
              project: _currentProject, // 🚀 TRIGGERS EDIT MODE
            ),
          ),
        ),
      );
    } else {
      isUpdated = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => AddProjectForm(
          isDesktop: false, 
          project: _currentProject, // 🚀 TRIGGERS EDIT MODE
        ),
      );
    }
    setState(() => _isLoadingProjectName = true);
    _fetchProjectDetails();
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

  void _openProjectSettings(BuildContext context, String projectId) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final theme = Theme.of(context);
    
    final managerWidget = ProjectSettingsManager(projectId: projectId);

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
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
      showModalBottomSheet(
        context: context,
        isScrollControlled: true, 
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max, 
        children: [
          _buildHeader(context, theme),

          AppTabBar(
            controller: _tabController,
            tabs: _sections.map((s) => s.toUpperCase()).toList(),
            horizontalPadding: 24.0,
          ),

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

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
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
                      Icons.business_rounded, 
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

          const Spacer(),

          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20), 
              tooltip: "Manage Project Settings",
              onPressed: () => _openProjectSettings(context, widget.projectId), 
            ),
          ),
          
        ],
      ),
    );
  }
}