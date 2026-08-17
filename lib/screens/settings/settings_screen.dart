import 'package:flutter/material.dart';
import '../../core/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Color> accentColors = [
      const Color(0xFF1C58F6), const Color(0xFF00AB55), const Color(0xFF7635DC),
      const Color(0xFFFDA92D), const Color(0xFFFF3030),
    ];

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          // Uses transparent to seamlessly blend into your MainScaffold's background
          backgroundColor: Colors.transparent, 
          
          // 🚀 Align topCenter keeps it at the top, but centers it horizontally on large screens
          body: Align(
            alignment: Alignment.topCenter, 
            child: ConstrainedBox(
              // 🚀 Prevents the UI from stretching infinitely on wide desktop monitors!
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // 🚀 Clean, page-level header (No close button!)
                  Text(
                    "Settings",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Manage your app appearance and preferences.",
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Sections
                  _buildAppearanceSection(theme, colorScheme),
                  const SizedBox(height: 40),
                  _buildPresetSection(theme, colorScheme, accentColors),
                ],
              ),
            ),
          ),
        );
      },
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
        color: colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
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
          padding: const EdgeInsets.symmetric(vertical: 16), // A bit more padding for desktop
          decoration: BoxDecoration(
            color: active ? themeController.targetColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active 
                ? [BoxShadow(color: themeController.targetColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] 
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: active ? Colors.white : Colors.grey),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(
                color: active ? Colors.white : Colors.grey, 
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w600
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorGrid(List<Color> colors, ColorScheme colorScheme) {
    return Wrap(
      spacing: 16, // Spaced out slightly more for a breathable desktop layout
      runSpacing: 16,
      children: colors.map((color) {
        bool selected = themeController.targetColor.value == color.value;
        return GestureDetector(
          onTap: () => themeController.setTargetColor(color),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48, // Slightly larger targets
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colorScheme.onSurface : Colors.transparent,
                width: 2
              ),
              boxShadow: selected 
                  ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] 
                  : [],
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.5), 
          fontSize: 12, 
          fontWeight: FontWeight.w800, 
          letterSpacing: 1.5
        ),
      ),
    );
  }
}