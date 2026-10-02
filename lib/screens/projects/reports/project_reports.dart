import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:field_report_fe/models/project.dart';
import 'package:field_report_fe/screens/projects/controllers/project_controller.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/api_service.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/widgets.dart';
import '../../../utils/app_responsive.dart';
import './create_report_screen.dart';
import './edit_report_screen.dart';
import './generation/report_generation_api.dart';
import './generation/widgets/span_progress_card.dart';
import '../../../utils/save_report_file.dart';
import './preview_report_pdf_screen.dart';

class ProjectReports extends StatefulWidget {
  final String projectId;

  const ProjectReports({super.key, required this.projectId});

  @override
  State<ProjectReports> createState() => _ProjectReportsState();
}

class _ProjectReportsState extends State<ProjectReports> {
  String _searchQuery = "";
  final ApiService _apiService = ApiService();

  // Reports currently downloading — shows a per-row spinner and blocks re-taps.
  final Set<String> _downloadingReportIds = {};

  // Report id -> the Span run that writes it. Reports Span writes (Word,
  // report_format 'docx') open in the Span report screen, never in the HTML
  // editor or PDF preview, which can't read them.
  Map<String, ReportRun> _runByReport = {};

  // Progress of runs still writing (job id -> 0..1), shown on their rows.
  final Map<String, double> _runProgress = {};
  Timer? _runPoll;

  Future<void> _loadSpanRuns() async {
    try {
      final runs = await ReportGenerationApi.listRuns(projectId: widget.projectId, limit: 100);
      if (!mounted) return;
      final wasRunning = _runByReport.values.where((r) => r.isRunning).map((r) => r.jobId).toSet();
      setState(() {
        _runByReport = {
          for (final run in runs)
            if (run.reportId != null) run.reportId!: run,
        };
      });
      final running = runs.where((r) => r.isRunning).toList();
      for (final run in running) {
        ReportGenerationApi.getEvents(run.jobId).then((events) {
          if (mounted) setState(() => _runProgress[run.jobId] = reportProgressFor(events.phaseKey));
        }).catchError((_) {});
      }
      // A run just finished: refresh the rows.
      if (wasRunning.any((id) => runs.any((r) => r.jobId == id && r.status == 'ready'))) {
        projectController.getAllReports(widget.projectId);
      }
      _runPoll?.cancel();
      _runPoll = running.isEmpty ? null : Timer(const Duration(seconds: 5), _loadSpanRuns);
    } catch (_) {
      // The rows still open: Span reports load their run on tap.
    }
  }

  @override
  void dispose() {
    _runPoll?.cancel();
    super.dispose();
  }

  bool _isSpanReport(ProjectReport report) => report.reportFormat == 'docx' || _runByReport.containsKey(report.id);

  Future<void> _openSpanReport(ProjectReport report) async {
    var run = _runByReport[report.id];
    if (run == null) {
      await _loadSpanRuns();
      run = _runByReport[report.id];
    }
    if (!mounted) return;
    if (run == null) {
      ToastService.show(context, type: ToastType.error, message: "This report's details couldn't be loaded. Refresh and try again.");
      return;
    }
    context.go('/projects/${widget.projectId}/reports/runs/${run.jobId}');
  }

  /// Span reports download as the current Word file (with any edits).
  Future<void> _downloadSpanReport(ProjectReport report) async {
    if (_downloadingReportIds.contains(report.id)) return;
    setState(() => _downloadingReportIds.add(report.id));
    try {
      var run = _runByReport[report.id];
      if (run == null) {
        await _loadSpanRuns();
        run = _runByReport[report.id];
      }
      if (run == null) throw Exception("This report's file couldn't be found. Refresh and try again.");
      if (run.isRunning) throw Exception('Span is still writing this report.');
      final detail = await ReportGenerationApi.getRun(run.jobId);
      final bytes = await ReportGenerationApi.getFileBytes(run.jobId, detail.reportPath ?? 'generated/filled.docx');
      final project = projectController.currentProject?.name;
      final saved = await saveReportFile(
        bytes,
        fileName: [if (project != null && project.isNotEmpty) project, run.inspectionName ?? report.name, run.templateName ?? 'Span'].join(' - '),
        extension: 'docx',
      );
      if (mounted) ToastService.show(context, type: ToastType.success, message: saved.isEmpty ? 'Downloaded.' : 'Saved to $saved');
    } catch (e) {
      if (mounted) ToastService.show(context, type: ToastType.error, message: e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloadingReportIds.remove(report.id));
    }
  }

  /// Span reports are listed as "Level 3 walkthrough report" (inspection + report).
  String _displayName(ProjectReport report) {
    final run = _runByReport[report.id];
    if (run?.inspectionName != null) return '${run!.inspectionName} report';
    return report.name;
  }

  // Same storage-permission flow as DocumentPdfExporter: ask once via
  // a dialog, send the user to settings when permanently denied, and require
  // a fresh tap after granting.
  Future<bool> _ensureStoragePermission() async {
    if (kIsWeb || !io.Platform.isAndroid) return true;

    var manageStatus = await Permission.manageExternalStorage.status;
    var storageStatus = await Permission.storage.status;
    if (manageStatus.isGranted || storageStatus.isGranted) return true;

    if (!mounted) return false;
    bool? allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Storage Permission Required"),
        content: const Text("We need storage access to save the downloaded PDF to your device. Please allow access."),
        actions: [
          Button(
            label: "Cancel",
            variant: ButtonVariant.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          Button(
            label: "Allow",
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (allow == true) {
      if (await Permission.storage.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await Permission.manageExternalStorage.request();
        await Permission.storage.request();
      }
    }

    return false;
  }

  Future<void> _downloadReportPdf(ProjectReport report) async {
    if (_downloadingReportIds.contains(report.id)) return;
    if (!await _ensureStoragePermission()) return;
    if (!mounted) return;

    setState(() => _downloadingReportIds.add(report.id));
    try {
      final response = await _apiService.get('/report/exportPdf/${report.id}');
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception("Failed to export PDF (Status: ${response.statusCode}).");
      }

      final decoded = jsonDecode(response.body);
      final String? signedUrl = decoded?['data']?['signedUrl'];
      if (signedUrl == null || signedUrl.isEmpty) {
        throw Exception("Invalid response format.");
      }

      final pdfRes = await http.get(Uri.parse(signedUrl));
      if (pdfRes.statusCode != 200) {
        throw Exception("Failed to download PDF (HTTP ${pdfRes.statusCode}).");
      }
      final Uint8List pdfBytes = pdfRes.bodyBytes;
      if (!mounted) return;

      String fileName = report.name.isNotEmpty ? report.name : 'report_${report.id}';
      final activeProject = projectController.currentProject;
      if (activeProject != null && activeProject.name.isNotEmpty) {
        fileName = '${activeProject.name} - $fileName';
      }
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

      String filePath = '';

      if (kIsWeb) {
        filePath = await FileSaver.instance.saveFile(
          name: fileName,
          bytes: pdfBytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        io.Directory? baseDirectory;
        if (io.Platform.isAndroid) {
          baseDirectory = io.Directory('/storage/emulated/0/Documents');
          if (!await baseDirectory.exists()) {
            baseDirectory = await getExternalStorageDirectory(); // fallback
          }
        } else {
          baseDirectory = await getApplicationDocumentsDirectory();
        }

        if (baseDirectory != null) {
          final io.Directory targetDirectory = io.Directory('${baseDirectory.path}/Span Inspect');
          try {
            if (!await targetDirectory.exists()) {
              await targetDirectory.create(recursive: true);
            }
            final io.File file = io.File('${targetDirectory.path}/$fileName.pdf');
            await file.writeAsBytes(pdfBytes, flush: true);
            filePath = file.path;
            await _scanMediaFile(filePath);
          } catch (e) {
            if (mounted) {
              ToastService.show(context, message: "Android blocked folder creation. Check permissions! Error: $e", type: ToastType.error);
            }
            final fallbackDir = await getExternalStorageDirectory();
            if (fallbackDir != null) {
              final io.File file = io.File('${fallbackDir.path}/$fileName.pdf');
              await file.writeAsBytes(pdfBytes, flush: true);
              filePath = file.path;
              await _scanMediaFile(filePath);
            }
          }
        }
      }

      if (mounted && filePath.isNotEmpty) {
        if (kIsWeb) {
          ToastService.show(context, message: "The PDF has been successfully downloaded.", type: ToastType.success);
        } else {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("Download Complete"),
                content: const Text("The PDF has been successfully downloaded."),
                actions: [
                  Button(
                    label: "Close",
                    variant: ButtonVariant.outline,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Button(
                    label: "Open File",
                    onPressed: () async {
                      Navigator.pop(context);
                      final result = await OpenFilex.open(filePath);
                      if (result.type != ResultType.done && mounted) {
                        ToastService.show(context, message: "Could not open file: ${result.message}", type: ToastType.error);
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      if (mounted) ToastService.show(context, message: "Download Error: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _downloadingReportIds.remove(report.id));
    }
  }

  Future<void> _scanMediaFile(String path) async {
    if (!io.Platform.isAndroid) return;
    try {
      const platform = MethodChannel('com.fieldreport.field_report_fe/mediascanner');
      await platform.invokeMethod('scanFile', {'path': path});
    } catch (e) {
      debugPrint('MediaScanner error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    projectController.getAllReports(widget.projectId);
    _loadSpanRuns();
  }

  List<ProjectReport> _getFilteredReports() {
    return projectController.reports.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> removeReport(BuildContext context, String id) async {
    try {
      final response = await _apiService.delete('/report/delete/$id');
      if (!context.mounted) return;

      if (response.statusCode == 200) {
        ToastService.show(context, 
          message: "Report deleted successfully", 
          type: ToastType.success
        );
        projectController.getAllReports(widget.projectId);
      } else {
        ToastService.show(context, 
          message: "Unexpected error occurred", 
          type: ToastType.error
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ToastService.show(context, 
        message: "Failed to delete report: $e", 
        type: ToastType.error
      );
    }
  }

  /// "Create Report" offers two paths for a project report: the Eve Word
  /// flow (fill a ready Word profile's `.docx` for selected inspections) or
  /// the existing HTML/skill-based flow ([CreateReportScreen]).
  void _showCreateReportChooser(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Report',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which report format to generate for this project.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _createOptionTile(
                  theme: theme,
                  icon: Icons.description_outlined,
                  title: 'Write with Span',
                  subtitle: "Span writes a Word report from an inspection, in your template's format.",
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    context.go('/projects/${widget.projectId}/reports/generate');
                  },
                ),
                const SizedBox(height: 12),
                _createOptionTile(
                  theme: theme,
                  icon: Icons.article_outlined,
                  title: 'HTML report',
                  subtitle: 'Existing flow: select a skill-based template and finalize.',
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    final bool? didCreate = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CreateReportScreen(projectId: widget.projectId)),
                    );
                    if (didCreate == true && mounted) {
                      projectController.getAllReports(widget.projectId);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createOptionTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ProjectReport report) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: ConfirmationDialog(
            title: "Remove Report",
            description: "Are you sure you want to remove this for '${report.name}'?",
            confirmLabel: "Remove",
            onConfirm: () async => await removeReport(context, report.id),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: projectController,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            // 🚀 1. Wrap the entire AppCard in Expanded
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.stretch, 
                  children: [
                    _buildTopToolbar(theme),                    
                    // 🚀 2. Wrap the Table in Expanded so it fills the rest of the card
                    Expanded(
                      child: ListenableBuilder(
                        listenable: projectController,
                        builder: (context, child) {
                          final displayData = _getFilteredReports();
                          return CommonTable<ProjectReport>(
                            isLoading: projectController.isReportLoading,
                            data: displayData,
                            showCheckboxes: false,
                            onRowTap: (report) {
                              if (_isSpanReport(report)) {
                                _openSpanReport(report);
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PreviewReportPdfScreen(
                                    reportId: report.id,
                                    reportName: report.name,
                                    isReadOnly: true,
                                  ),
                                  fullscreenDialog: true,
                                ),
                              );
                            },
                            columns: [
                              TableColumn(
                                title: 'Sr No.',
                                flex: 1,
                                minWidth: 60,
                                builder: (item) {
                                  final index = projectController.reports.indexOf(item) + 1;
                                  return Text(index.toString().padLeft(2, '0'));
                                },
                              ),
                              TableColumn(
                                title: 'Report Name',
                                flex: 2,
                                sortable: false,
                                builder: (item) => Text(
                                  _displayName(item),
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                              
                              // 🚀 3. Stacked Date & Time for consistency!
                              TableColumn(
                                title: 'Created Date',
                                flex: 2,
                                sortable: true,
                                sortValue: (item) => item.createDate,
                                builder: (item) => _runByReport[item.id]?.isRunning == true
                                    ? SpanRowProgress(
                                        key: ValueKey('row-progress-${item.id}'),
                                        label: 'Span is writing',
                                        progress: _runProgress[_runByReport[item.id]!.jobId] ?? 0.05,
                                      )
                                    : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('dd MMM yyyy').format(item.createDate),
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('hh:mm a').format(item.createDate),
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurfaceVariant, 
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // 🚀 4. ADDED isStickyRight to keep actions pinned!
                              TableColumn(
                                title: "Actions",
                                flex: 0,
                                minWidth: 140, // Perfect width for 3 icons
                                isStickyRight: true, // 🌟 The magic property
                                builder: (report) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _downloadingReportIds.contains(report.id)
                                        ? const Padding(
                                            padding: EdgeInsets.all(12.0),
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.download_outlined, size: 20),
                                            color: colorScheme.primary,
                                            tooltip: _isSpanReport(report) ? "Download Word" : "Download PDF",
                                            onPressed: () => _isSpanReport(report) ? _downloadSpanReport(report) : _downloadReportPdf(report),
                                          ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      color: colorScheme.primary,
                                      tooltip: "Edit Report",
                                      onPressed: () async {
                                        if (_isSpanReport(report)) {
                                          _openSpanReport(report);
                                          return;
                                        }
                                        final didUpdate = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditReportScreen(reportId: report.id),
                                          ),
                                        );

                                        if (didUpdate == true && mounted) {
                                          projectController.getAllReports(widget.projectId);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      color: colorScheme.error,
                                      tooltip: "Delete Report",
                                      onPressed: () => _confirmDelete(context, report),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      ),
                    )  
                  ]
                )
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    final isDesktop = AppResponsive.isDesktopScreen(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 16), 
      child: Row(
        children: [
          // Search Field
          Expanded(
            child: SearchField(
              // Let it fill space on mobile, constrain to 350 on desktop
              width: isDesktop ? 350 : double.infinity, 
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          if (isDesktop) const Spacer(),
          if (!isDesktop) const SizedBox(width: 12), // Add breathing room on mobile

          // Refresh Button (Desktop Only)
          if (isDesktop) ...[
            Tooltip(
              message: 'Refresh Reports',
              child: InkWell(
                onTap: projectController.isReportLoading ? null : () {
                  projectController.getAllReports(widget.projectId);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded, 
                    size: 20, 
                    color: colorScheme.onSurface.withOpacity(0.7)
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Create Report Button — opens the Word vs HTML chooser dialog.
          Button(
            label: isDesktop ? "Create Report" : "Create", 
            variant: ButtonVariant.filled,
            icon: Icons.add,
            onPressed: () => _showCreateReportChooser(context),
          ),
        ],
      )
    );
  }
}