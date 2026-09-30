import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeController = ThemeController();

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  Color _targetColor = const Color(0xFF1C58F6);
  String _fontFamily = 'Public Sans';
  double _fontSize = 15.0; // Default size from your image

  ThemeMode get themeMode => _themeMode;
  Color get targetColor => _targetColor;
  String get fontFamily => _fontFamily;
  double get fontSize => _fontSize;

  // Built ThemeData is expensive (GoogleFonts text theme + ColorScheme.fromSeed),
  // and MaterialApp asks for both brightnesses on every rebuild — cache until a
  // theme input actually changes.
  final Map<Brightness, ThemeData> _themeCache = {};

  void _invalidateThemeCache() => _themeCache.clear();

  // --- 🚀 NEW: Load Preferences on Startup ---
  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Theme Mode (saved as string)
    final savedTheme = prefs.getString('themeMode');
    if (savedTheme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.toString() == savedTheme,
        orElse: () => ThemeMode.light,
      );
    }

    // Load Color (saved as int)
    final savedColor = prefs.getInt('targetColor');
    if (savedColor != null) {
      _targetColor = Color(savedColor);
    }

    // Load Font Family
    final savedFont = prefs.getString('fontFamily');
    if (savedFont != null) {
      _fontFamily = savedFont;
    }

    // Load Font Size
    final savedFontSize = prefs.getDouble('fontSize');
    if (savedFontSize != null) {
      _fontSize = savedFontSize;
    }

    _invalidateThemeCache();
    notifyListeners();
  }

  // --- 🚀 UPDATED: Save to Storage when Changed ---
  
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString());
  }

  Future<void> setTargetColor(Color color) async {
    _targetColor = color;
    _invalidateThemeCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('targetColor', color.value);
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    _invalidateThemeCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fontFamily', family);
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    _invalidateThemeCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', size);
  }

  // --- YOUR EXISTING THEME LOGIC ---
  ThemeData getTheme(Brightness brightness) {
    return _themeCache.putIfAbsent(brightness, () => _buildTheme(brightness));
  }

  ThemeData _buildTheme(Brightness brightness) {
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
        fontSizeFactor: _fontSize / 15.0, // Scale font size globally based on default
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