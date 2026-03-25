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

import '../screens/layout/not_found_screen.dart';

final router = GoRouter(
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
      ],
    ),
  ],

  redirect: (context, state) {
    final bool isAuthenticated = authController.isAuthenticated;
    final bool isInitialized = authController.isInitialized;
    final String location = state.matchedLocation;

    // 1. Still Booting? 
    if (!isInitialized) {
      // CAPTURE: Save where they were (e.g., /projects) before moving to /loading
      authController.setTargetPath(location);
      return '/loading';
    }

    // 2. Not logged in? Force to /login
    if (!isAuthenticated) {
      return (location == '/login') ? null : '/login';
    }

    // 3. Logged in but User Data is missing? Fetch it on /loading
    if (isAuthenticated && authController.user == null) {
      // If they were already on a specific page, keep saving it
      authController.setTargetPath(location);
      return (location == '/loading') ? null : '/loading';
    }

    // 4. Logged in and trying to hit Login or Loading?
    if (isAuthenticated && (location == '/login' || location == '/loading')) {
      // RESTORE: Go to the saved path (Flow 2) or Dashboard (Flow 1)
      return authController.targetPath;
    }

    // 5. Allow all other paths!
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