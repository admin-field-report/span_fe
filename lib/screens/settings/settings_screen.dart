// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';
// import '../../core/theme_controller.dart';

// class SettingsScreen extends StatelessWidget {
//   const SettingsScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final List<Color> accentColors = [
//       const Color(0xFF00AB55), const Color(0xFF3366FF), const Color(0xFF7635DC),
//       const Color(0xFF2065D1), const Color(0xFFFDA92D), const Color(0xFFFF3030),
//     ];

//     final List<String> fonts = ["Public Sans", "Inter", "DM Sans", "Nunito"];

//     return ListenableBuilder(
//       listenable: themeController,
//       builder: (context, _) {
//         final theme = Theme.of(context);
//         final colorScheme = theme.colorScheme;
//         final size = MediaQuery.of(context).size;
//         final bool isDesktop = size.width > 900;
        
//         return Scaffold(
//           backgroundColor: theme.scaffoldBackgroundColor,
//           body: Center(
//             child: Container(
//               // Constraint content width on desktop to prevent awkward stretching
//               constraints: BoxConstraints(maxWidth: isDesktop ? 1000 : double.infinity),
//               child: ListView(
//                 padding: EdgeInsets.symmetric(
//                   horizontal: isDesktop ? 40 : 24, 
//                   vertical: 40
//                 ),
//                 children: [
//                   _buildHeader(theme, isDesktop),
//                   const SizedBox(height: 40),

//                   if (isDesktop) 
//                     // Desktop: Two-column layout
//                     Row(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Expanded(child: _buildLeftColumn(theme, colorScheme, accentColors)),
//                         const SizedBox(width: 40),
//                         Expanded(child: _buildRightColumn(theme, colorScheme, fonts)),
//                       ],
//                     )
//                   else 
//                     // Mobile: Single-column list
//                     Column(
//                       children: [
//                         _buildAppearanceSection(theme, colorScheme),
//                         const SizedBox(height: 32),
//                         _buildPresetSection(theme, colorScheme, accentColors),
//                         const SizedBox(height: 32),
//                         _buildFontSection(theme, fonts, theme),
//                         const SizedBox(height: 32),
//                         _buildSizeSection(theme, colorScheme),
//                       ],
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   // --- RESPONSIVE LAYOUT HELPERS ---

//   Widget _buildHeader(ThemeData theme, bool isDesktop) {
//     return Column(
//       crossAxisAlignment: isDesktop ? CrossAxisAlignment.center : CrossAxisAlignment.start,
//       children: [
//         Text(
//           "Settings", 
//           style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)
//         ),
//         Text(
//           "Manage your dashboard appearance and typography",
//           style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
//         ),
//       ],
//     );
//   }

//   Widget _buildLeftColumn(ThemeData theme, ColorScheme colorScheme, List<Color> accentColors) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildAppearanceSection(theme, colorScheme),
//         const SizedBox(height: 40),
//         _buildPresetSection(theme, colorScheme, accentColors),
//       ],
//     );
//   }

//   Widget _buildRightColumn(ThemeData theme, ColorScheme colorScheme, List<String> fonts) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildFontSection(theme, fonts, theme),
//         const SizedBox(height: 40),
//         _buildSizeSection(theme, colorScheme),
//       ],
//     );
//   }

//   // --- COMPONENT BLOCKS ---

//   Widget _buildAppearanceSection(ThemeData theme, ColorScheme colorScheme) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildSectionHeader("Appearance Mode", theme),
//         _buildThemeToggle(colorScheme),
//       ],
//     );
//   }

//   Widget _buildPresetSection(ThemeData theme, ColorScheme colorScheme, List<Color> accentColors) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildSectionHeader("Presets", theme),
//         _buildColorGrid(accentColors, colorScheme),
//       ],
//     );
//   }

//   Widget _buildFontSection(ThemeData theme, List<String> fonts, ThemeData currentTheme) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildSectionHeader("Font Family", theme),
//         _buildFontGrid(fonts, theme),
//       ],
//     );
//   }

//   Widget _buildSizeSection(ThemeData theme, ColorScheme colorScheme) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         _buildSectionHeader("Font Size", theme),
//         _buildSizeSlider(colorScheme, theme),
//       ],
//     );
//   }

//   // --- CORE UI ELEMENTS (Updated for better Desktop sizing) ---

//   Widget _buildThemeToggle(ColorScheme colorScheme) {
//     return Container(
//       padding: const EdgeInsets.all(6),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: Row(
//         children: [
//           _modeButton("Light", Icons.light_mode_outlined, ThemeMode.light),
//           _modeButton("Dark", Icons.dark_mode_outlined, ThemeMode.dark),
//           _modeButton("System", Icons.settings_brightness_outlined, ThemeMode.system),
//         ],
//       ),
//     );
//   }

//   Widget _modeButton(String label, IconData icon, ThemeMode mode) {
//     bool active = themeController.themeMode == mode;
//     return Expanded(
//       child: GestureDetector(
//         onTap: () => themeController.setThemeMode(mode),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 200),
//           padding: const EdgeInsets.symmetric(vertical: 14),
//           decoration: BoxDecoration(
//             color: active ? themeController.targetColor.withOpacity(0.1) : Colors.transparent,
//             borderRadius: BorderRadius.circular(12),
//             border: active ? Border.all(color: themeController.targetColor.withOpacity(0.3)) : null,
//           ),
//           child: Column(
//             children: [
//               Icon(icon, size: 20, color: active ? themeController.targetColor : Colors.grey),
//               const SizedBox(height: 4),
//               Text(label, style: TextStyle(
//                 color: active ? themeController.targetColor : Colors.grey, 
//                 fontSize: 12,
//                 fontWeight: active ? FontWeight.bold : FontWeight.normal
//               )),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildColorGrid(List<Color> colors, ColorScheme colorScheme) {
//     return Wrap(
//       spacing: 12,
//       runSpacing: 12,
//       children: colors.map((color) {
//         bool selected = themeController.targetColor.value == color.value;
//         return GestureDetector(
//           onTap: () => themeController.setTargetColor(color),
//           child: AnimatedContainer(
//             duration: const Duration(milliseconds: 200),
//             width: 48, height: 48,
//             decoration: BoxDecoration(
//               color: color,
//               shape: BoxShape.circle,
//               border: Border.all(
//                 color: selected ? colorScheme.onSurface : Colors.transparent,
//                 width: 2
//               ),
//               boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)] : null,
//             ),
//             child: selected ? const Icon(Icons.check, color: Colors.white) : null,
//           ),
//         );
//       }).toList(),
//     );
//   }

//   Widget _buildFontGrid(List<String> fonts, ThemeData theme) {
//     return GridView.builder(
//       shrinkWrap: true,
//       physics: const NeverScrollableScrollPhysics(),
//       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: 2, 
//         crossAxisSpacing: 12, 
//         mainAxisSpacing: 12, 
//         childAspectRatio: 2.5
//       ),
//       itemCount: fonts.length,
//       itemBuilder: (context, i) {
//         bool selected = themeController.fontFamily == fonts[i];
//         return InkWell(
//           onTap: () => themeController.setFontFamily(fonts[i]),
//           borderRadius: BorderRadius.circular(12),
//           child: Container(
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(12),
//               border: Border.all(color: selected ? themeController.targetColor : theme.colorScheme.outlineVariant),
//               color: selected ? themeController.targetColor.withOpacity(0.05) : null,
//             ),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Text("Aa", style: GoogleFonts.getFont(fonts[i], fontWeight: FontWeight.bold, fontSize: 18)),
//                 Text(fonts[i], style: const TextStyle(fontSize: 11)),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildSizeSlider(ColorScheme colorScheme, ThemeData theme) {
//     return Card(
//       elevation: 0,
//       color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
//       child: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           children: [
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Text("Small", style: theme.textTheme.labelSmall),
//                 Text("${themeController.fontSize.toInt()}px", 
//                   style: TextStyle(color: themeController.targetColor, fontWeight: FontWeight.bold)),
//                 Text("Large", style: theme.textTheme.labelLarge),
//               ],
//             ),
//             Slider(
//               value: themeController.fontSize,
//               min: 12, max: 24,
//               divisions: 12,
//               activeColor: themeController.targetColor,
//               onChanged: (val) => themeController.setFontSize(val),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSectionHeader(String title, ThemeData theme) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 16, left: 4),
//       child: Text(
//         title.toUpperCase(),
//         style: TextStyle(
//           color: theme.colorScheme.onSurface.withOpacity(0.5), 
//           fontSize: 12, 
//           fontWeight: FontWeight.bold, 
//           letterSpacing: 1.5
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Color> accentColors = [
      const Color(0xFF00AB55), const Color(0xFF3366FF), const Color(0xFF7635DC),
      const Color(0xFF2065D1), const Color(0xFFFDA92D), const Color(0xFFFF3030),
    ];

    final List<String> fonts = ["Public Sans", "Inter", "DM Sans", "Nunito"];

    return Drawer(
      width: 400, // Fixed width for desktop/mobile consistency
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          return SafeArea(
            child: Column(
              children: [
                // Drawer Header with Close Button
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

                // Vertical Scrollable Content
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

  // --- VERTICAL COMPONENT BLOCKS ---

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

  Widget _buildFontSection(ThemeData theme, List<String> fonts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Font Family", theme),
        _buildFontGrid(fonts, theme),
      ],
    );
  }

  Widget _buildSizeSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Font Size", theme),
        _buildSizeSlider(colorScheme, theme),
      ],
    );
  }

  // --- UI ELEMENTS ---

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

  Widget _buildFontGrid(List<String> fonts, ThemeData theme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, 
        crossAxisSpacing: 10, 
        mainAxisSpacing: 10, 
        childAspectRatio: 2.2
      ),
      itemCount: fonts.length,
      itemBuilder: (context, i) {
        bool selected = themeController.fontFamily == fonts[i];
        return InkWell(
          onTap: () => themeController.setFontFamily(fonts[i]),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? themeController.targetColor : theme.colorScheme.outlineVariant),
              color: selected ? themeController.targetColor.withOpacity(0.05) : null,
            ),
            child: Center(
              child: Text(fonts[i], 
                style: GoogleFonts.getFont(fonts[i], 
                  fontSize: 13, 
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal
                )
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSizeSlider(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("12px", style: theme.textTheme.labelSmall),
              Text("${themeController.fontSize.toInt()}px", 
                style: TextStyle(color: themeController.targetColor, fontWeight: FontWeight.bold)),
              Text("24px", style: theme.textTheme.labelSmall),
            ],
          ),
          Slider(
            value: themeController.fontSize,
            min: 12, max: 24,
            divisions: 12,
            activeColor: themeController.targetColor,
            onChanged: (val) => themeController.setFontSize(val),
          ),
        ],
      ),
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