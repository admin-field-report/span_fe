import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final themeController = ThemeController();

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _targetColor = const Color(0xFF00AB55);
  String _fontFamily = 'Public Sans';
  double _fontSize = 15.0; // Default size from your image

  ThemeMode get themeMode => _themeMode;
  Color get targetColor => _targetColor;
  String get fontFamily => _fontFamily;
  double get fontSize => _fontSize;

  void setThemeMode(ThemeMode mode) => { _themeMode = mode, notifyListeners() };
  void setTargetColor(Color color) => { _targetColor = color, notifyListeners() };
  void setFontFamily(String family) => { _fontFamily = family, notifyListeners() };
  void setFontSize(double size) => { _fontSize = size, notifyListeners() };

  ThemeData getTheme(Brightness brightness) {

    final isDark = brightness == Brightness.dark;

    // Exact background and surface colors from your dashboard images
    final Color customBg = isDark
        ? const Color(0xFF151A21)
        : const Color(0xFFF9FAFB);
        
    final Color surface = isDark
        ? const Color(0xFF28323D)
        : const Color(0xFFF4F6F8);

    final Color surfaceContainer = isDark
        ? const Color(0xFF1C252E)
        : Colors.white;

    final Color outline = isDark 
        ? const Color(0xFF2F363D) 
        : const Color(0xFFE5E7EB);

    final Color outlineVariant = isDark 
        ? const Color(0xFF36404A) 
        : const Color(0xFFEAECEF);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _targetColor,
      brightness: brightness,
      surface: surface, 
      surfaceContainer: surfaceContainer,
      outline: outline,
      outlineVariant: outlineVariant,
    ).copyWith(
      surface: surface,
      onSurface: isDark ? Colors.white : const Color(0xFF212B36),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      textTheme: GoogleFonts.getTextTheme(_fontFamily).apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      scaffoldBackgroundColor: customBg,
      
      cardTheme: CardThemeData(
        color: surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.1)),
        ),
      ),
    );
  }
}