import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/project.dart';
import './controllers/project_controller.dart';
import '../../widgets/widgets.dart';
import './widgets/add_project_form.dart';
import '../../core/api_service.dart';
import '../../services/toast_service.dart';

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
   final bool isDesktop = MediaQuery.of(context).size.width > 900;

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
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;
    final bool isDesktop = size.width > 900;

    return ListenableBuilder(
      listenable: projectController,
      builder: (context, child) {
        final displayData = _getFilteredProjects();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER SECTION
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 32, 
                  vertical: 20
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              "Projects",
                              style: (isMobile ? theme.textTheme.headlineMedium : theme.textTheme.displaySmall)?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            // Desktop Refresh Button
                            if (isDesktop) ...[
                              const SizedBox(width: 16),
                              IconButton(
                                onPressed: projectController.isLoading ? null : () => projectController.getAllProjects(),
                                tooltip: 'Refresh Projects',
                                icon: projectController.isLoading 
                                  ? SizedBox(
                                      width: 18, 
                                      height: 18, 
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, 
                                        color: colorScheme.primary
                                      )
                                    )
                                  : Icon(
                                      Icons.refresh_rounded, 
                                      color: colorScheme.onSurface.withOpacity(0.6)
                                    ),
                                style: IconButton.styleFrom(
                                  backgroundColor: colorScheme.onSurface.withOpacity(0.05),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!isDesktop) 
                          FilledButton.icon( // Assuming 'Button' was a placeholder for FilledButton
                            label: const Text("Add Project"),
                            icon: const Icon(Icons.add_rounded),
                            onPressed: () => _showAddProject(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildTopToolbar(isDesktop, theme),
                  ],
                ),
              ),
         
              // TABLE SECTION
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  child: ListenableBuilder(
                    listenable: projectController,
                    builder: (context, child) {
                      return CommonTable<Project>(
                        isLoading: projectController.isLoading,
                        data: displayData,
                        showCheckboxes: false,
                        rowsPerPage: 10,
                        onRowTap: (project) {
                          final id = project.id;
                          final name = Uri.encodeComponent(project.name);
                          context.go('/projects/details/$id/$name/inspections');
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- UI CONCEPT HELPERS ---
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

  Widget _buildTopToolbar(bool isDesktop, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 45,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                icon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                hintText: "Search projects...",
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(width: 16),
          Button(
            label: "Add Project",
            icon: Icons.add_rounded,
            onPressed: () => _showAddProject(context),
            ),
          ]
      ],
    );
  }
}