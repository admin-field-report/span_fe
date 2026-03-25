import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/project.dart';
import './controllers/project_controller.dart';
import '../../widgets/widgets.dart';
import './widgets/add_project_form.dart';
import '../../core/api_service.dart';
import '../../services/toast_service.dart';
import '../../utils/utils.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
    final ApiService _apiService = ApiService();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    projectController.getAllProjects();
  }

  List<Project> _getFilteredProjects() {
    return projectController.projects.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             p.description.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _showAddProject(BuildContext context) {
   final bool isDesktop = AppResponsive.isDesktopScreen(context);

  if (isDesktop) {
    showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: AddProjectForm(isDesktop: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => const AddProjectForm(isDesktop: false),
      );
    }
  }

  Future<void> removeProject(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/project/$id');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        ToastService.show(context, 
          message: "Project deleted successfully", 
          type: ToastType.success
        );
        projectController.getAllProjects();
      } else {
        ToastService.show(context, 
          message: "Unexpected error occurred", 
          type: ToastType.error
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastService.show(context, 
        message: "Failed to delete project", 
        type: ToastType.error
      );
    }
  }

  void _confirmDelete(BuildContext context, Project project) {
    showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: ConfirmationDialog(
              title: "Remove Project",
              description: "Are you sure you want to remove '${project.name}'?",
              confirmLabel: "Remove",
              onConfirm: () async => await removeProject(context, project.id),
            ),
          ),
        ),
      );
  }

@override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: projectController,
      builder: (context, child) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              SizedBox(height: 10),

              _buildHeader(context, theme),

              SizedBox(height: 20),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    // 1. HEADER SECTION
                    _buildTopToolbar(theme),
                    
                    // 2. TABLE SECTION
                    ListenableBuilder(
                      listenable: projectController,
                      builder: (context, child) {
                      final displayData = _getFilteredProjects();
                      return CommonTable<Project>(
                          isLoading: projectController.isLoading,
                          data: displayData,
                          showCheckboxes: false,
                          rowsPerPage: 10,
                          onRowTap: (project) {
                            final id = project.id;
                            context.go('/projects/details/$id/inspections');
                          },
                          columns: [
                            TableColumn(
                              title: "Name",
                              flex: 3,
                              minWidth: 250,
                              sortable: true,
                              sortValue: (p) => p.name,
                              builder: (p) => _buildProductCell(p, theme),
                            ),
                            TableColumn(
                              title: "Description",
                              flex: 3,
                              minWidth: 200,
                              builder: (p) => Text(
                                p.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            TableColumn(
                              title: "Created at",
                              flex: 2,
                              minWidth: 150,
                              sortable: true,
                              sortValue: (p) => p.createDate,
                              builder: (p) => _buildDateTimeCell(p, theme),
                            ),
                            TableColumn(
                              title: "Actions",
                              flex: 0,
                              minWidth: 150,
                              builder: (p) => IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: colorScheme.error,
                                onPressed: () => _confirmDelete(context, p),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    
                  ],
                ),
              )
            ],
          );
      },
    );
  }

  // --- UI CONCEPT HELPERS ---
  Widget _buildHeader(BuildContext context, ThemeData theme) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Projects", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
          Button(
              label: "Add Project",
              icon: Icons.add_rounded,
              onPressed: () => _showAddProject(context),
            )
        ],
      ),
    ],
  );
}

  Widget _buildProductCell(Project p, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder_copy_outlined, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeCell(Project p, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(DateFormat('dd MMM yyyy').format(p.createDate), 
          style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(DateFormat('hh:mm a').format(p.createDate), 
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16), 
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              width: 350,
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) ...[
            const Spacer(),
            Tooltip(
              message: 'Refresh Projects',
              child: InkWell(
                onTap: projectController.isLoading ? null : () {
                  projectController.getAllProjects();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded, 
                    size: 20, 
                    color: colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
              ),
            ),
          ],
        ],
      )
    );
  }
}