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
import '../screens/reports/reports_screen.dart';
import '../screens/reports/word_profile_template_screen.dart';

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
        return LoginScreen(
          showBetaLogin: isBeta, 
          authMode: AuthMode.login, // 🚀 Updated to use enum
        );
      },
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) {
        final isBeta = state.uri.queryParameters['beta'] == 'true';
        return LoginScreen(
          showBetaLogin: isBeta, 
          authMode: AuthMode.signup, // 🚀 Updated to use enum
        );
      },
    ),
    // 🚀 NEW: Added the forgot password route
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) {
        final isBeta = state.uri.queryParameters['beta'] == 'true';
        return LoginScreen(
          showBetaLogin: isBeta, 
          authMode: AuthMode.forgotPassword, 
        );
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
                        // 🚀 Initial document travels via `extra`, not the URL — with
                        // multiple documents open as tabs, the URL stays clean and the
                        // open-tab session is restored from local storage instead.
                        final extra = state.extra;
                        final documentId = extra is Map ? (extra['documentId']?.toString() ?? '') : '';

                        return CanvasScreen(
                          projectId: state.pathParameters['id']!,
                          inspectionId: state.pathParameters['inspectionId']!,
                          documentId: documentId,
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
          path: '/templates/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        // 🚀 Eve Word-profile flow: create-mode (no id yet) and manage-mode
        // (existing template, optionally resuming a known job/status via
        // query params so the list row doesn't need a fresh metadata fetch
        // before the screen can start polling).
        GoRoute(
          path: '/templates/reports/word-profile',
          builder: (context, state) => const WordProfileTemplateScreen(),
        ),
        GoRoute(
          path: '/templates/reports/word-profile/:templateId',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            return WordProfileTemplateScreen(
              templateId: state.pathParameters['templateId'],
              templateName: query['title'],
              initialProfileStatus: query['status'],
              initialJobId: query['jobId'],
            );
          },
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
//   redirect: (context, state) {
//     final bool isAuthenticated = authController.isAuthenticated;
//     final bool isInitialized = authController.isInitialized;
    
//     final String path = state.uri.path;
//     final String fullUri = state.uri.toString();

//     // 1. Extract the intended destination from the URL if it exists
//     final String? continueTo = state.uri.queryParameters['continue'];

//     // Helper function: Safely attach the intended path to the redirect URL
//     String createRedirect(String targetPath) {
      
//       if (authController.isExplicitLogout) return targetPath;

//       final targetUri = continueTo ?? (path != '/' && path != '/login' && path != '/loading' && path != '/signup' ? fullUri : null);
      
//       if (targetUri != null) {
//         return Uri(path: targetPath, queryParameters: {'continue': targetUri}).toString();
//       }
//       return targetPath;
//     }

//     // 2. Still Booting? Force to /loading and save the deep link in the URL
//     if (!isInitialized) {
//       if (path == '/loading') return null; 
//       return createRedirect('/loading');
//     }

//     // 3. Not logged in? Force to /login and save the deep link in the URL
//     if (!isAuthenticated) {
//       if (path == '/login' || path == '/signup') return null; 
//       return createRedirect('/login');
//     }

//     // 4. Logged in but User Data is missing? Fetch it on /loading
//     if (isAuthenticated && authController.user == null) {
//       return createRedirect('/loading');
//     }

//     // 5. Fully Authenticated and Booted!
//     // If they are sitting on a public screen, release them to their intended path
//     if (path == '/login' || path == '/loading' || path == '/signup') {
//       if (continueTo != null && continueTo.isNotEmpty) {
//         return continueTo; // Send them back to the deep link!
//       }
//       return '/projects'; // Default fallback if no deep link existed
//     }

//     // 6. Allow all normal navigation to proceed
//     return null;
//   },
// );

redirect: (context, state) {
    final bool isAuthenticated = authController.isAuthenticated;
    final bool isInitialized = authController.isInitialized;
    
    final String path = state.uri.path;
    final String fullUri = state.uri.toString();

    // 1. Extract the intended destination from the URL if it exists
    final String? continueTo = state.uri.queryParameters['continue'];

    // 🚀 NEW: Define the list of public routes that don't require login
    final bool isPublicRoute = path == '/login' || 
                               path == '/signup' || 
                               path == '/forgot-password';

    // Helper function: Safely attach the intended path to the redirect URL
    String createRedirect(String targetPath) {
      if (authController.isExplicitLogout) return targetPath;

      // 🚀 UPDATED: Use the new isPublicRoute check
      final targetUri = continueTo ?? (path != '/' && !isPublicRoute && path != '/loading' ? fullUri : null);
      
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

    // 3. Not logged in? Force to /login (unless they are already on a public route)
    if (!isAuthenticated) {
      if (isPublicRoute) return null; // 🚀 THE FIX: Allows /forgot-password to render!
      return createRedirect('/login');
    }

    // 4. Logged in but User Data is missing? Fetch it on /loading
    if (isAuthenticated && authController.user == null) {
      return createRedirect('/loading');
    }

    // 5. Fully Authenticated and Booted!
    // If they are sitting on a public screen, release them to their intended path
    if (isPublicRoute || path == '/loading') { // 🚀 UPDATED: Use the new isPublicRoute check
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