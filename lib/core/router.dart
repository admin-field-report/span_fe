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

import '../screens/tools/tools_manager_screen.dart';

import '../screens/tags/tag_management_screen.dart';

import '../screens/ai_data/ai_data_screen.dart';

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
            path: '/templates/tools',
            builder: (context, state) => const ToolsManagerScreen(),
          ),
          GoRoute(
            path: '/ai',
            builder: (context, state) => const AIDataScreen(),
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
    final String location = state.matchedLocation;

    // 1. Still Booting? Stay on /loading (if you use it as a route)
    if (!isInitialized) return '/loading';

    // 2. Not logged in? Force to /login unless they are already there
    if (!isAuthenticated) {
      return (location == '/login') ? null : '/login';
    }

    // 3. Logged in but User Data is missing? Fetch it on /loading
    if (isAuthenticated && authController.user == null) {
      return (location == '/loading') ? null : '/loading';
    }

    // 4. Logged in and trying to hit Login or Loading? Send to Dashboard
    if (isAuthenticated && (location == '/login' || location == '/loading')) {
      return '/';
    }

    // 5. IMPORTANT: Allow all other paths! 
    // If we return null, GoRouter stays on the path the user clicked (e.g., /settings)
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