import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/controllers/auth_controller.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/app_loading_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/layout/main_scaffold.dart';
import '../screens/projects/project_screen.dart';
import '../screens/projects/project_detail_screen.dart';
import '../screens/projects/widgets/inspection_details.dart';

import '../screens/canvas/canvas_screen.dart';

import '../screens/tags/tag_management_screen.dart';

import '../widgets/canvas/canvas.dart';

import '../screens/layout/not_found_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  refreshListenable: authController,
  initialLocation: '/',
  errorBuilder: (context, state) => const NotFoundScreen(),
  routes: [
    // --- PUBLIC ROUTES ---
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/loading',
      builder: (context, state) => const AppLoadingScreen(),
    ),
    // --- PRIVATE ROUTES (Wrapped in ShellRoute) ---
    ShellRoute(
      builder: (context, state, child) {
        final bool isCanvasRoute = state.uri.path.contains('/canvas');
        return MainScaffold(
          isScrollable: !isCanvasRoute, 
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/projects',
          builder: (context, state) => const ProjectScreen(),
          routes: [
            GoRoute(
              path: 'details/:id/:section', 
              builder: (context, state) {
                return ProjectDetailsScreen(
                  projectId: state.pathParameters['id']!,
                  initialSection: state.pathParameters['section'] ?? 'inspections',
                );
              },
              routes: [
                GoRoute(
                  path: ':inspectionId', 
                  builder: (context, state) {
                    return InspectionDetailsScreen(
                      inspectionId: state.pathParameters['inspectionId']!,
                    );
                  },
                  routes: [
                    GoRoute(
                      path: 'canvas', 
                      builder: (context, state) {
                        final documentId = state.uri.queryParameters['document'] ?? '';
                        final page = state.uri.queryParameters['page'] ?? '1';

                        return CanvasScreen(
                          projectId: state.pathParameters['id']!, 
                          inspectionId: state.pathParameters['inspectionId']!,
                          documentId: documentId,
                          page: page,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
          ),
          GoRoute(
            path: '/templates/tags',
            builder: (context, state) => const TagManagementScreen(),
          ),
          GoRoute(
            path: '/canvas',
            builder: (context, state) => const Canvas(),
          ),
      ],
    ),
  ],

  redirect: (context, state) {
    final bool isAuthenticated = authController.isAuthenticated;
    final bool isInitialized = authController.isInitialized;

    // 1. Manually build the exact path they want to visit
    String location = state.uri.path;
    if (state.uri.query.isNotEmpty) {
      location += '?${state.uri.query}';
    }

    // 2. Still Booting? 
    if (!isInitialized) {
      // If they are already heading to loading, let them.
      if (state.uri.path == '/loading') return null;
      
      // Pass their exact destination into the loading URL safely encoded!
      final encodedLoc = Uri.encodeComponent(location);
      return '/loading?continue=$encodedLoc';
    }

    // 3. Not logged in? Force to /login
    if (!isAuthenticated) {
      if (state.uri.path == '/login') return null;
      
      // Save their destination so they go back after logging in!
      final encodedLoc = Uri.encodeComponent(location);
      return '/login?continue=$encodedLoc';
    }

    // 4. Logged in but User Data is missing? Fetch it on /loading
    if (isAuthenticated && authController.user == null) {
      if (state.uri.path == '/loading') return null;
      
      final encodedLoc = Uri.encodeComponent(location);
      return '/loading?continue=$encodedLoc';
    }

    // 5. App is fully ready, but they are stuck on a system route?
    if (isAuthenticated && (state.uri.path == '/login' || state.uri.path == '/loading')) {
      
      // 🚀 THE MAGIC RESTORE 🚀
      // Check if the URL has our '?continue=' parameter
      final continuePath = state.uri.queryParameters['continue'];
      
      if (continuePath != null && continuePath.isNotEmpty) {
        // Decode it and send them right back to their exact canvas URL!
        return Uri.decodeComponent(continuePath);
      }
      
      // Failsafe: If no continue path exists, send to home/dashboard
      return '/projects'; // Update this to your actual default home route!
    }

    // 6. Allow all other paths!
    return null;
  },
);


// Private Page 1
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Text("Dashboard (Private)");
  }
}