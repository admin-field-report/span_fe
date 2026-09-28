// LOCAL PREVIEW ONLY — not part of the app build.
//
// Renders the Span Report Profiler screens inside the app's own layout and
// theme without signing in, so the screens can be reviewed and screenshotted
// while a dev account isn't available. The real app (lib/main.dart) and its
// auth are unchanged. Run with:
//   flutter run -d web-server --web-port 8687 -t lib/preview_report_profiler.dart --dart-define=EVE_UI_KEY=...
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';

import 'core/storage_service.dart';
import 'core/theme_controller.dart';
import 'screens/reports/report_profiler_detail_screen.dart';
import 'screens/reports/report_profiler_screen.dart';
import 'screens/layout/main_scaffold.dart';

final _previewRouter = GoRouter(
  initialLocation: '/templates/reports/profiler',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainScaffold(isScrollable: true, child: child),
      routes: [
        GoRoute(
          path: '/templates/reports/profiler',
          builder: (context, state) => const ReportProfilerScreen(),
        ),
        GoRoute(
          path: '/templates/reports/profiler/new',
          builder: (context, state) => const ReportProfilerDetailScreen(),
        ),
        GoRoute(
          path: '/templates/reports/profiler/:templateId',
          builder: (context, state) => ReportProfilerDetailScreen(
            key: ValueKey(state.pathParameters['templateId']),
            templateId: state.pathParameters['templateId'],
          ),
        ),
      ],
    ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await StorageService.init();
  await themeController.loadPreferences();
  runApp(ListenableBuilder(
    listenable: themeController,
    builder: (context, _) => MaterialApp.router(
      title: 'Span Inspect (preview)',
      debugShowCheckedModeBanner: false,
      routerConfig: _previewRouter,
      themeMode: themeController.themeMode,
      theme: themeController.getTheme(Brightness.light),
      darkTheme: themeController.getTheme(Brightness.dark),
    ),
  ));
}
