import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/controllers/auth_controller.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/app_loading_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/layout/main_scaffold.dart';
import '../screens/projects/project_screen.dart';
import '../screens/projects/project_detail_screen.dart';
import '../screens/projects/inspections/inspection_details.dart';
import '../screens/canvas/canvas_screen.dart';
import '../screens/templates/templates_screen.dart';
import '../screens/tools/tools_manager_screen.dart';
import '../screens/tags/tag_management_screen.dart';
import '../screens/ai_data/ai_data_screen.dart';
import '../widgets/canvas/canvas.dart';
import '../screens/layout/not_found_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  initialLocation: '/',
  refreshListenable: authController,
  navigatorKey: rootNavigatorKey,
  errorBuilder: (context, state) => const NotFoundScreen(),
  routes: [
    // --- PUBLIC ROUTES ---
    GoRoute(
      path: '/login',
      builder: (context, state) {
        final isBeta = state.uri.queryParameters['beta'] == 'true';
        return LoginScreen(showBetaLogin: isBeta, isLoginMode: true);
      },
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) {
        final isBeta = state.uri.queryParameters['beta'] == 'true';
        return LoginScreen(showBetaLogin: isBeta, isLoginMode: false);
      },
    ),
    GoRoute(
      path: '/loading',
      builder: (context, state) => const AppLoadingScreen(),
    ),
    // --- PRIVATE ROUTES (Wrapped in ShellRoute) ---
    ShellRoute(
      builder: (context, state, child) {
        final bool isCanvasRoute = state.uri.path.contains('/canvas');
        final bool removePadding = state.uri.path.contains('/canvas');
        return MainScaffold(
          isScrollable: !isCanvasRoute,
          removePadding: removePadding,
          isFullScreen: isCanvasRoute,
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
                      path: '/canvas', 
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
          path: '/templates/projects',
          builder: (context, state) => const TemplateManagementScreen(),
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

  // 🚀 BULLETPROOF WEB REDIRECT LOGIC
  redirect: (context, state) {
    final bool isAuthenticated = authController.isAuthenticated;
    final bool isInitialized = authController.isInitialized;
    
    final String path = state.uri.path;
    final String fullUri = state.uri.toString();

    // 1. Extract the intended destination from the URL if it exists
    final String? continueTo = state.uri.queryParameters['continue'];

    // Helper function: Safely attach the intended path to the redirect URL
    String createRedirect(String targetPath) {
      
      if (authController.isExplicitLogout) return targetPath;

      final targetUri = continueTo ?? (path != '/' && path != '/login' && path != '/loading' && path != '/signup' ? fullUri : null);
      
      if (targetUri != null) {
        return Uri(path: targetPath, queryParameters: {'continue': targetUri}).toString();
      }
      return targetPath;
    }

    // 2. Still Booting? Force to /loading and save the deep link in the URL
    if (!isInitialized) {
      if (path == '/loading') return null; 
      return createRedirect('/loading');
    }

    // 3. Not logged in? Force to /login and save the deep link in the URL
    if (!isAuthenticated) {
      if (path == '/login' || path == '/signup') return null; 
      return createRedirect('/login');
    }

    // 4. Logged in but User Data is missing? Fetch it on /loading
    if (isAuthenticated && authController.user == null) {
      return createRedirect('/loading');
    }

    // 5. Fully Authenticated and Booted!
    // If they are sitting on a public screen, release them to their intended path
    if (path == '/login' || path == '/loading' || path == '/signup') {
      if (continueTo != null && continueTo.isNotEmpty) {
        return continueTo; // Send them back to the deep link!
      }
      return '/projects'; // Default fallback if no deep link existed
    }

    // 6. Allow all normal navigation to proceed
    return null;
  },
);

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Text("Dashboard (Private)");
  }
}