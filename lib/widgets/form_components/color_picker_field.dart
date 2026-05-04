import 'package:flutter/material.dart';
import 'color_picker.dart';
import '../button/button.dart';
import '../../utils/app_responsive.dart';

class ColorPickerField extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerField({
    super.key,
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // --- Color Preview Circle ---
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: currentColor,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outlineVariant, width: 2),
          ),
        ),
        const SizedBox(width: 16),
        
        // --- Open Picker Button ---
        Button(
          label: "Choose Color",
          icon: Icons.palette_outlined,
          variant: ButtonVariant.outline,
          onPressed: () {
            // Temporary color to hold state before saving
            Color tempColor = currentColor;
            
            // 🚀 Check if we are on Desktop or Mobile
            // ignore: undefined_class
            final isDesktop = AppResponsive.isDesktopScreen(context);

            // 🚀 We extract the content so we can share it between Dialog and BottomSheet
            Widget buildPickerContent(BuildContext modalContext) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- HEADER ---
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, isDesktop ? 24 : 16, 16),
                    color: theme.colorScheme.surface,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Pick a Color", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(modalContext), splashRadius: 20),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  
                  // --- CUSTOM COLOR PICKER ---
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: AppColorPicker(
                        initialColor: tempColor,
                        onColorChanged: (Color color) {
                          tempColor = color; 
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  
                  // --- FOOTER ---
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, isDesktop ? 16 : 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Button(
                          label: "Cancel",
                          variant: ButtonVariant.outline,
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                        const SizedBox(width: 12),
                        Button(
                          label: "Save Color",
                          onPressed: () {
                            onColorChanged(tempColor); // Push the new color back up!
                            Navigator.pop(modalContext);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // 🚀 RESPONSIVE TRIGGER
            if (isDesktop) {
              // DESKTOP: Show Floating Dialog
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) => Dialog(
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  surfaceTintColor: Colors.transparent,
                  clipBehavior: Clip.hardEdge,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400, maxHeight: 650),
                    child: buildPickerContent(dialogContext),
                  ),
                ),
              );
            } else {
              // MOBILE: Show Bottom Sheet
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (BuildContext sheetContext) => Container(
                  height: MediaQuery.of(context).size.height * 0.90, // Takes up 90% of mobile screen
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: buildPickerContent(sheetContext),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}