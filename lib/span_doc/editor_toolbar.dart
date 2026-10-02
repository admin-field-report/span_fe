import 'package:flutter/material.dart';

import 'rich_field_controller.dart';

/// The report editor's fixed toolbar, like the app's existing report editor:
/// bold, italic, underline, strike, clear formatting, bullets, numbers, and
/// undo / redo. Text tools work on the field being edited and are dimmed
/// when none is; the toolbar never takes focus from that field.
class ReportEditorToolbar extends StatelessWidget {
  final RichFieldController? active;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// Called after a text tool changes the active field.
  final VoidCallback? onChanged;

  const ReportEditorToolbar({
    super.key,
    required this.active,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final controller = active;
    Widget bar(BuildContext context) {
      final enabled = controller != null;
      Widget tool(IconData icon, String tip, {bool on = false, VoidCallback? onTap, Key? key}) {
        return Tooltip(
          message: tip,
          child: InkWell(
            key: key,
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: on ? const Color(0xFFE9ECEF) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 19, color: onTap == null ? const Color(0xFFCED4DA) : const Color(0xFF374151)),
            ),
          ),
        );
      }

      VoidCallback? text(void Function(RichFieldController c) action) => enabled
          ? () {
              action(controller);
              onChanged?.call();
            }
          : null;

      Widget divider() => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: const Color(0xFFDEE2E6));

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDEE2E6)),
        ),
        child: Row(
          children: [
            tool(Icons.format_bold_rounded, 'Bold', key: const ValueKey('tool-bold'), on: controller?.isActive(RichFormat.bold) ?? false, onTap: text((c) => c.toggle(RichFormat.bold))),
            tool(Icons.format_italic_rounded, 'Italic', key: const ValueKey('tool-italic'), on: controller?.isActive(RichFormat.italic) ?? false, onTap: text((c) => c.toggle(RichFormat.italic))),
            tool(Icons.format_underlined_rounded, 'Underline', key: const ValueKey('tool-underline'), on: controller?.isActive(RichFormat.underline) ?? false, onTap: text((c) => c.toggle(RichFormat.underline))),
            tool(Icons.format_strikethrough_rounded, 'Strikethrough', on: controller?.isActive(RichFormat.strike) ?? false, onTap: text((c) => c.toggle(RichFormat.strike))),
            tool(Icons.format_clear_rounded, 'Clear formatting', onTap: text((c) => c.clearFormatting())),
            divider(),
            tool(Icons.format_list_bulleted_rounded, 'Bulleted list', key: const ValueKey('tool-bullets'), on: enabled && controller.text.isNotEmpty && controller.isBulleted, onTap: text((c) => c.toggleBullets())),
            tool(Icons.format_list_numbered_rounded, 'Numbered list', on: enabled && controller.text.isNotEmpty && controller.isNumbered, onTap: text((c) => c.toggleNumbers())),
            const Spacer(),
            if (!enabled)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Text('Select text in the report to edit it', style: TextStyle(fontSize: 12, color: Color(0xFF868E96))),
              ),
            tool(Icons.undo_rounded, 'Undo', key: const ValueKey('tool-undo'), onTap: canUndo ? onUndo : null),
            tool(Icons.redo_rounded, 'Redo', onTap: canRedo ? onRedo : null),
          ],
        ),
      );
    }

    // Taps on the toolbar count as inside the field, so it keeps focus.
    return TextFieldTapRegion(
      child: controller == null ? bar(context) : ListenableBuilder(listenable: controller, builder: (context, _) => bar(context)),
    );
  }
}
