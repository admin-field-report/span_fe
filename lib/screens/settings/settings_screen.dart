
import 'package:flutter/material.dart';
import '../../core/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Color> accentColors = [
      const Color(0xFF00AB55), const Color(0xFF3366FF), const Color(0xFF7635DC),
      const Color(0xFF2065D1), const Color(0xFFFDA92D), const Color(0xFFFF3030),
    ];

    return Drawer(
      width: 400,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Settings",
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.onSurface.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildAppearanceSection(theme, colorScheme),
                      const SizedBox(height: 32),
                      _buildPresetSection(theme, colorScheme, accentColors),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppearanceSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Appearance Mode", theme),
        _buildThemeToggle(colorScheme),
      ],
    );
  }

  Widget _buildPresetSection(ThemeData theme, ColorScheme colorScheme, List<Color> accentColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Presets", theme),
        _buildColorGrid(accentColors, colorScheme),
      ],
    );
  }

  Widget _buildThemeToggle(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _modeButton("Light", Icons.light_mode_outlined, ThemeMode.light),
          _modeButton("Dark", Icons.dark_mode_outlined, ThemeMode.dark),
          _modeButton("System", Icons.settings_brightness_outlined, ThemeMode.system),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, ThemeMode mode) {
    bool active = themeController.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => themeController.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? themeController.targetColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active ? [BoxShadow(color: themeController.targetColor.withOpacity(0.3), blurRadius: 8)] : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: active ? Colors.white : Colors.grey),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                color: active ? Colors.white : Colors.grey, 
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorGrid(List<Color> colors, ColorScheme colorScheme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: colors.map((color) {
        bool selected = themeController.targetColor.value == color.value;
        return GestureDetector(
          onTap: () => themeController.setTargetColor(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colorScheme.onSurface : Colors.transparent,
                width: 2
              ),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.4), 
          fontSize: 11, 
          fontWeight: FontWeight.w800, 
          letterSpacing: 1.2
        ),
      ),
    );
  }
}