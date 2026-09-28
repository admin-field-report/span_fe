// LOCAL PREVIEW ONLY — not part of the app build.
//
// Renders the Span report generation screens (Generate report, progress,
// the generated report as an editable document, and the Reports list) inside
// the app's own layout and theme without signing in, so they can be reviewed
// and screenshotted while a dev account isn't available.
// The real app (lib/main.dart) and its auth are unchanged. Run with:
//   flutter run -d web-server --web-port 8686 -t lib/preview_report_generation.dart \
//     --dart-define=EVE_UI_KEY=... --dart-define=EVE_UI_BASE_URL=http://localhost:3100
//
// Everything loads real data from the Span UI API except
// /projects/<id>/reports/runs/sample-progress, a fixed "in progress" state
// (no report is running locally; the dev tool's live event stream is only
// available on its deployment). On a report, `?edit=1` opens Area 2's
// description for editing with one wording change applied (so Save shows),
// and `?details=1` opens the Details sheet. Nothing is saved from the preview.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';

import 'core/storage_service.dart';
import 'core/theme_controller.dart';
import 'screens/layout/main_scaffold.dart';
import 'screens/projects/reports/generation/generate_report_screen.dart';
import 'screens/projects/reports/generation/report_generation_api.dart';
import 'screens/projects/reports/generation/report_run_screen.dart';
import 'screens/projects/reports/generation/span_reports_list.dart';

/// A report mid-run: the inspection and template of a real run
/// (job_20260928001010_7ts0u0), with activity lines in the shape the
/// events API returns for the steps that run takes.
ReportRunPreviewState _sampleProgress() {
  final start = DateTime(2026, 9, 27, 20, 10, 10);
  DateTime at(int m, int s) => start.add(Duration(minutes: m, seconds: s));
  var i = 0;
  GenerationActivity act(int m, int s, String text, {String kind = 'tool'}) =>
      GenerationActivity(index: i++, at: at(m, s), kind: kind, text: text);
  return ReportRunPreviewState(
    now: at(4, 38),
    detail: ReportRunDetail(
      run: ReportRun(
        jobId: 'sample-progress',
        status: 'running',
        templateId: 'tpl_20260927205231_i6kce2',
        templateName: 'WRG Progress Report',
        inspectionId: 'insp_20260927172458_jvrpmh',
        inspectionName: '37-22 Parsons Crescent (courtyard facade, week 3)',
        createdAt: start,
      ),
      stats: const ReportStats(),
      qa: const ReportQa(),
      questions: const [],
      typicalMinutes: 6,
      maxMinutes: 20,
    ),
    events: GenerationEvents(
      status: 'running',
      nextIndex: 12,
      phaseKey: 'qa',
      phaseStartedAt: {
        'reading': at(0, 4),
        'writing': at(1, 22),
        'filling': at(2, 51),
        'qa': at(3, 9),
      },
      lastEventAt: at(4, 31),
      activities: [
        act(0, 4, 'Loaded the job details'),
        act(0, 6, 'Loading the report template and its instructions'),
        act(0, 6, 'Loading the inspection: findings, photos and notes'),
        act(0, 11, 'Loading the report writing guide'),
        act(1, 20, 'Template and inspection are clear. Now writing the activity log and captions.', kind: 'message'),
        act(1, 22, 'Writing the report content'),
        act(2, 51, 'Filling the Word template'),
        act(3, 9, 'Running quality checks on the report'),
        act(3, 40,
            'The first fill ran to 5 pages with a near-empty last page. Letting the activity table flow like the examples do.',
            kind: 'message'),
        act(3, 58, 'Tidying the Word file'),
        act(4, 17, 'Filling the Word template'),
        act(4, 31, 'Running quality checks on the report'),
      ],
    ),
  );
}

/// A small wording edit a user might make (Area 2 of the NYC DDC run).
void _sampleEdit(Map<String, dynamic> fillMap) {
  final areas = fillMap['{{BLOCK:AREA}}'];
  if (areas is! List || areas.length < 2 || areas[1] is! Map) return;
  final item = areas[1] as Map;
  final text = item['{{DESCRIPTION}}'];
  if (text is String) {
    item['{{DESCRIPTION}}'] = text.replaceFirst(
      'approximately 12 linear feet of the 30 linear feet complete',
      'approximately 12 of the 30 linear feet complete',
    );
  }
}

final _previewRouter = GoRouter(
  initialLocation: '/projects/demo/reports',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainScaffold(isScrollable: true, child: child),
      routes: [
        GoRoute(
          path: '/projects/:projectId/reports',
          builder: (context, state) => SpanReportsList(
            projectId: state.pathParameters['projectId']!,
            inspectionId: state.uri.queryParameters['inspectionId'],
          ),
        ),
        GoRoute(
          path: '/projects/:projectId/reports/generate',
          builder: (context, state) => GenerateReportScreen(
            projectId: state.pathParameters['projectId']!,
            inspectionId: state.uri.queryParameters['inspectionId'],
            templateId: state.uri.queryParameters['templateId'],
          ),
        ),
        GoRoute(
          path: '/projects/:projectId/reports/runs/sample-progress',
          builder: (context, state) => ReportRunScreen(
            projectId: state.pathParameters['projectId']!,
            jobId: 'sample-progress',
            preview: _sampleProgress(),
          ),
        ),
        GoRoute(
          path: '/projects/:projectId/reports/runs/:jobId',
          builder: (context, state) {
            final query = state.uri.queryParameters;
            final edit = query['edit'] == '1';
            final details = query['details'] == '1';
            return ReportRunScreen(
              key: ValueKey('${state.pathParameters['jobId']}-${state.uri.query}'),
              projectId: state.pathParameters['projectId']!,
              jobId: state.pathParameters['jobId']!,
              editPreview: edit || details ? ReportEditPreview(
                editing: edit ? const ['{{BLOCK:AREA}}', 1, '{{DESCRIPTION}}'] : null,
                applyEdit: edit ? _sampleEdit : null,
                openDetails: details,
              ) : null,
            );
          },
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
