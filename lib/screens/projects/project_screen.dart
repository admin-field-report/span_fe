import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/card/card.dart';
import '../../widgets/table/table.dart';
import '../../widgets/button/button.dart';
import '../../widgets/search_field/search_field.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../../models/project.dart';
import './controllers/project_controller.dart';
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
            child: AddProjectForm(isDesktop: true), // No project passed = Create Mode
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

  // 🚀 REWIRED: Method to show the Edit Project Form
  void _showEditProject(BuildContext context, Project project) {
    final bool isDesktop = AppResponsive.isDesktopScreen(context);

    if (isDesktop) {
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.5),
        builder: (context) => Center(
          child: Material(
            color: Colors.transparent,
            child: AddProjectForm(isDesktop: true, project: project), // Pass project = Edit Mode
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) => AddProjectForm(isDesktop: false, project: project),
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
            const SizedBox(height: 10),
            _buildHeader(context, theme),
            const SizedBox(height: 10),

            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    _buildTopToolbar(theme),
                    
                    Expanded(
                      child: ListenableBuilder(
                        listenable: projectController,
                        builder: (context, child) {
                          final displayData = _getFilteredProjects();
                          return CommonTable<Project>(
                            isLoading: projectController.isLoading,
                            data: displayData,
                            showCheckboxes: false,
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
                                minWidth: 100, 
                                isStickyRight: true, 
                                builder: (p) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      color: colorScheme.primary,
                                      tooltip: "Edit Project",
                                      onPressed: () => _showEditProject(context, p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      color: colorScheme.error,
                                      tooltip: "Delete Project",
                                      onPressed: () => _confirmDelete(context, p),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      )
                     ),
                  ],
                ),
              )
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
            Text("Projects", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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

          if (isDesktop) const Spacer(),
          if (isDesktop) 
            Button(
              label: "Add Project",
              icon: Icons.add_rounded,
              onPressed: () => _showAddProject(context),
            )
          else ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Add Project",
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
              onPressed: () => _showAddProject(context),
            )
          ],
        ],
      )
    );
  }
}