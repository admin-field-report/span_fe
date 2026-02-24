import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme_controller.dart';
import '../../models/project.dart';
import './controllers/project_controller.dart';
import '../../widgets/table/table.dart';
import '../../widgets/button/button.dart';
import './widgets/add_project_form.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeController, projectController]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final size = MediaQuery.of(context).size;
        final bool isMobile = size.width < 600;
        final bool isDesktop = size.width > 900;

        final displayData = _getFilteredProjects();

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () => projectController.getAllProjects(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [

                  // --- HEADER SECTION (Concept Redesign) ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 20 : 32, 
                        vertical: 40
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
                                        ? const SizedBox(
                                            width: 18, 
                                            height: 18, 
                                            child: CircularProgressIndicator(strokeWidth: 2)
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
                               Button(
                                  label: "Add Project",
                                  icon: Icons.add_rounded,
                                  onPressed: () => _showAddProject(context),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildTopToolbar(isDesktop, theme),
                        ],
                      ),
                    ),
                  ),

                  // --- DATA TABLE SECTION ---
                  if (projectController.isLoading)
                    const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()))
                  else if (displayData.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text("No projects found", 
                          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
                      sliver: SliverToBoxAdapter(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: colorScheme.outlineVariant.withOpacity(0.2)),
                          ),
                          child: CommonTable<Project>(
                            data: displayData,
                            showCheckboxes: false,
                            rowsPerPage: 10,
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
                                title: "Create at",
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
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
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