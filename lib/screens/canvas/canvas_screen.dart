import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/storage_service.dart';
import '../../utils/app_responsive.dart';
import '../../widgets/breadcrumb/breadcrumb.dart';
import '../../widgets/confirmation/confirmation_remove.dart';
import '../projects/controllers/project_controller.dart';
import '../projects/controllers/inspection_controller.dart';

import 'canvas_document_pane.dart';
import 'models/canvas_tab.dart';
import 'web/before_unload_guard.dart';
import 'widgets/canvas_tab_strip.dart';

class CanvasScreen extends StatefulWidget {
  final String documentId;
  final String projectId;
  final String inspectionId;
  final String page;
  final String? annotateImageKey;

  const CanvasScreen({
    super.key,
    required this.projectId,
    required this.inspectionId,
    required this.documentId,
    this.page = '1',
    this.annotateImageKey,
  });

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  late List<CanvasTab> _tabs;
  late String _activeDocumentId;
  final Map<String, GlobalKey<CanvasDocumentPaneState>> _paneKeys = {};
  final BeforeUnloadGuard _beforeUnloadGuard = BeforeUnloadGuard();

  String get _storageKey => 'canvas_tabs_${widget.inspectionId}';

  bool get _hasAnyUnsavedChanges =>
      _paneKeys.values.any((key) => key.currentState?.hasUnsavedChanges ?? false);

  @override
  void initState() {
    super.initState();
    _restoreOrSeedTabs();
    if (_tabs.isNotEmpty) _persistSession();

    inspectionController.fetchInspectionDetails(widget.inspectionId).then((_) {
      if (mounted) _pruneStaleTabs();
    });
    if (widget.projectId.isNotEmpty) {
      projectController.fetchProjectDetails(widget.projectId);
    }

    // 🚀 Warn on browser refresh/close/back if any tab has unsaved work. No-op
    // outside web. Browsers don't allow a custom-styled dialog here — this
    // triggers the browser's own generic "leave site?" confirmation, not ours.
    _beforeUnloadGuard.install(() => _hasAnyUnsavedChanges);
  }

  @override
  void dispose() {
    _beforeUnloadGuard.dispose();
    super.dispose();
  }

  // 🚀 Restores this inspection's open tabs from localStorage (survives a browser
  // refresh) instead of relying on the URL, which only ever encodes one document.
  void _restoreOrSeedTabs() {
    List<CanvasTab> restoredTabs = [];
    String? restoredActive;

    final String? saved = StorageService.getString(_storageKey);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        restoredTabs = (decoded['tabs'] as List<dynamic>? ?? [])
            .map(
              (t) => CanvasTab(
                documentId: t['documentId'].toString(),
                page: (t['page'] ?? '1').toString(),
              ),
            )
            .toList();
        restoredActive = decoded['active']?.toString();
      } catch (_) {
        restoredTabs = [];
      }
    }

    final bool hasInitialDocument = widget.documentId.isNotEmpty;

    if (restoredTabs.isEmpty) {
      // No saved session (first-ever visit for this inspection). Seed from whatever
      // document was just clicked, if any — otherwise there's nothing to show
      // (handled by the empty state in build()).
      _tabs = hasInitialDocument
          ? [CanvasTab(documentId: widget.documentId, page: widget.page)]
          : [];
      _activeDocumentId = widget.documentId;
      return;
    }

    _tabs = restoredTabs;

    if (hasInitialDocument &&
        !_tabs.any((t) => t.documentId == widget.documentId)) {
      // A document not part of the saved session was explicitly opened (e.g. a fresh
      // click from Inspection Details) — add it alongside the restored tabs and focus it.
      _tabs.add(CanvasTab(documentId: widget.documentId, page: widget.page));
      _activeDocumentId = widget.documentId;
    } else {
      // Plain refresh (no `extra` — it doesn't survive a hard reload): restore
      // whichever tab was actually focused before the refresh.
      final String fallback = hasInitialDocument
          ? widget.documentId
          : _tabs.first.documentId;
      _activeDocumentId =
          (restoredActive != null &&
              _tabs.any((t) => t.documentId == restoredActive))
          ? restoredActive
          : fallback;
    }
  }

  void _persistSession() {
    final payload = jsonEncode({
      'tabs': _tabs
          .map((t) => {'documentId': t.documentId, 'page': t.page})
          .toList(),
      'active': _activeDocumentId,
    });
    StorageService.setString(_storageKey, payload);
  }

  // Drops tabs for documents no longer assigned to this inspection, once the real
  // document list has loaded. The tab that was actually navigated to is never pruned.
  void _pruneStaleTabs() {
    final validIds = inspectionController.documents
        .map((d) => d['id'].toString())
        .toSet();
    if (validIds.isEmpty) return;

    final int before = _tabs.length;
    _tabs.removeWhere(
      (t) =>
          t.documentId != widget.documentId && !validIds.contains(t.documentId),
    );

    if (_tabs.isEmpty && widget.documentId.isNotEmpty) {
      _tabs = [CanvasTab(documentId: widget.documentId, page: widget.page)];
    }
    if (_tabs.isNotEmpty &&
        !_tabs.any((t) => t.documentId == _activeDocumentId)) {
      _activeDocumentId = _tabs.first.documentId;
    }

    if (_tabs.length != before) {
      setState(() {});
      _persistSession();
    }
  }

  GlobalKey<CanvasDocumentPaneState> _keyFor(String documentId) {
    return _paneKeys.putIfAbsent(
      documentId,
      () => GlobalKey<CanvasDocumentPaneState>(),
    );
  }

  // Mirrors CanvasTabStrip's own label lookup so the confirmation dialog can
  // name exactly which document(s) have unsaved work.
  String _documentNameFor(String documentId) {
    try {
      final doc = inspectionController.documents.firstWhere(
        (d) => d['id'].toString() == documentId,
      );
      final name = doc['document_name'];
      return (name != null && name.toString().trim().isNotEmpty)
          ? name.toString()
          : 'Document';
    } catch (_) {
      return 'Document';
    }
  }

  List<String> get _unsavedDocumentIds => _tabs
      .where((t) => _paneKeys[t.documentId]?.currentState?.hasUnsavedChanges ?? false)
      .map((t) => t.documentId)
      .toList();

  String _unsavedChangesDescription(List<String> documentIds) {
    final names = documentIds.map(_documentNameFor).toList();
    if (names.length == 1) {
      return "\"${names.first}\" has unsaved changes that will be permanently lost if you continue.";
    }
    final bulleted = names.map((n) => "• $n").join("\n");
    return "These documents have unsaved changes that will be permanently lost if you continue:\n$bulleted";
  }

  Future<bool> _confirmDiscardChanges(String description) async {
    bool shouldClose = false;

    await showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Exit Without Saving?",
        description: description,
        confirmLabel: "Exit",
        cancelLabel: "Cancel",
        confirmColor: Colors.red,
        onConfirm: () async {
          shouldClose = true;
        },
      ),
    );

    return shouldClose;
  }

  // Guards in-app navigation (breadcrumb taps) the same way tab/canvas closes
  // are guarded — only runs `navigate` once any unsaved changes are confirmed.
  Future<void> _guardedNavigate(VoidCallback navigate) async {
    final unsavedIds = _unsavedDocumentIds;
    if (unsavedIds.isEmpty) {
      navigate();
      return;
    }

    if (await _confirmDiscardChanges(_unsavedChangesDescription(unsavedIds)) && mounted) {
      navigate();
    }
  }

  Future<void> _requestCloseTab(String documentId) async {
    final bool hasUnsaved =
        _paneKeys[documentId]?.currentState?.hasUnsavedChanges ?? false;

    if (!hasUnsaved) {
      _closeTab(documentId);
      return;
    }

    if (await _confirmDiscardChanges(_unsavedChangesDescription([documentId])) && mounted) {
      _closeTab(documentId);
    }
  }

  // 🚀 Single "close the whole canvas" affordance — checks every open tab, not
  // just the active one, since the per-tab close buttons no longer live inside
  // the canvas itself.
  Future<void> _requestGlobalClose() async {
    final unsavedIds = _unsavedDocumentIds;
    if (unsavedIds.isEmpty) {
      _exitCanvas();
      return;
    }

    if (await _confirmDiscardChanges(_unsavedChangesDescription(unsavedIds)) && mounted) {
      _exitCanvas();
    }
  }

  void _closeTab(String documentId) {
    if (_tabs.length <= 1) {
      _exitCanvas();
      return;
    }

    final closingIndex = _tabs.indexWhere((t) => t.documentId == documentId);
    if (closingIndex == -1) return;

    final bool wasActive = _activeDocumentId == documentId;

    setState(() {
      _tabs.removeAt(closingIndex);
      _paneKeys.remove(documentId);
      if (wasActive) {
        _activeDocumentId =
            _tabs[(closingIndex - 1).clamp(0, _tabs.length - 1)].documentId;
      }
    });
    _persistSession();
  }

  void _exitCanvas() {
    StorageService.remove(_storageKey);

    final extra = GoRouterState.of(context).extra;

    if (extra is Function) {
      extra();
    } else if (extra is Map<String, dynamic> &&
        extra['onRefresh'] is Function) {
      extra['onRefresh']();
    }

    if (extra is Map<String, dynamic> && extra['returnUrl'] != null) {
      context.go(extra['returnUrl']);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _openTabPicker() async {
    final candidates = inspectionController.documents
        .where((d) => !_tabs.any((t) => t.documentId == d['id'].toString()))
        .toList();

    final theme = Theme.of(context);

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
          child: Container(
            color: theme.colorScheme.surfaceContainer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Open Document",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: candidates.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            "All documents are already open.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: candidates.length,
                          itemBuilder: (context, index) {
                            final doc = candidates[index];
                            final String docId = doc['id'].toString();
                            final String docName =
                                doc['document_name'] ?? 'Document ${index + 1}';

                            return ListTile(
                              leading: Icon(
                                Icons.picture_as_pdf_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              title: Text(docName),
                              onTap: () {
                                setState(() {
                                  _tabs.add(
                                    CanvasTab(documentId: docId, page: '1'),
                                  );
                                  _activeDocumentId = docId;
                                });
                                _persistSession();
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context, ThemeData theme) {
    final projectName =
        projectController.currentProject?.name ?? "Project Details";
    final projectId = projectController.currentProject?.id ?? "";

    String inspectionLabel = "Inspection details";
    final activeInspection = inspectionController.currentInspection;

    if (activeInspection != null) {
      final rawDate = activeInspection.createTime;
      final parsedDate = rawDate is DateTime
          ? rawDate
          : DateTime.tryParse(rawDate.toString());
      if (parsedDate != null) {
        inspectionLabel =
            "Inspection - ${DateFormat('dd MMM yyyy').format(parsedDate)}";
      }
    }

    return AppBreadcrumbs(
      items: [
        BreadcrumbItem(
          label: "Projects",
          onTap: () => _guardedNavigate(() => context.go('/projects')),
        ),
        BreadcrumbItem(
          label: projectName,
          onTap: () => _guardedNavigate(() {
            if (projectId.isNotEmpty) {
              context.go('/projects/details/$projectId/inspections');
            } else {
              Navigator.of(context).pop();
            }
          }),
        ),
        BreadcrumbItem(
          label: inspectionLabel,
          onTap: () => _guardedNavigate(() => Navigator.of(context).pop()),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(BuildContext context, ThemeData theme) {
    final bool isWeb = AppResponsive.isWeb;
    final double iconSize = isWeb ? 18 : 14;
    final double borderRadius = isWeb ? 8 : 5;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildBreadcrumb(context, theme)),
        Padding(
          padding: const EdgeInsets.only(top: 10, right: 4),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Tooltip(
              message: "Close",
              child: InkWell(
                borderRadius: BorderRadius.circular(borderRadius),
                onTap: _requestGlobalClose,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close_rounded, size: iconSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            "No document selected",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Open a document from Inspection Details to start annotating.",
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            projectController,
            inspectionController,
          ]),
          builder: (context, _) {
            if (_tabs.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
                    child: _buildHeaderRow(context, theme),
                  ),
                  Expanded(child: _buildEmptyState(theme)),
                ],
              );
            }

            final activeIndex = _tabs
                .indexWhere((t) => t.documentId == _activeDocumentId)
                .clamp(0, _tabs.length - 1);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: _buildHeaderRow(context, theme),
                ),
                CanvasTabStrip(
                  tabs: _tabs,
                  activeDocumentId: _activeDocumentId,
                  documents: inspectionController.documents,
                  onTabSelected: (id) {
                    setState(() => _activeDocumentId = id);
                    _persistSession();
                  },
                  onTabClosed: _requestCloseTab,
                  onAddTab: _openTabPicker,
                ),
                Expanded(
                  child: IndexedStack(
                    index: activeIndex,
                    children: _tabs
                        .map(
                          (tab) => CanvasDocumentPane(
                            key: _keyFor(tab.documentId),
                            projectId: widget.projectId,
                            inspectionId: widget.inspectionId,
                            documentId: tab.documentId,
                            page: tab.page,
                            annotateImageKey:
                                tab.documentId == widget.documentId
                                ? widget.annotateImageKey
                                : null,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
