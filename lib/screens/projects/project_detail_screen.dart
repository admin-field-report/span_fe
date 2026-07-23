import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'inspections/project_inspections.dart';
import 'documents/project_documents.dart';
import 'reports/project_reports.dart';
import './widgets/project_medias.dart';
import './widgets/project_settings.dart';
import '../../widgets/tab/tab.dart';
import '../../widgets/breadcrumb/breadcrumb.dart'; 
import '../../utils/utils.dart';
import './widgets/add_project_form.dart'; 
import './controllers/project_controller.dart'; 

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

    // 🚀 TELL THE CONTROLLER TO DO THE HEAVY LIFTING
    WidgetsBinding.instance.addPostFrameCallback((_) {
      projectController.fetchProjectDetails(widget.projectId);
    });
  }

  Future<void> _showEditProject() async {
    if (projectController.currentProject == null) return; 

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
              project: projectController.currentProject, 
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
          project: projectController.currentProject, 
        ),
      );
    }
    
    // 🚀 Refresh data after editing
    if (isUpdated == true) {
      projectController.fetchProjectDetails(widget.projectId);
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
          
          // 🚀 WRAP HEADER IN LISTENABLE TO REACT TO CONTROLLER
          ListenableBuilder(
            listenable: projectController,
            builder: (context, _) => _buildHeader(context, theme),
          ),

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
    // 🚀 READ DATA DIRECTLY FROM CONTROLLER
    final project = projectController.currentProject;
    final isLoading = projectController.isProjectDetailsLoading;
    final projectName = project?.name ?? "Loading...";
    final clientName = project?.clientName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBreadcrumbs(
            items: [
              BreadcrumbItem(
                label: "Projects",
                onTap: () => context.go('/projects'), 
              ),
              BreadcrumbItem(
                label: projectName, 
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => context.go('/projects'),
              ),
              const SizedBox(width: 12), 
              
              Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, 
                    children: [
                      Text(
                        projectName, 
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (isLoading) ...[
                        const SizedBox(width: 12),
                        const SizedBox(
                          width: 14, height: 14, 
                          child: CircularProgressIndicator(strokeWidth: 2)
                        )
                      ] else if (project != null) ...[
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
                  
                  if (clientName != null && clientName.isNotEmpty && !isLoading) ...[
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
                          clientName,
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
        ],
      ),
    );
  }
}