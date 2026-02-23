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
    // Exact background and surface colors from your dashboard images
    final Color customBg = brightness == Brightness.dark 
        ? const Color(0xFF151A21)
        : const Color(0xFFF9FAFB);
        
    final Color customCard = brightness == Brightness.dark 
        ? const Color(0xFF1C252E) // Lighter Navy-Grey for Cards/Sidebar
        : Colors.white;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _targetColor,
      brightness: brightness,
      // CRITICAL: Set these explicitly to match your design
      surface: customCard, 
      surfaceContainer: customCard,
      background: customBg, // Use surface for newer Flutter versions
    ).copyWith(
      surface: customCard,
      onSurface: brightness == Brightness.dark ? Colors.white : const Color(0xFF212B36),
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
      
      // Explicitly set CardThemeData to use the customCard color
      cardTheme: CardThemeData(
        color: customCard,
        surfaceTintColor: Colors.transparent, // Prevents Material 3 from adding a purple tint
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.1)),
        ),
      ),
    );
  }
}