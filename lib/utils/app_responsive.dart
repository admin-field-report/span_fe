import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AppResponsive {
  // --- CORE PLATFORM CHECKS ---
  

  /// Checks if the app is running in a Web browser
  static bool get isWeb => kIsWeb;

  /// Checks if the app is running on Android (Safe for Web)
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Checks if the app is running on iOS (Safe for Web)
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Checks if the app is running on a Mobile device (Android or iOS)
  static bool get isMobile => isAndroid || isIOS;

  /// Checks if the app is running on a Desktop OS (Windows, macOS, or Linux)
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static String getPlatformName() {
    if (isWeb) return 'web';
    if (isAndroid) return 'android';
    if (isIOS) return 'ios';
    return 'unknown';
  }

  // --- SCREEN SIZE CHECKS ---
  // These are useful for responsive UI layout decisions

  static bool isMobileScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static bool isTabletScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 && MediaQuery.sizeOf(context).width < 1024;

  static bool isDesktopScreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1024;
}