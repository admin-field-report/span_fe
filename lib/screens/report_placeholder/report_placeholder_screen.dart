import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/toast_service.dart';
import '../../widgets/button/button.dart';
import '../reports/controllers/report_controller.dart';
import 'models/report_element.dart';
import 'region_html_codec.dart';
import 'widgets/element_context_toolbar.dart';
import 'widgets/element_tools_panel.dart';

class ReportPlaceholderScreen extends StatefulWidget {
  /// When provided, the editor loads that report template's existing
  /// header/footer (via GET .../html) and Save patches them back. When null,
  /// it's a blank, unsaved scratch document (e.g. opened from the generic
  /// left-nav entry).
  final String? templateId;

  /// Shown as the AppBar title; falls back to a generic label when opened
  /// blank (no [templateId]).
  final String? templateName;

  const ReportPlaceholderScreen({super.key, this.templateId, this.templateName});

  @override
  State<ReportPlaceholderScreen> createState() => _ReportPlaceholderScreenState();
}

class _ReportPlaceholderScreenState extends State<ReportPlaceholderScreen> {
  static const double _pageWidth = 816;
  static const double _pageHeight = 732;
  static const double _footerHeight = 50;

  final List<ReportElement> _elements = [];
  String? _selectedId;
  int _idCounter = 0;

  bool _isLoadingTemplate = false;
  bool _isSaving = false;

  /// Tracked so the caller (e.g. the report details screen) only re-fetches
  /// when something was actually saved here, not on every plain back-nav.
  bool _didSave = false;

  bool get _hasHeader => _elements.any((e) => e.type == ReportElementType.header);
  bool get _hasBody => _elements.any((e) => e.type == ReportElementType.bodyContent);
  bool get _hasFooter => _elements.any((e) => e.type == ReportElementType.footer);

  @override
  void initState() {
    super.initState();
    _selectedId = null;

    if (widget.templateId != null) {
      _loadFromTemplate(widget.templateId!);
    }
    // Otherwise: start with a completely blank document.
  }

  Future<void> _loadFromTemplate(String templateId) async {
    setState(() => _isLoadingTemplate = true);

    try {
      final data = await reportController.fetchTemplateHtml(templateId);
      final header = parseRegionHtml(
        regionHtml: data['header_html'] as String?,
        regionType: ReportElementType.header,
        nextId: _nextId,
      );
      final footer = parseRegionHtml(
        regionHtml: data['footer_html'] as String?,
        regionType: ReportElementType.footer,
        nextId: _nextId,
      );

      if (!mounted) return;
      setState(() {
        _elements.clear();
        if (header != null) _elements.add(header);
        if (footer != null) _elements.add(footer);
        _isLoadingTemplate = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingTemplate = false);
      ToastService.show(context, message: "Failed to load report template.", type: ToastType.error);
    }
  }

  Future<void> _saveTemplate() async {
    if (widget.templateId == null) {
      ToastService.show(context, message: "Open this from a report to save.", type: ToastType.warning);
      return;
    }
    if (!_hasHeader) {
      ToastService.show(context, message: "Add a Header before saving.", type: ToastType.warning);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final headerHtml = buildRegionHtml(_header, pageWidth: _pageWidth);
      final footerHtml = buildRegionHtml(_footer, pageWidth: _pageWidth);
      await reportController.saveTemplateHtml(widget.templateId!, headerHtml: headerHtml, footerHtml: footerHtml);
      if (!mounted) return;
      _didSave = true;
      ToastService.show(context, message: "Report template saved successfully", type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      ToastService.show(context, message: "Failed to save report template.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  ReportElement? get _header => _elements.where((e) => e.type == ReportElementType.header).firstOrNull;
  ReportElement? get _footer => _elements.where((e) => e.type == ReportElementType.footer).firstOrNull;

  /// Header and footer heights are resizable per-report, so other elements' clamping
  /// needs to read the live values instead of fixed constants.
  double get _headerBandHeight => _header?.size.height ?? 0;
  double get _footerBandHeight => _footer?.size.height ?? _footerHeight;

  bool _showCenterGuide = false;
  bool _showLeftGuide = false;
  bool _showRightGuide = false;

  Set<String> get _addedBandElements {
    final set = <String>{};
    if (_header != null) {
      for (final c in _header!.children) {
        if (c.toolType != null) set.add(c.toolType!);
      }
    }
    if (_footer != null) {
      for (final c in _footer!.children) {
        if (c.toolType != null) set.add(c.toolType!);
      }
    }
    return set;
  }

  ReportElement? _findById(String? id) {
    if (id == null) return null;
    for (final e in _elements) {
      if (e.id == id) return e;
      for (final c in e.children) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  ReportElement? get _selectedElement => _findById(_selectedId);

  String _nextId() => 'el_${_idCounter++}_${DateTime.now().microsecondsSinceEpoch}';

  void _addElement(ReportElementType type) {
    if (type == ReportElementType.header) {
      if (_hasHeader) return;
      _addHeader();
      return;
    }
    if (type == ReportElementType.bodyContent) {
      if (_hasBody) return;
      _addBodyContent();
      return;
    }
    if (type == ReportElementType.footer) {
      if (_hasFooter) return;
      _addFooter();
      return;
    }

    final bodyCount = _elements.where((e) => !e.isPinned && !e.type.isBandElement).length;

    final defaultText = switch (type) {
      ReportElementType.header => '',
      ReportElementType.footer => 'Page footer text',
      ReportElementType.bodyContent => '{{BODY_CONTENT}}',
      ReportElementType.text => 'Custom Text Label',
      ReportElementType.logo => 'LOGO',
      ReportElementType.pageNumber => 'Page 1',
      ReportElementType.infoBar => '', // only ever created via _addHeader
    };

    // Logo defaults into the top-left of the header band; Page Number into the
    // bottom-right of the footer band. Both stay fully draggable afterwards.
    final defaultPosition = switch (type) {
      ReportElementType.logo => const Offset(20, 8),
      ReportElementType.pageNumber => Offset(_pageWidth - 100, _pageHeight - 30),
      _ => Offset(40, _headerBandHeight + 24 + (bodyCount * 48).toDouble()),
    };

    final element = ReportElement(
      id: _nextId(),
      type: type,
      text: defaultText,
      position: defaultPosition,
    );

    setState(() {
      _elements.add(element);
      _selectedId = element.id;
    });
  }

  /// Header is a small container rather than a single text block: it always
  /// comes with a Logo, Title and Description, each independently movable and
  /// stylable, positioned relative to the header's own top-left corner.
  void _addHeader({int style = 1}) {
    if (_hasHeader) {
      _elements.removeWhere((e) => e.type == ReportElementType.header);
    }

    final header = ReportElement(
      id: _nextId(),
      type: ReportElementType.header,
      text: '',
      backgroundColor: Colors.white,
      children: [],
    );

    if (style == 1) {
      // Style 1: Standard (Logo Left, Text Right, InfoBar Bottom)
      header.backgroundColor = Colors.white;
      header.size = const Size(0, 130);
      header.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.logo, toolType: 'logo', text: '', position: const Offset(24, 16)),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'companyName', text: 'COMPANY NAME', position: const Offset(110, 24), fontSize: 24, isBold: true, color: Colors.black87),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(112, 54), fontSize: 12, color: Colors.grey.shade700),
        ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: 'infoBar', text: 'Report Date', secondaryText: 'Inspector Name', backgroundColor: Colors.black, color: Colors.white),
      ]);
    } else if (style == 2) {
      // Centered Corporate: Logo Center Top, Name/Address Center Bottom, InfoBar Bottom
      header.backgroundColor = Colors.white;
      header.size = const Size(0, 190);
      header.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.logo, toolType: 'logo', text: '', position: Offset((_pageWidth - 70) / 2, 10)),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'companyName', text: 'COMPANY NAME', position: const Offset(0, 90), size: Size(_pageWidth, 0), fontSize: 22, isBold: true, color: Colors.blueGrey.shade900, align: TextAlign.center),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(0, 120), size: Size(_pageWidth, 0), fontSize: 11, color: Colors.grey.shade600, align: TextAlign.center),
        ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: 'infoBar', text: 'Report Date', secondaryText: 'Inspector Name', backgroundColor: Colors.blueGrey.shade50, color: Colors.blueGrey.shade900),
      ]);
    } else if (style == 3) {
      // Minimalist Text-Only (No Logo): Huge Company Name Left, Address Right, Minimal InfoBar
      header.backgroundColor = Colors.grey.shade50;
      header.size = const Size(0, 120);
      header.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'companyName', text: 'COMPANY NAME', position: const Offset(32, 24), fontSize: 28, isBold: true, color: Colors.black87),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(_pageWidth - 200, 24), fontSize: 11, color: Colors.black54, align: TextAlign.right),
        ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: 'infoBar', text: 'Report Date', secondaryText: 'Inspector Name', backgroundColor: Colors.grey.shade200, color: Colors.black87),
      ]);
    } else if (style == 4) {
      // Bold Banner: Dark Blue Background, Logo Left, "INSPECTION REPORT" Center, Address Right
      header.backgroundColor = Colors.indigo.shade900;
      header.size = const Size(0, 140);
      header.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.logo, toolType: 'logo', text: '', position: const Offset(24, 20)),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'companyName', text: 'COMPANY NAME', position: Offset((_pageWidth - 250) / 2, 35), fontSize: 24, isBold: true, color: Colors.white, align: TextAlign.center, size: Size(250, 0)),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: Offset((_pageWidth - 250) / 2, 70), fontSize: 14, color: Colors.indigo.shade200, align: TextAlign.center, size: Size(250, 0)),
        ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: 'infoBar', text: 'Report Date', secondaryText: 'Inspector Name', backgroundColor: Colors.indigo.shade800, color: Colors.white),
      ]);
    } else if (style == 5) {
      // Modern Split: Teal Accent, Logo Right, Company Info Left
      header.backgroundColor = Colors.white;
      header.size = const Size(0, 130);
      header.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'companyName', text: 'COMPANY NAME', position: const Offset(32, 24), fontSize: 26, isBold: true, color: Colors.teal.shade900),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(34, 60), fontSize: 12, color: Colors.teal.shade700),
        ReportElement(id: _nextId(), type: ReportElementType.logo, toolType: 'logo', text: '', position: const Offset(_pageWidth - 100, 16)),
        ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: 'infoBar', text: 'Report Date', secondaryText: 'Inspector Name', backgroundColor: Colors.teal.shade900, color: Colors.white),
      ]);
    }

    setState(() {
      _elements.add(header);
      _selectedId = header.id;
    });
  }

  void _addBandElement(String toolType) {
    if (toolType == 'logo' || toolType == 'companyName' || toolType == 'address' || toolType == 'infoBar') {
      if (!_hasHeader) {
        ToastService.show(context, message: "Please add a Header template first", type: ToastType.warning);
        return;
      }
      
      ReportElement element;
      if (toolType == 'logo') {
        element = ReportElement(id: _nextId(), type: ReportElementType.logo, toolType: toolType, text: '', position: const Offset(20, 12));
      } else if (toolType == 'companyName') {
        element = ReportElement(id: _nextId(), type: ReportElementType.text, toolType: toolType, text: 'COMPANY NAME', position: const Offset(20, 20), fontSize: 24, isBold: true, color: Colors.black87);
      } else if (toolType == 'address') {
        element = ReportElement(id: _nextId(), type: ReportElementType.text, toolType: toolType, text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(20, 60), fontSize: 12, color: Colors.grey.shade700);
      } else {
        element = ReportElement(id: _nextId(), type: ReportElementType.infoBar, toolType: toolType, text: 'Date', secondaryText: 'Inspector', backgroundColor: Colors.black, color: Colors.white);
      }

      setState(() {
        _header!.children.add(element);
        _selectedId = element.id;
      });
    } else if (toolType == 'pageNumber') {
      if (!_hasFooter) {
        ToastService.show(context, message: "Please add a Footer template first", type: ToastType.warning);
        return;
      }
      final element = ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: toolType, text: 'Page 1', position: Offset(_pageWidth - 100, (_footerBandHeight - 24) / 2));
      setState(() {
        _footer!.children.add(element);
        _selectedId = element.id;
      });
    }
  }

  void _addFooter({int style = 1}) {
    if (_hasFooter) {
      _elements.removeWhere((e) => e.type == ReportElementType.footer);
    }

    final footer = ReportElement(
      id: _nextId(),
      type: ReportElementType.footer,
      text: '',
      backgroundColor: Colors.white,
      children: [],
    );

    if (style == 1) {
      // Style 1: Standard (Left Text, Right Page Num)
      footer.size = const Size(0, 60);
      footer.backgroundColor = Colors.white;
      footer.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(24, 20), fontSize: 10, color: Colors.grey.shade700),
        ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: 'pageNumber', text: 'Page 1', position: Offset(_pageWidth - 100, 20), fontSize: 10, color: Colors.grey.shade700),
      ]);
    } else if (style == 2) {
      // Style 2: Centered (Center Page Num, Center Contact Info)
      footer.size = const Size(0, 70);
      footer.backgroundColor = Colors.grey.shade50;
      footer.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: 'pageNumber', text: 'Page 1', position: Offset((_pageWidth - 50) / 2, 16), fontSize: 11, isBold: true, color: Colors.blueGrey.shade800),
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: Offset((_pageWidth - 220) / 2, 40), fontSize: 9, color: Colors.grey.shade600, align: TextAlign.center, size: Size(220, 0)),
      ]);
    } else if (style == 3) {
      // Style 3: Minimal (Right Page Num only)
      footer.size = const Size(0, 50);
      footer.backgroundColor = Colors.white;
      footer.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: 'pageNumber', text: 'Page 1', position: Offset(_pageWidth - 80, 16), fontSize: 12, color: Colors.black54),
      ]);
    } else if (style == 4) {
      // Style 4: Bold Banner (Dark Blue, Left Text, Right Page Num)
      footer.size = const Size(0, 60);
      footer.backgroundColor = Colors.indigo.shade900;
      footer.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(24, 20), fontSize: 11, color: Colors.indigo.shade100),
        ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: 'pageNumber', text: 'Page 1', position: Offset(_pageWidth - 100, 20), fontSize: 11, color: Colors.white),
      ]);
    } else if (style == 5) {
      // Style 5: Modern Split (Teal accent, Left Address, Right Page Num)
      footer.size = const Size(0, 60);
      footer.backgroundColor = Colors.teal.shade900;
      footer.children.addAll([
        ReportElement(id: _nextId(), type: ReportElementType.text, toolType: 'address', text: '1234 Innovation Drive, Suite 100, Austin, TX 78701', position: const Offset(32, 20), fontSize: 11, color: Colors.teal.shade50),
        ReportElement(id: _nextId(), type: ReportElementType.pageNumber, toolType: 'pageNumber', text: 'Page 1', position: Offset(_pageWidth - 100, 20), fontSize: 11, isBold: true, color: Colors.white),
      ]);
    }

    setState(() {
      _elements.add(footer);
      _selectedId = footer.id;
    });
  }

  void _addBodyContent() {
    final body = ReportElement(
      id: _nextId(),
      type: ReportElementType.bodyContent,
      text: '{{BODY_CONTENT}} - Inspection Findings & Data',
      secondaryText: 'Actual field inspection items, tables, checklists, and photos will be injected into this container dynamically during report generation.',
      position: Offset(40, _headerBandHeight + 20),
      size: Size(_pageWidth - 80, (_pageHeight - _headerBandHeight - _footerBandHeight - 40).clamp(150.0, 500.0).toDouble()),
      backgroundColor: Colors.grey.shade50,
      color: Colors.blueGrey.shade800,
      fontSize: 16,
    );

    setState(() {
      _elements.add(body);
      _selectedId = body.id;
    });
  }



  void _removeElement(String id) {
    setState(() {
      _elements.removeWhere((e) => e.id == id);
      for (final e in _elements) {
        e.children.removeWhere((c) => c.id == id);
      }
      if (_selectedId == id) _selectedId = null;
    });
  }

  void _mutateSelected(void Function(ReportElement) mutate) {
    final element = _selectedElement;
    if (element == null) return;
    setState(() => mutate(element));
  }

  void _applySnapGuides(double newDx, double elementWidth, double maxDx) {
    const double snapThreshold = 6.0;
    _showCenterGuide = false;
    _showLeftGuide = false;
    _showRightGuide = false;

    // Center snap
    final centerX = _pageWidth / 2 - elementWidth / 2;
    if ((newDx - centerX).abs() < snapThreshold) {
      newDx = centerX;
      _showCenterGuide = true;
    }
    // Left margin snap (x = 40)
    if ((newDx - 40.0).abs() < snapThreshold) {
      newDx = 40.0;
      _showLeftGuide = true;
    }
    // Right margin snap (x = _pageWidth - 40 - width)
    final rightX = _pageWidth - 40.0 - elementWidth;
    if ((newDx - rightX).abs() < snapThreshold) {
      newDx = rightX;
      _showRightGuide = true;
    }
  }

  void _moveElement(ReportElement element, Offset delta) {
    setState(() {
      final elementWidth = element.size.width == 0 ? 120.0 : element.size.width;
      final elementHeight = element.size.height == 0 ? 20.0 : element.size.height;
      final maxDx = (_pageWidth - elementWidth).clamp(0.0, _pageWidth).toDouble();
      double newDx = (element.position.dx + delta.dx).clamp(0.0, maxDx).toDouble();
      final rawDy = element.position.dy + delta.dy;

      _applySnapGuides(newDx, elementWidth, maxDx);
      if (_showCenterGuide) newDx = _pageWidth / 2 - elementWidth / 2;
      if (_showLeftGuide) newDx = 40.0;
      if (_showRightGuide) newDx = _pageWidth - 40.0 - elementWidth;

      double newDy;
      if (element.type.isBandElement) {
        final headerMaxDy = (_headerBandHeight - elementHeight).clamp(0.0, _headerBandHeight).toDouble();
        final footerMinDy = _pageHeight - _footerBandHeight;
        final footerMaxDy = _pageHeight - elementHeight;
        final isInFooterHalf = rawDy > _pageHeight / 2;
        newDy = isInFooterHalf
            ? rawDy.clamp(footerMinDy, footerMaxDy).toDouble()
            : rawDy.clamp(0.0, headerMaxDy).toDouble();
      } else {
        final maxDy = (_pageHeight - _footerBandHeight - elementHeight).clamp(0.0, _pageHeight).toDouble();
        final minDy = _headerBandHeight + 8;
        newDy = rawDy.clamp(minDy, maxDy).toDouble();
      }

      element.position = Offset(newDx, newDy);
    });
  }

  /// Moves a child within its container band (header or footer).
  void _moveBandChild(ReportElement band, ReportElement child, Offset delta) {
    setState(() {
      final childWidth = child.size.width == 0 ? 120.0 : child.size.width;
      final childHeight = child.size.height == 0 ? 20.0 : child.size.height;
      final maxDx = (_pageWidth - childWidth).clamp(0.0, _pageWidth).toDouble();
      final maxDy = (band.size.height - childHeight).clamp(0.0, band.size.height).toDouble();
      double newDx = (child.position.dx + delta.dx).clamp(0.0, maxDx).toDouble();

      _applySnapGuides(newDx, childWidth, maxDx);
      if (_showCenterGuide) newDx = _pageWidth / 2 - childWidth / 2;
      if (_showLeftGuide) newDx = 40.0;
      if (_showRightGuide) newDx = _pageWidth - 40.0 - childWidth;

      child.position = Offset(
        newDx,
        (child.position.dy + delta.dy).clamp(0.0, maxDy).toDouble(),
      );
    });
  }

  void _resizeHeader(ReportElement header, double deltaY) {
    setState(() {
      header.size = Size(header.size.width, (header.size.height + deltaY).clamp(60.0, 240.0).toDouble());
    });
  }

  void _resizeFooter(ReportElement footer, double deltaY) {
    setState(() {
      // Dragging up (negative deltaY) increases footer height
      footer.size = Size(footer.size.width, (footer.size.height - deltaY).clamp(40.0, 200.0).toDouble());
    });
  }

  void _resizeBandChild(ReportElement band, ReportElement child, Offset delta) {
    setState(() {
      final maxWidth = (_pageWidth - child.position.dx).clamp(24.0, _pageWidth).toDouble();
      final maxHeight = (band.size.height - child.position.dy).clamp(24.0, band.size.height).toDouble();
      child.size = Size(
        (child.size.width + delta.dx).clamp(24.0, maxWidth).toDouble(),
        (child.size.height + delta.dy).clamp(24.0, maxHeight).toDouble(),
      );
    });
  }

  void _resizeBodyElement(ReportElement element, Offset delta) {
    setState(() {
      final maxWidth = (_pageWidth - element.position.dx).clamp(24.0, _pageWidth).toDouble();
      final maxHeight = (_pageHeight - element.position.dy).clamp(24.0, _pageHeight).toDouble();
      element.size = Size(
        (element.size.width + delta.dx).clamp(40.0, maxWidth).toDouble(),
        (element.size.height + delta.dy).clamp(40.0, maxHeight).toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final appBar = AppBar(
      centerTitle: false,
      title: Text(widget.templateName ?? "Report Placeholder"),
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      backgroundColor: theme.colorScheme.surface,
      // Custom back button (instead of the default implicit one) so the
      // caller can tell whether anything was actually saved here, rather
      // than re-fetching on every plain back navigation.
      leading: Navigator.canPop(context) ? BackButton(onPressed: () => context.pop(_didSave)) : null,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Button(
            label: "Save",
            icon: Icons.save_outlined,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _saveTemplate,
          ),
        ),
      ],
    );

    if (_isLoadingTemplate) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                "Loading report template...",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    final header = _header;
    final footer = _footer;
    final bodyElements = _elements.where((e) => !e.isPinned);
    final selected = _selectedElement;

    return Scaffold(
      appBar: appBar,
      body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElementToolsPanel(
                  hasHeader: _hasHeader,
                  hasFooter: _hasFooter,
                  addedBandElements: _addedBandElements,
                  onAddElement: _addElement,
                  onAddHeaderStyle: (style) => _addHeader(style: style),
                  onAddFooterStyle: (style) => _addFooter(style: style),
                  onAddBandElement: _addBandElement,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => setState(() {
                            _selectedId = null;
                            _showCenterGuide = false;
                            _showLeftGuide = false;
                            _showRightGuide = false;
                          }),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Container(
                                width: _pageWidth,
                                height: _pageHeight,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    if (header != null)
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: header.size.height,
                                        child: _HeaderBand(
                                          header: header,
                                          pageWidth: _pageWidth,
                                          selectedId: _selectedId,
                                          onSelectHeader: () => setState(() => _selectedId = header.id),
                                          onSelectChild: (id) => setState(() => _selectedId = id),
                                          onDragChild: (child, delta) => _moveBandChild(header, child, delta),
                                          onResizeChild: (child, delta) => _resizeBandChild(header, child, delta),
                                          onResizeHeight: (deltaY) => _resizeHeader(header, deltaY),
                                        ),
                                      ),
                                    if (footer != null)
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        height: _footerBandHeight,
                                        child: _FooterBand(
                                          footer: footer,
                                          pageWidth: _pageWidth,
                                          selectedId: _selectedId,
                                          onSelectFooter: () => setState(() => _selectedId = footer.id),
                                          onSelectChild: (id) => setState(() => _selectedId = id),
                                          onDragChild: (child, delta) => _moveBandChild(footer, child, delta),
                                          onResizeChild: (child, delta) => _resizeBandChild(footer, child, delta),
                                          onResizeHeight: (deltaY) => _resizeFooter(footer, deltaY),
                                        ),
                                      ),
                                    for (final element in bodyElements)
                                      Positioned(
                                        left: element.position.dx,
                                        top: element.position.dy,
                                        child: _DraggableElement(
                                          element: element,
                                          isSelected: element.id == _selectedId,
                                          maxWidth: _pageWidth - 80,
                                          onSelect: () => setState(() => _selectedId = element.id),
                                          onDrag: (delta) => _moveElement(element, delta),
                                          onResize: (element.type == ReportElementType.bodyContent ||
                                                  element.type == ReportElementType.logo)
                                              ? (delta) => _resizeBodyElement(element, delta)
                                              : null,
                                        ),
                                      ),
                                    if (_showCenterGuide)
                                      Positioned(
                                        left: _pageWidth / 2,
                                        top: 0,
                                        bottom: 0,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 1,
                                            color: Colors.blue.withOpacity(0.8),
                                          ),
                                        ),
                                      ),
                                    if (_showLeftGuide)
                                      Positioned(
                                        left: 40,
                                        top: 0,
                                        bottom: 0,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 1,
                                            color: Colors.blue.withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                    if (_showRightGuide)
                                      Positioned(
                                        left: _pageWidth - 40,
                                        top: 0,
                                        bottom: 0,
                                        child: IgnorePointer(
                                          child: Container(
                                            width: 1,
                                            color: Colors.blue.withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (selected != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Center(
                            child: ElementContextToolbar(
                              key: ValueKey(selected.id),
                              element: selected,
                              allowDelete: true,
                              onTextChanged: (val) => _mutateSelected((e) => e.text = val),
                              onSecondaryTextChanged: (val) => _mutateSelected((e) => e.secondaryText = val),
                              onFontSizeChanged: (val) => _mutateSelected((e) => e.fontSize = val),
                              onBoldChanged: (val) => _mutateSelected((e) => e.isBold = val),
                              onItalicChanged: (val) => _mutateSelected((e) => e.isItalic = val),
                              onUnderlineChanged: (val) => _mutateSelected((e) => e.isUnderline = val),
                              onAlignChanged: (val) => _mutateSelected((e) => e.align = val),
                              onColorChanged: (val) => _mutateSelected((e) => e.color = val),
                              onBackgroundColorChanged: (val) => _mutateSelected((e) => e.backgroundColor = val),
                              onThicknessChanged: (val) => _mutateSelected(
                                (e) => e.size = Size(e.size.width, val),
                              ),
                              onDelete: () => _removeElement(selected.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      ),
    );
  }
}


/// The header band: its own background, a bottom-edge drag handle to resize
/// its height, and the Logo/Title/Description children rendered on top.
class _HeaderBand extends StatelessWidget {
  final ReportElement header;
  final double pageWidth;
  final String? selectedId;
  final VoidCallback onSelectHeader;
  final ValueChanged<String> onSelectChild;
  final void Function(ReportElement child, Offset delta) onDragChild;
  final void Function(ReportElement child, Offset delta) onResizeChild;
  final ValueChanged<double> onResizeHeight;

  const _HeaderBand({
    required this.header,
    required this.pageWidth,
    required this.selectedId,
    required this.onSelectHeader,
    required this.onSelectChild,
    required this.onDragChild,
    required this.onResizeChild,
    required this.onResizeHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHeaderSelected = header.id == selectedId;
    final infoBar = header.children.where((c) => c.type == ReportElementType.infoBar).firstOrNull;
    final freeChildren = header.children.where((c) => c.type != ReportElementType.infoBar);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelectHeader,
          child: Container(
            width: pageWidth,
            height: header.size.height,
            decoration: BoxDecoration(
              color: header.backgroundColor,
              border: isHeaderSelected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
            ),
          ),
        ),
        for (final child in freeChildren)
          Positioned(
            left: child.position.dx,
            top: child.position.dy,
            child: _DraggableElement(
              element: child,
              isSelected: child.id == selectedId,
              maxWidth: pageWidth,
              onSelect: () => onSelectChild(child.id),
              onDrag: (delta) => onDragChild(child, delta),
              onResize: child.type == ReportElementType.logo
                  ? (delta) => onResizeChild(child, delta)
                  : null,
            ),
          ),
        // The info bar (Date / Inspector Name) is docked full-width along the
        // header's bottom edge rather than freely positioned like the others.
        if (infoBar != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: infoBar.size.height,
            child: _InfoBar(
              element: infoBar,
              isSelected: infoBar.id == selectedId,
              onSelect: () => onSelectChild(infoBar.id),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -4,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onResizeHeight(details.delta.dy),
              child: const SizedBox(height: 8),
            ),
          ),
        ),
      ],
    );
  }
}

/// The footer band: its own background, a top-edge drag handle to resize
/// its height, and child elements (Page Number, footer text, logo) rendered on top.
class _FooterBand extends StatelessWidget {
  final ReportElement footer;
  final double pageWidth;
  final String? selectedId;
  final VoidCallback onSelectFooter;
  final ValueChanged<String> onSelectChild;
  final void Function(ReportElement child, Offset delta) onDragChild;
  final void Function(ReportElement child, Offset delta) onResizeChild;
  final ValueChanged<double> onResizeHeight;

  const _FooterBand({
    required this.footer,
    required this.pageWidth,
    required this.selectedId,
    required this.onSelectFooter,
    required this.onSelectChild,
    required this.onDragChild,
    required this.onResizeChild,
    required this.onResizeHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFooterSelected = footer.id == selectedId;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelectFooter,
          child: Container(
            width: pageWidth,
            height: footer.size.height,
            decoration: BoxDecoration(
              color: footer.backgroundColor,
              border: isFooterSelected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
            ),
          ),
        ),
        for (final child in footer.children)
          Positioned(
            left: child.position.dx,
            top: child.position.dy,
            child: _DraggableElement(
              element: child,
              isSelected: child.id == selectedId,
              maxWidth: pageWidth,
              onSelect: () => onSelectChild(child.id),
              onDrag: (delta) => onDragChild(child, delta),
              onResize: child.type == ReportElementType.logo
                  ? (delta) => onResizeChild(child, delta)
                  : null,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: -4,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => onResizeHeight(details.delta.dy),
              child: const SizedBox(height: 8),
            ),
          ),
        ),
      ],
    );
  }
}

/// Header's bottom info strip — Date on the left, Inspector Name on the
/// right, sharing one background color and one text color.
class _InfoBar extends StatelessWidget {
  final ReportElement element;
  final bool isSelected;
  final VoidCallback onSelect;

  const _InfoBar({required this.element, required this.isSelected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(fontSize: element.fontSize, color: element.color);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: element.backgroundColor,
          border: isSelected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: Row(
          children: [
            Text(element.text, style: textStyle),
            const Spacer(),
            Text(element.secondaryText, style: textStyle),
          ],
        ),
      ),
    );
  }
}

class _DraggableElement extends StatelessWidget {
  final ReportElement element;
  final bool isSelected;
  final double maxWidth;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset>? onResize;

  const _DraggableElement({
    required this.element,
    required this.isSelected,
    required this.maxWidth,
    required this.onSelect,
    required this.onDrag,
    this.onResize,
  });

  Widget _content(BuildContext context, Border? selectionBorder) {
    return switch (element.type) {
      ReportElementType.bodyContent => Container(
          width: element.size.width,
          height: element.size.height,
          decoration: BoxDecoration(
            border: selectionBorder ?? Border.all(color: Colors.blueGrey.shade300, width: 2, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(8),
            color: element.backgroundColor == Colors.transparent ? Colors.grey.shade50 : element.backgroundColor,
          ),
          padding: const EdgeInsets.all(20),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_rounded, color: Colors.blueGrey.shade400, size: 36),
              const SizedBox(height: 10),
              Text(
                element.text,
                style: TextStyle(
                  fontSize: element.fontSize,
                  fontWeight: FontWeight.bold,
                  color: element.color,
                ),
                textAlign: TextAlign.center,
              ),
              if (element.secondaryText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  element.secondaryText,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ReportElementType.logo => Container(
          width: element.size.width,
          height: element.size.height,
          decoration: BoxDecoration(
            border: selectionBorder ?? Border.all(color: Colors.grey.shade400, width: 1.5),
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey.shade100,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_outlined, color: Colors.grey.shade500, size: 22),
              Text("Logo", style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
            ],
          ),
        ),
      _ => Container(
          width: element.size.width > 0 ? element.size.width : null,
          height: element.size.height > 0 ? element.size.height : null,
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(border: selectionBorder),
          alignment: element.size.width > 0 
              ? (element.align == TextAlign.center
                  ? Alignment.center
                  : element.align == TextAlign.right
                      ? Alignment.centerRight
                      : Alignment.centerLeft)
              : null,
          child: Text(
            element.text,
            textAlign: element.align,
            style: TextStyle(
              fontSize: element.fontSize,
              fontWeight: element.isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: element.isItalic ? FontStyle.italic : FontStyle.normal,
              decoration: element.isUnderline ? TextDecoration.underline : TextDecoration.none,
              color: element.color,
            ),
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionBorder = isSelected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null;

    final draggable = GestureDetector(
      onTap: onSelect,
      onPanUpdate: (details) {
        onSelect();
        onDrag(details.delta);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: _content(context, selectionBorder),
      ),
    );

    if (onResize == null || !isSelected) return draggable;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        draggable,
        Positioned(
          right: -6,
          bottom: -6,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            child: GestureDetector(
              onPanUpdate: (details) {
                onSelect();
                onResize!(details.delta);
              },
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

