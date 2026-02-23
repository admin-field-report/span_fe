import 'package:shared_preferences/shared_preferences.dart';

// --- Global Constants for Keys ---
const String keyAccessToken = 'AccessToken';
const String keyRefreshToken = 'RefreshToken';
const String keyIdToken = 'IdToken';
const String keyExpiresIn = 'ExpiresIn';
const String keyTokenType = 'TokenType';
const String keyUserData = 'userData';

class StorageService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Generic Common Methods ---

  /// Sets a string value for a specific key
  static Future<bool> setString(String key, String value) async {
    return await _prefs?.setString(key, value) ?? false;
  }

  /// Gets a string value for a specific key
  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  /// Sets an integer value (useful for ExpiresIn)
  static Future<bool> setInt(String key, int value) async {
    return await _prefs?.setInt(key, value) ?? false;
  }

  static int? getInt(String key) {
    return _prefs?.getInt(key);
  }

  // --- Utility Methods ---

  static Future<bool> remove(String key) async {
    return await _prefs?.remove(key) ?? false;
  }

  static Future<bool> clearAll() async {
    return await _prefs?.clear() ?? false;
  }
}