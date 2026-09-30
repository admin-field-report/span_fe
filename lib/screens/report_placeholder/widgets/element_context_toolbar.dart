import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../widgets/form_components/compact_color_picker.dart';
import '../models/report_element.dart';

/// Floating pill-shaped toolbar shown above the selected element — mirrors the
/// contextual toolbar design used by the image-annotation canvas
/// (widgets/canvas/canvas.dart's `_buildContextualToolbar`/`_toolbarAction`).
class ElementContextToolbar extends StatelessWidget {
  final ReportElement element;
  final bool allowDelete;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onSecondaryTextChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<bool> onBoldChanged;
  final ValueChanged<bool> onItalicChanged;
  final ValueChanged<bool> onUnderlineChanged;
  final ValueChanged<TextAlign> onAlignChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<Color> onBackgroundColorChanged;
  final ValueChanged<double> onThicknessChanged;
  final VoidCallback onDelete;

  const ElementContextToolbar({
    super.key,
    required this.element,
    this.allowDelete = true,
    required this.onTextChanged,
    required this.onSecondaryTextChanged,
    required this.onFontSizeChanged,
    required this.onBoldChanged,
    required this.onItalicChanged,
    required this.onUnderlineChanged,
    required this.onAlignChanged,
    required this.onColorChanged,
    required this.onBackgroundColorChanged,
    required this.onThicknessChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = <Widget>[];

    if (element.type == ReportElementType.header || element.type == ReportElementType.footer) {
      // The header/footer container itself only exposes a background color —
      // its Logo/Title/Description children carry their own text formatting.
      actions.add(
        _action(
          context,
          theme,
          icon: Icons.format_color_fill_rounded,
          label: 'Background color',
          swatch: element.backgroundColor,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Background color', element.backgroundColor, onBackgroundColorChanged),
        ),
      );
    } else if (element.type.hasEditableText) {
      actions.addAll([
        _action(
          context,
          theme,
          icon: Icons.edit_note_rounded,
          label: 'Edit text',
          onTap: (_) => _showEditTextDialog(context, element.text, onTextChanged),
        ),
        _toggle(theme, icon: Icons.format_bold_rounded, label: 'Bold', active: element.isBold, onTap: () => onBoldChanged(!element.isBold)),
        _toggle(theme, icon: Icons.format_italic_rounded, label: 'Italic', active: element.isItalic, onTap: () => onItalicChanged(!element.isItalic)),
        _toggle(theme, icon: Icons.format_underline_rounded, label: 'Underline', active: element.isUnderline, onTap: () => onUnderlineChanged(!element.isUnderline)),
        _toolbarDivider(theme),
        _toggle(theme, icon: Icons.format_align_left_rounded, label: 'Align left', active: element.align == TextAlign.left, onTap: () => onAlignChanged(TextAlign.left)),
        _toggle(theme, icon: Icons.format_align_center_rounded, label: 'Align center', active: element.align == TextAlign.center, onTap: () => onAlignChanged(TextAlign.center)),
        _toggle(theme, icon: Icons.format_align_right_rounded, label: 'Align right', active: element.align == TextAlign.right, onTap: () => onAlignChanged(TextAlign.right)),
        _toolbarDivider(theme),
        _action(
          context,
          theme,
          icon: Icons.format_size_rounded,
          label: 'Font size',
          onTap: (anchor) => _showFontSizePopover(context, anchor, theme, element.fontSize, onFontSizeChanged),
        ),
        _action(
          context,
          theme,
          icon: Icons.format_color_text_rounded,
          label: 'Text color',
          swatch: element.color,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Text color', element.color, onColorChanged),
        ),
      ]);
    } else if (element.type == ReportElementType.infoBar) {
      actions.addAll([
        _action(
          context,
          theme,
          icon: Icons.edit_note_rounded,
          label: 'Edit text',
          onTap: (_) => _showEditInfoBarDialog(context, element.text, element.secondaryText, onTextChanged, onSecondaryTextChanged),
        ),
        _action(
          context,
          theme,
          icon: Icons.format_color_fill_rounded,
          label: 'Background color',
          swatch: element.backgroundColor,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Background color', element.backgroundColor, onBackgroundColorChanged),
        ),
        _action(
          context,
          theme,
          icon: Icons.format_color_text_rounded,
          label: 'Text color',
          swatch: element.color,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Text color', element.color, onColorChanged),
        ),
      ]);
    } else if (element.type == ReportElementType.bodyContent) {
      actions.addAll([
        _action(
          context,
          theme,
          icon: Icons.format_color_fill_rounded,
          label: 'Background color',
          swatch: element.backgroundColor,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Background color', element.backgroundColor, onBackgroundColorChanged),
        ),
        _action(
          context,
          theme,
          icon: Icons.format_color_text_rounded,
          label: 'Text color',
          swatch: element.color,
          onTap: (anchor) => _showColorPopover(context, anchor, theme, 'Text color', element.color, onColorChanged),
        ),
      ]);
    }

    if (actions.isNotEmpty) actions.add(_toolbarDivider(theme));
    if (allowDelete) {
      actions.add(_action(context, theme, icon: Icons.delete_outline_rounded, label: 'Delete', destructive: true, onTap: (_) => onDelete()));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.62)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _contextBadge(theme),
                _toolbarDivider(theme),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contextBadge(ThemeData theme) {
    return Tooltip(
      message: element.type.label,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.72),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.20)),
        ),
        child: Icon(element.type.icon, size: 17, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _toolbarDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
    );
  }

  Widget _action(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required void Function(GlobalKey anchorKey) onTap,
    Color? swatch,
    bool destructive = false,
  }) {
    final anchorKey = GlobalKey();
    final baseColor = destructive ? Colors.red : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(anchorKey),
          child: Container(
            key: anchorKey,
            width: 34,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 17, color: baseColor),
                if (swatch != null)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: swatch,
                        border: Border.all(color: theme.colorScheme.surface, width: 1.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: active ? theme.colorScheme.primaryContainer.withOpacity(0.5) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

Future<void> _showEditTextDialog(BuildContext context, String currentText, ValueChanged<String> onSaved) async {
  final controller = TextEditingController(text: currentText);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Edit Text"),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 3,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: "Type your text here...", border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
        TextButton(
          onPressed: () {
            onSaved(controller.text);
            Navigator.pop(dialogContext);
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
}

Future<void> _showEditInfoBarDialog(
  BuildContext context,
  String currentText,
  String currentSecondaryText,
  ValueChanged<String> onTextSaved,
  ValueChanged<String> onSecondaryTextSaved,
) async {
  final dateController = TextEditingController(text: currentText);
  final inspectorController = TextEditingController(text: currentSecondaryText);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Edit Info Bar"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateController,
              autofocus: true,
              decoration: const InputDecoration(labelText: "Date (left side)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: inspectorController,
              decoration: const InputDecoration(labelText: "Inspector Name (right side)", border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
        TextButton(
          onPressed: () {
            onTextSaved(dateController.text);
            onSecondaryTextSaved(inspectorController.text);
            Navigator.pop(dialogContext);
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
}

/// Generic anchored popover — positions a small floating card above/near the
/// tapped toolbar button, mirroring canvas.dart's `_showToolbarPopover`.
Future<void> _showAnchoredPopover({
  required BuildContext context,
  required GlobalKey anchorKey,
  required ThemeData theme,
  required String title,
  required IconData icon,
  required Widget Function(StateSetter setPopoverState) builder,
  double width = 232,
}) async {
  final anchorContext = anchorKey.currentContext;
  if (anchorContext == null) return;

  final renderObject = anchorContext.findRenderObject();
  final overlayState = Overlay.of(context, rootOverlay: true);
  final overlayObject = overlayState.context.findRenderObject();
  if (renderObject is! RenderBox || overlayObject is! RenderBox) return;

  final overlaySize = overlayObject.size;
  final targetOffset = renderObject.localToGlobal(Offset.zero, ancestor: overlayObject);
  final targetSize = renderObject.size;
  final targetCenterX = targetOffset.dx + targetSize.width / 2;

  final popoverWidth = math.min(width, math.max(180.0, overlaySize.width - 16.0));
  final maxLeft = math.max(8.0, overlaySize.width - popoverWidth - 8.0);
  final left = (targetCenterX - popoverWidth / 2).clamp(8.0, maxLeft).toDouble();
  final bottom = (overlaySize.height - targetOffset.dy + 8).clamp(8.0, math.max(8.0, overlaySize.height - 8.0)).toDouble();

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            left: left,
            bottom: bottom,
            child: Material(
              type: MaterialType.transparency,
              child: StatefulBuilder(
                builder: (context, setPopoverState) {
                  return Container(
                    width: popoverWidth,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.7)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 18, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(Icons.close, size: 15, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        builder(setPopoverState),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<void> _showFontSizePopover(
  BuildContext context,
  GlobalKey anchorKey,
  ThemeData theme,
  double currentSize,
  ValueChanged<double> onChanged,
) {
  double size = currentSize;
  return _showAnchoredPopover(
    context: context,
    anchorKey: anchorKey,
    theme: theme,
    title: 'Font size',
    icon: Icons.format_size_rounded,
    width: 220,
    builder: (setPopoverState) {
      return StatefulBuilder(
        builder: (context, _) {
          return Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () {
                  size = (size - 1).clamp(8, 72).toDouble();
                  onChanged(size);
                  setPopoverState(() {});
                },
              ),
              Expanded(child: Text('${size.toStringAsFixed(0)}px', textAlign: TextAlign.center)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () {
                  size = (size + 1).clamp(8, 72).toDouble();
                  onChanged(size);
                  setPopoverState(() {});
                },
              ),
            ],
          );
        },
      );
    },
  );
}


Future<void> _showColorPopover(
  BuildContext context,
  GlobalKey anchorKey,
  ThemeData theme,
  String title,
  Color currentColor,
  ValueChanged<Color> onChanged,
) {
  return _showAnchoredPopover(
    context: context,
    anchorKey: anchorKey,
    theme: theme,
    title: title,
    icon: Icons.palette_outlined,
    width: 260,
    builder: (setPopoverState) {
      return CompactColorPicker(
        initialColor: currentColor,
        showOpacity: true, // We probably want opacity for report placeholder elements too (e.g. background)
        onColorChanged: onChanged,
      );
    },
  );
}
