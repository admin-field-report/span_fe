import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../widgets/canvas/models/canvas_models.dart';
import '../../../widgets/canvas/widgets/canvas_painter.dart';

class CustomToolsPanel extends StatelessWidget {
  final List<CustomToolGroup> groups;
  final CustomTool? selectedTool;
  final Function(CustomTool) onToolSelected;
  final VoidCallback onClose;

  const CustomToolsPanel({
    super.key,
    required this.groups,
    required this.selectedTool,
    required this.onToolSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // Header
          // Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          //   decoration: BoxDecoration(
          //     color: theme.colorScheme.surfaceContainer,
          //     border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          //   ),
          //   child: Row(
          //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //     children: [
          //       Text("Custom Tools", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          //       IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onClose, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          //     ],
          //   ),
          // ),
          
          // Tool Groups List
          Expanded(
            child: groups.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return ExpansionTile(
                        title: Text(group.toolGroup, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        initiallyExpanded: index == 0,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: group.tools.length,
                              itemBuilder: (context, toolIndex) {
                                final tool = group.tools[toolIndex];
                                final isSelected = selectedTool?.toolId == tool.toolId;                              

                                return InkWell(
                                  onTap: () => onToolSelected(tool),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant, 
                                        width: isSelected ? 2 : 1
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      color: isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : Colors.transparent,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // 🌟 USING THE CENTERED PREVIEW PAINTER 🌟
                                        Expanded(
                                          child: tool.toolObjects.isNotEmpty 
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Container(
                                                    color: Colors.white, // Clean background for the thumbnail
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    child: CustomPaint(
                                                      painter: CenteredPreviewPainter(context, tool.toolObjects),
                                                    ),
                                                  ),
                                                )
                                              : const Center(
                                                  child: Icon(Icons.extension_outlined, size: 20, color: Colors.grey)
                                                ),
                                        ),
                                        
                                        const SizedBox(height: 4),
                                        Text(
                                          tool.toolName, 
                                          style: const TextStyle(fontSize: 9), 
                                          textAlign: TextAlign.center, 
                                          maxLines: 1, 
                                          overflow: TextOverflow.ellipsis
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        ],
                      );
                    },
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