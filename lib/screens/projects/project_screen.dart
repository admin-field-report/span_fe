import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme_controller.dart';
import '../../models/project.dart';
import './controllers/project_controller.dart';
import '../../widgets/Table/table.dart';

// // --- PROJECT SCREEN ---
// class ProjectScreen extends StatefulWidget {
//   const ProjectScreen({super.key});

//   @override
//   State<ProjectScreen> createState() => _ProjectScreenState();
// }

// class _ProjectScreenState extends State<ProjectScreen> {
  
//   @override
//   void initState() {
//     super.initState();
//     projectController.getAllProjects();
//   }

//   String _searchQuery = "";
  
//   @override
//   Widget build(BuildContext context) {
//     return ListenableBuilder(
//       // Merging both theme and project listeners
//       listenable: Listenable.merge([themeController, projectController]),
//       builder: (context, _) {
//         final theme = Theme.of(context);
//         final colorScheme = theme.colorScheme;
//         final size = MediaQuery.of(context).size;
        
//         final bool isMobile = size.width < 600;
//         final bool isDesktop = size.width > 900;

//         return Scaffold(
//           backgroundColor: theme.scaffoldBackgroundColor,
//           body: SafeArea(
//             child: RefreshIndicator(
//               onRefresh: () => projectController.getAllProjects(),
//               color: colorScheme.primary,
//               child: CustomScrollView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 slivers: [
//                   SliverToBoxAdapter(
//                     child: Padding(
//                       padding: EdgeInsets.symmetric(
//                         horizontal: isMobile ? 20 : 32, 
//                         vertical: 40
//                       ),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: [
//                               Row(
//                                 children: [
//                                   Text(
//                                     "Projects",
//                                     style: (isMobile ? theme.textTheme.headlineMedium : theme.textTheme.displaySmall)?.copyWith(
//                                       fontWeight: FontWeight.w900,
//                                       letterSpacing: -1.0,
//                                       color: colorScheme.onSurface,
//                                     ),
//                                   ),
//                                   // Desktop Refresh Button
//                                   if (isDesktop) ...[
//                                     const SizedBox(width: 16),
//                                     IconButton(
//                                       onPressed: projectController.isLoading ? null : () => projectController.getAllProjects(),
//                                       tooltip: 'Refresh Projects',
//                                       icon: projectController.isLoading 
//                                         ? const SizedBox(
//                                             width: 18, 
//                                             height: 18, 
//                                             child: CircularProgressIndicator(strokeWidth: 2)
//                                           )
//                                         : Icon(
//                                             Icons.refresh_rounded, 
//                                             color: colorScheme.onSurface.withOpacity(0.6)
//                                           ),
//                                       style: IconButton.styleFrom(
//                                         backgroundColor: colorScheme.onSurface.withOpacity(0.05),
//                                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                                       ),
//                                     ),
//                                   ],
//                                 ],
//                               ),
//                               if (!isDesktop) _buildNewProjectButton(theme, isMobile),
//                             ],
//                           ),
//                           const SizedBox(height: 24),
//                           _buildTopToolbar(isDesktop, theme),
//                         ],
//                       ),
//                     ),
//                   ),

//                   // 1. Handle Loading state
//                   if (projectController.isLoading)
//                     const SliverFillRemaining(
//                       hasScrollBody: false,
//                       child: Center(
//                         child: CircularProgressIndicator(
//                           strokeWidth: 3,
//                         ),
//                       ),
//                     )

//                   // 2. Handle Empty state (Finished loading but 0 items)
//                   else if (!projectController.isLoading && projectController.projects.isEmpty)
//                     SliverFillRemaining(
//                       hasScrollBody: false,
//                       child: Center(
//                         child: Column(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(Icons.folder_open_outlined, size: 48, color: colorScheme.onSurface.withOpacity(0.2)),
//                             const SizedBox(height: 16),
//                             Text(
//                               "No projects found",
//                               style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
//                             ),
//                           ],
//                         ),
//                       ),
//                     )

//                   // 3. Handle Data state
//                   else
//                     SliverPadding(
//                       padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
//                       sliver: _buildGrid(projectController.projects, size.width),
//                     ),

//                   const SliverToBoxAdapter(child: SizedBox(height: 120)),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildTopToolbar(bool isDesktop, ThemeData theme) {
//     final colorScheme = theme.colorScheme;
//     return Row(
//       children: [
//         Expanded(
//           child: Container(
//             height: 56,
//             decoration: BoxDecoration(
//               color: colorScheme.onSurface.withOpacity(0.05),
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.1)),
//             ),
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             child: TextField(
//               onChanged: (v) => setState(() => _searchQuery = v),
//               style: TextStyle(color: colorScheme.onSurface),
//               decoration: InputDecoration(
//                 icon: Icon(Icons.search, size: 20, color: colorScheme.primary),
//                 hintText: "Search projects...",
//                 border: InputBorder.none,
//                 hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.3)),
//               ),
//             ),
//           ),
//         ),
//         if (isDesktop) ...[
//           const SizedBox(width: 16),
//           _buildNewProjectButton(theme, false),
//         ]
//       ],
//     );
//   }

//   Widget _buildNewProjectButton(ThemeData theme, bool isSmall) {
//     return ElevatedButton.icon(
//       onPressed: () {},
//       style: ElevatedButton.styleFrom(
//         backgroundColor: theme.colorScheme.primary,
//         foregroundColor: theme.colorScheme.onPrimary,
//         padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 18),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         elevation: 0,
//       ),
//       icon: const Icon(Icons.add_rounded),
//       label: Text("Create Project", style: const TextStyle(fontWeight: FontWeight.bold)),
//     );
//   }

//   Widget _buildGrid(List<Project> projects, double width) {
//     // Dynamic column count based on width
//     int crossAxisCount = width > 1200 ? 3 : (width > 700 ? 2 : 1);
    
//     return SliverGrid(
//       gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: crossAxisCount,
//         mainAxisSpacing: 20,
//         crossAxisSpacing: 20,
//         mainAxisExtent: 200, // Fixed height for Bento consistency
//       ),
//       delegate: SliverChildBuilderDelegate(
//         (context, i) => _BentoCard(
//           project: projects[i],
//           onDelete: () {
//             // Add delete logic here
//           },
//         ),
//         childCount: projects.length,
//       ),
//     );
//   }
// }

// // --- BENTO CARD COMPONENT ---
// class _BentoCard extends StatelessWidget {
//   final Project project;
//   final VoidCallback onDelete;
  
//   const _BentoCard({required this.project, required this.onDelete});

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final colorScheme = theme.colorScheme;
//     final df = DateFormat('MMM dd, yyyy');

//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: theme.cardTheme.color,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.1)),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.1), 
//             blurRadius: 15, 
//             offset: const Offset(0, 8)
//           )
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Title: 1 line with ellipsis
//           Text(
//             project.name,
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis, // Standard ellipsis
//             style: theme.textTheme.titleMedium?.copyWith(
//               fontWeight: FontWeight.bold,
//               letterSpacing: -0.5,
//             ),
//           ),
//           const SizedBox(height: 12),
          
//           // Description: Fixed constraints for ellipsis
//           Expanded(
//             child: SizedBox(
//               width: double.infinity, // Ensures text takes full width to calculate overflow
//               child: Text(
//                 project.description,
//                 maxLines: 3, // Shows exactly 3 lines then dots
//                 overflow: TextOverflow.ellipsis, // The "3 dots"
//                 style: theme.textTheme.bodySmall?.copyWith(
//                   color: colorScheme.onSurface.withOpacity(0.8),
//                   height: 1.5,
//                 ),
//               ),
//             ),
//           ),
          
//           const Divider(height: 32, thickness: 0.5),
          
//           // Footer
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     "CREATED", 
//                     style: theme.textTheme.labelSmall?.copyWith(
//                       color: colorScheme.onSurface.withOpacity(0.8), 
//                       letterSpacing: 1,
//                       fontSize: 9,
//                     )
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     df.format(project.createDate), 
//                     style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)
//                   ),
//                 ],
//               ),
//               GestureDetector(
//                 onTap: onDelete,
//                 child: Container(
//                   padding: const EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     color: colorScheme.error.withOpacity(0.08),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }


class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  String _searchQuery = "";
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    projectController.getAllProjects();
  }

  // --- Logic: Search and Sort ---
  List<Project> _getProcessedProjects() {
    List<Project> list = projectController.projects.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             p.description.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    list.sort((a, b) {
      dynamic aVal = _sortColumnIndex == 0 ? a.name.toLowerCase() : a.createDate;
      dynamic bVal = _sortColumnIndex == 0 ? b.name.toLowerCase() : b.createDate;
      
      return _sortAscending ? Comparable.compare(aVal, bVal) : Comparable.compare(bVal, aVal);
    });
    return list;
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

        final displayData = _getProcessedProjects();

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                // --- HEADER SECTION (Kept your original style) ---
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32, vertical: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Projects",
                              style: (isMobile ? theme.textTheme.headlineMedium : theme.textTheme.displaySmall)?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (!isDesktop) _buildNewProjectButton(theme, isMobile),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildTopToolbar(isDesktop, theme),
                      ],
                    ),
                  ),
                ),

                // --- TABLE SECTION ---
                if (projectController.isLoading)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (displayData.isEmpty)
                  SliverFillRemaining(
                    child: Center(child: Text("No projects found", style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)))),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32),
                    sliver: SliverToBoxAdapter(
                      child: CommonTable<Project>(
                        data: displayData,
                        sortColumnIndex: _sortColumnIndex,
                        sortAscending: _sortAscending,
                        onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; }),
                        columns: [
                          TableColumn(
                            title: "Project Name", 
                            sortable: true,
                            builder: (p) => Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))
                          ),
                          TableColumn(
                            title: "Description", 
                            builder: (p) => Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis)
                          ),
                          TableColumn(
                            title: "Date", 
                            sortable: true,
                            builder: (p) => Text(DateFormat('MMM dd, yyyy').format(p.createDate))
                          ),
                          TableColumn(
                            title: "Actions", 
                            builder: (p) => IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: colorScheme.error,
                              onPressed: () {},
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- YOUR ORIGINAL BUTTON (Kept exactly the same) ---
  Widget _buildNewProjectButton(ThemeData theme, bool isSmall) {
    return ElevatedButton.icon(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      icon: const Icon(Icons.add_rounded),
      label: Text("Create Project", style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTopToolbar(bool isDesktop, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                icon: Icon(Icons.search, size: 20, color: colorScheme.primary),
                hintText: "Search projects...",
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(width: 16),
          _buildNewProjectButton(theme, false),
        ]
      ],
    );
  }
}