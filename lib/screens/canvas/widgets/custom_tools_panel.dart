import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/canvas/widgets/canvas_painter.dart';
import 'empty_selection_card.dart';

class CustomToolsPanel extends StatefulWidget {
  final List<CustomToolGroup> groups;
  final CustomTool? selectedTool;
  final bool isSelectedToolLocked;
  final Function(CustomTool) onToolSelected;
  final VoidCallback onClose;
  final bool isLoading;
  final VoidCallback? onAddToolSets;
  final VoidCallback? onCreateToolSet;

  const CustomToolsPanel({
    super.key,
    required this.groups,
    required this.isLoading,
    required this.selectedTool,
    this.isSelectedToolLocked = false,
    required this.onToolSelected,
    required this.onClose,
    this.onAddToolSets,
    this.onCreateToolSet,
  });

  @override
  State<CustomToolsPanel> createState() => _CustomToolsPanelState();
}

class _CustomToolsPanelState extends State<CustomToolsPanel> {
  static const double _tileSize = 40;
  static const double _itemWidth = 50;

  // Keyed by group name; null until groups first arrive so the first group opens by default.
  Set<String>? _expandedGroups;

  Set<String> get _expanded {
    if (_expandedGroups == null && widget.groups.isNotEmpty) {
      _expandedGroups = {widget.groups.first.toolGroup};
    }
    return _expandedGroups ?? <String>{};
  }

  void _toggleGroup(String name) {
    setState(() {
      final expanded = _expanded;
      expanded.contains(name) ? expanded.remove(name) : expanded.add(name);
    });
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: CircularProgressIndicator(color: theme.colorScheme.primary),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: EmptySelectionCard(
        icon: Icons.category_outlined,
        title: "No Tool Set selected for this project.",
        actionLabel: "Add Tool Sets",
        onAction: widget.onAddToolSets,
        linkLabel: "Create a new Tool Set",
        onLink: widget.onCreateToolSet,
      ),
    );
  }

  Widget _buildContentState(ThemeData theme) {
    final groups = widget.groups;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      itemCount: groups.length,
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Divider(height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      itemBuilder: (context, index) {
        final group = groups[index];
        final isExpanded = _expanded.contains(group.toolGroup);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroupHeader(theme, group, isExpanded),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: group.tools.map((tool) => _buildToolItem(theme, tool)).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupHeader(ThemeData theme, CustomToolGroup group, bool isExpanded) {
    return InkWell(
      onTap: () => _toggleGroup(group.toolGroup),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                group.toolGroup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${group.tools.length}",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolItem(ThemeData theme, CustomTool tool) {
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = widget.selectedTool?.toolId == tool.toolId;

    // Tool drawings keep their own (often dark) stroke colours, so the tile stays light
    // in both themes; dark mode just uses a slightly dimmer shade so it doesn't glare.
    final tileColor = isDark ? const Color(0xFFD9DCE1) : const Color(0xFFF1F3F5);

    return SizedBox(
      width: _itemWidth,
      child: InkWell(
        onTap: () => widget.onToolSelected(tool),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: _tileSize,
                    height: _tileSize,
                    decoration: BoxDecoration(
                      color: tileColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.6),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: tool.toolObjects.isNotEmpty
                        ? IgnorePointer(
                            child: CustomPaint(painter: CenteredPreviewPainter(context, tool.toolObjects)),
                          )
                        : const Icon(Icons.extension_outlined, size: 20, color: Colors.grey),
                  ),
                  if (isSelected && widget.isSelectedToolLocked)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.primary),
                        ),
                        child: Icon(Icons.lock, size: 10, color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                tool.toolName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget bodyContent;
    if (widget.isLoading) {
      bodyContent = _buildLoadingState(theme);
    } else if (widget.groups.isEmpty) {
      bodyContent = _buildEmptyState(theme);
    } else {
      bodyContent = _buildContentState(theme);
    }

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: bodyContent,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text("Tool Sets", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (widget.onAddToolSets != null)
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                onPressed: widget.onAddToolSets,
                tooltip: "Add Tool Sets",
                padding: EdgeInsets.zero,
                iconSize: 18,
                style: IconButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: Icon(Icons.add, color: theme.colorScheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// PREVIEW CENTERING WRAPPER PAINTER 
// ==========================================
class CenteredPreviewPainter extends CustomPainter {
  final BuildContext context;
  final List<DrawingObject> objects;

  CenteredPreviewPainter(this.context, this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) return;

    // 1. Calculate the bounds
    Rect bounds = _calculateBounds(objects);

    // If the drawing is just a single point (like Text or a Dot), 
    // it has no width/height. Inflate it so math doesn't crash!
    if (bounds.width == 0 || bounds.height == 0) {
      bounds = bounds.inflate(100.0); 
    }

    // 2. Calculate scale to fit in the container
    double padding = 10.0; // Reduced padding slightly since the grid boxes are small
    double scaleX = (size.width - padding) / bounds.width;
    double scaleY = (size.height - padding) / bounds.height;
    double scale = math.min(scaleX, scaleY);

    if (scale > 1.0) scale = 1.0;

    canvas.save();
    
    // Clip the outer box so nothing bleeds into the UI
    canvas.clipRect(Offset.zero & size);
    
    // Center the drawing
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    // Pass a massive size to MainPainter to prevent accidental clipping
    Size massiveSize = Size(bounds.right + 2000, bounds.bottom + 2000);
    MainPainter(context, objects, null).paint(canvas, massiveSize);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Rect _calculateBounds(List<DrawingObject> objects) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void checkOffset(Offset offset) {
      if (offset.dx < minX) minX = offset.dx;
      if (offset.dy < minY) minY = offset.dy;
      if (offset.dx > maxX) maxX = offset.dx;
      if (offset.dy > maxY) maxY = offset.dy;
    }

    void processObject(DrawingObject obj) {
      checkOffset(obj.start);
      checkOffset(obj.end);

      if (obj.points != null && obj.points!.isNotEmpty) {
        for (var point in obj.points!) {
          checkOffset(point);
        }
      }

      if (obj.internalShapes != null && obj.internalShapes!.isNotEmpty) {
        for (var internalObj in obj.internalShapes!) {
          processObject(internalObj);
        }
      }
    }

    for (var obj in objects) {
      processObject(obj);
    }

    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}