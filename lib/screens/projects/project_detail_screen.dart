import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/widgets.dart';
import './widgets/project_inspections.dart';
import './widgets/project_documents.dart';
import './widgets/project_reports.dart';
import './widgets/project_medias.dart';

class ProjectDetailsScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  final String initialSection;

  const ProjectDetailsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
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
    // Calculate initial index based on URL
    int initialIndex = _sections.indexOf(widget.initialSection);
    _tabController = TabController(
      length: _sections.length, 
      vsync: this, 
      initialIndex: initialIndex != -1 ? initialIndex : 0,
    );

    // Update URL whenever the tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _updateUrl();
      }
    });
  }

  void _updateUrl() {
    final section = _sections[_tabController.index];
    final name = Uri.encodeComponent(widget.projectName);
    context.go('/projects/details/${widget.projectId}/$name/$section');
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
        children: [
          // --- 1. Header with Back Button ---
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => context.pop(),
                  tooltip: "Back to Projects",
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.projectName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
                      // Text(
                      //   widget.projectName,
                      //   style: theme.textTheme.titleLarge?.copyWith(
                      //     fontWeight: FontWeight.bold,
                      //     letterSpacing: -0.5,
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- 2. Tab Bar ---
          AppTabBar(
            controller: _tabController,
            tabs: _sections.map((s) => s.toUpperCase()).toList(),
            horizontalPadding: 24.0,
          ),

          // --- 3. Section Content ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ProjectInspectionsTab(projectId: widget.projectId),
                ProjectDocuments(projectId: widget.projectId),
                ProjectMediaTab(projectId: widget.projectId),
                ProjectReports(projectId: widget.projectId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB CONTENT BUILDERS ---
  Widget _buildPlaceholderTab(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}



// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import './widgets/project_inspections.dart';
// import './widgets/project_documents.dart';
// import './widgets/project_medias.dart';
// import '../../utils/app_responsive.dart';

// class ProjectDetailsScreen extends StatefulWidget {
//   final String projectId;
//   final String projectName;
//   final String initialSection;

//   const ProjectDetailsScreen({
//     super.key,
//     required this.projectId,
//     required this.projectName,
//     required this.initialSection,
//   });

//   @override
//   State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
// }

// class _ProjectDetailsScreenState extends State<ProjectDetailsScreen>
//     with SingleTickerProviderStateMixin {
//   late TabController _tabController;
//   final List<String> _sections = ['inspections', 'documents', 'media', 'reports'];

//   @override
//   void initState() {
//     super.initState();
//     int initialIndex = _sections.indexOf(widget.initialSection);
//     _tabController = TabController(
//       length: _sections.length,
//       vsync: this,
//       initialIndex: initialIndex != -1 ? initialIndex : 0,
//     );

//     _tabController.addListener(() {
//       if (!_tabController.indexIsChanging) {
//         _updateUrl();
//       }
//     });
//   }

//   void _updateUrl() {
//     final section = _sections[_tabController.index];
//     final name = Uri.encodeComponent(widget.projectName);
//     context.go('/projects/details/${widget.projectId}/$name/$section');
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final colorScheme = theme.colorScheme;
//     final bool isMobile = AppResponsive.isMobileScreen(context);

//     return Scaffold(
//       backgroundColor: theme.scaffoldBackgroundColor,
//       body: SafeArea(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // --- 1. MODERN HEADER ---
//             Padding(
//               padding: EdgeInsets.fromLTRB(isMobile ? 8 : 16, 24, 24, 16),
//               child: Row(
//                 children: [
//                   Tooltip(
//                     message: 'Back to Projects',
//                     child: IconButton.filledTonal(
//                       onPressed: () => context.pop(),
//                       icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
//                       style: IconButton.styleFrom(
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           widget.projectName,
//                           style: theme.textTheme.headlineSmall?.copyWith(
//                             fontWeight: FontWeight.bold,
//                             letterSpacing: -0.5,
//                           ),
//                         ),
//                         Text(
//                           "Project Overview & Management",
//                           style: theme.textTheme.bodySmall?.copyWith(
//                             color: colorScheme.onSurfaceVariant,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // --- 2. CLEAN TAB BAR ---
//             // Using a Container to add a subtle bottom border for separation
//             Container(
//               decoration: BoxDecoration(
//                 border: Border(
//                   bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1), width: 1),
//                 ),
//               ),
//               child: TabBar(
//                 controller: _tabController,
//                 isScrollable: isMobile,
//                 tabAlignment: isMobile ? TabAlignment.start : TabAlignment.fill,
//                 indicatorSize: TabBarIndicatorSize.label,
//                 indicatorWeight: 3,
//                 labelColor: colorScheme.primary,
//                 unselectedLabelColor: colorScheme.onSurfaceVariant,
//                 labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
//                 tabs: _sections.map((s) => Tab(text: s.toUpperCase())).toList(),
//               ),
//             ),

//             // --- 3. SECTION CONTENT ---
//             Expanded(
//               child: Container(
//                 // Adding a slight tint to the body background makes the table/cards pop
//                 color: theme.brightness == Brightness.dark 
//                     ? Colors.black.withOpacity(0.1) 
//                     : colorScheme.surfaceVariant.withOpacity(0.2),
//                 child: TabBarView(
//                   controller: _tabController,
//                   children: [
//                     _buildTabPadding(ProjectInspectionsTab(projectId: widget.projectId)),
//                     _buildTabPadding(ProjectDocuments(projectId: widget.projectId)),
//                     _buildTabPadding(ProjectMediaTab(projectId: widget.projectId)),
//                     // _buildPlaceholderTab("Media Gallery", Icons.collections_rounded),
//                     _buildPlaceholderTab("Analytics Reports", Icons.analytics_rounded),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildTabPadding(Widget child) {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: child,
//     );
//   }

//   Widget _buildPlaceholderTab(String title, IconData icon) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(24),
//             decoration: BoxDecoration(
//               color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
//               shape: BoxShape.circle,
//             ),
//             child: Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
//           ),
//           const SizedBox(height: 20),
//           Text(
//             title,
//             style: Theme.of(context).textTheme.titleMedium?.copyWith(
//               color: Theme.of(context).colorScheme.onSurfaceVariant,
//             ),
//           ),
//           const SizedBox(height: 8),
//           const Text("This module is currently under development.", style: TextStyle(color: Colors.grey, fontSize: 12)),
//         ],
//       ),
//     );
//   }
// }