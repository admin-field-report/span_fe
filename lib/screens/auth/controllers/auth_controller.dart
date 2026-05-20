import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api_service.dart';
import '../../../core/storage_service.dart';
import '../../../models/user.dart';

class AuthController extends ChangeNotifier {
  static final AuthController _instance = AuthController._internal();
  static AuthController get instance => _instance;
  AuthController._internal();

  bool _isRefreshing = false;

  // --- State Variables ---
  bool _isInitialized = false;
  UserModel? _user;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isCreatingUser = false;
  String? _errorMessageCreatingUser;
  Timer? _refreshTimer;
  String? _targetPath;
  bool _resetingPassword = false;
  String? _errorMessageResetingPassword;

  // --- Getters ---
  bool get isInitialized => _isInitialized;
  UserModel? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isCreatingUser => _isCreatingUser;
  String? get errorMessageCreatingUser => _errorMessageCreatingUser;
  String get targetPath => _targetPath ?? '/';
  bool get resetingPassword => _resetingPassword;
  String? get errorMessageResetingPassword => _errorMessageResetingPassword;

  bool _isExplicitLogout = false;
  bool get isExplicitLogout => _isExplicitLogout;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void setTargetPath(String path) {
    if (path != '/loading' && path != '/login') {
      _targetPath = path;
    }
  }

  void clearTargetPath() => _targetPath = null;

  // 🚀 REVISED: Manage Session with Retry Loop
  void manageSession() {
    final String? expiry = StorageService.getString(keyExpiresIn);
    if (expiry == null) return;

    final expiryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expiry));
    final refreshTime = expiryDate.subtract(const Duration(minutes: 2));
    final Duration delay = refreshTime.difference(DateTime.now());

    _refreshTimer?.cancel(); 

    if (delay.isNegative) {
      _executeBackgroundRefresh();
    } else {
      _refreshTimer = Timer(delay, () => _executeBackgroundRefresh());
    }
  }

  // 🚀 NEW: Background loop that retries if internet is down
  Future<void> _executeBackgroundRefresh() async {
    bool success = await refreshAccessToken();
    
    // If it failed (due to network) but they are still authenticated (not kicked out), retry in 30s!
    if (!success && _isAuthenticated) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(seconds: 30), () => _executeBackgroundRefresh());
    }
  }

  bool _isTokenExpired(String? expiry) {
    if (expiry == null) return true;
    final expiryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expiry));
    return DateTime.now().isAfter(expiryDate.subtract(const Duration(minutes: 1)));
  }

  bool _isNearExpiry(String? expiry) {
    if (expiry == null) return true;
    final expiryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expiry));
    return DateTime.now().isAfter(expiryDate.subtract(const Duration(minutes: 2)));
  }

  // 🚀 REVISED: Smart Boot Sequence
  Future<void> checkSession() async {
    final String? token = StorageService.getString(keyIdToken);
    final String? expiry = StorageService.getString(keyExpiresIn);

    if (token != null) {
      if (_isNearExpiry(expiry)) {
        await refreshAccessToken();
      }

      // Check if the token survived the refresh check
      if (StorageService.getString(keyIdToken) != null) {
        try {
          await fetchUserDetails();
        } catch (e) {
          debugPrint("User is offline or fetch failed, but keeping session alive.");
        }
        
        _isAuthenticated = true;
        manageSession();
      }
    } else {
      _isAuthenticated = false;
      await StorageService.clearAll(); 
    }

    _isInitialized = true;
    notifyListeners(); // Tells GoRouter the boot sequence is over!
  }
  
  // 🚀 REVISED: Crash-proof token refresh
  Future<bool> refreshAccessToken() async {
    if (_isRefreshing) return false; 
    
    final String? refreshToken = StorageService.getString(keyRefreshToken);
    if (refreshToken == null) {
      await logout();
      return false;
    }

    try {
      _isRefreshing = true;
      
      final response = await apiService.post('/user/refresh-token',{
        'refresh_token': refreshToken
      });

      // 400/401/403 means the token is permanently revoked. Log them out.
      if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
        await logout();
        return false;
      }
      
      // 500 means server error, just fail this attempt but don't log out.
      if (response.statusCode != 200) return false; 

      final responseData = jsonDecode(response.body);
      int expiresInSeconds = responseData['ExpiresIn'];
      DateTime expiryDate = DateTime.now().add(Duration(seconds: expiresInSeconds));

      await Future.wait([
        StorageService.setString(keyAccessToken, responseData['AccessToken']),
        StorageService.setString(keyIdToken, responseData['IdToken']),
        StorageService.setString(keyExpiresIn, expiryDate.millisecondsSinceEpoch.toString()),
        StorageService.setString(keyRefreshToken, responseData['RefreshToken']),
        StorageService.setString(keyTokenType, responseData['TokenType']),
      ]);
      
      manageSession(); 
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint("Network error refreshing token. Retaining session.");
      return false; 
    } finally {
      _isRefreshing = false;
    }
  }

  // 🚀 REVISED: Crash-proof user fetch
  Future<void> fetchUserDetails() async {
    try {
      final response = await apiService.post('/user/auth', {});

      if (response.statusCode == 200 || response.statusCode == 201) {
        final userData = UserModel.fromJson(jsonDecode(response.body));
        _user = userData;
        notifyListeners();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint("401/403 fetching user. Token revoked. Forcing logout.");
        await logout();
      } else {
        debugPrint("Server error fetching user details: ${response.statusCode}");
      }
    } catch (error) {
      debugPrint("Exception in fetchUserDetails: $error");
      // Do NOT rethrow. Do NOT set _user = null here (keep cached data if offline).
    }
  }

  Future<bool> signup({
    required String email,
    required String firstName,
    required String lastName,
    required String companyName,
  }) async {
    _isCreatingUser = true;
    _errorMessageCreatingUser = null;
    notifyListeners();

    try {
      final response = await apiService.post('/user/signup', {
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'company_name': companyName,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        _isCreatingUser = false;
        notifyListeners();
        return true;
      } else {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        _errorMessageCreatingUser = responseData['message'] ?? "Signup failed";
        _isCreatingUser = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessageCreatingUser = "An unexpected error occurred. Please try again.";
      _isCreatingUser = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> login(String email, String password) async {
    try {
      _isLoading = true;
      _errorMessage = '';
      notifyListeners();

      final loginRes = await apiService.post('/user/signin', {
        'email': email,
        'password': password,
      });

      if (loginRes.statusCode != 200) {
        final errorData = jsonDecode(loginRes.body);
        _errorMessage = errorData['message'] ?? 'An unknown error occurred';
        throw Exception(_errorMessage);
      }

      final loginData = jsonDecode(loginRes.body);
      int expiresInSeconds = loginData['ExpiresIn'];
      DateTime expiryDate = DateTime.now().add(Duration(seconds: expiresInSeconds));

      await Future.wait([
        StorageService.setString(keyAccessToken, loginData['AccessToken']),
        StorageService.setString(keyIdToken, loginData['IdToken']),
        StorageService.setString(keyExpiresIn, expiryDate.millisecondsSinceEpoch.toString()),
        StorageService.setString(keyRefreshToken, loginData['RefreshToken']),
        StorageService.setString(keyTokenType, loginData['TokenType']),
      ]);
      
      _isAuthenticated = true;
      
      await fetchUserDetails(); 
      
      manageSession(); 
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString().replaceAll('Exception: ', '');
      _isAuthenticated = false;
      _user = null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetPassword(String email, String password, String tempPassword) async {
    try {
      _resetingPassword = true;
      _errorMessageResetingPassword = '';
      notifyListeners();

      final response = await apiService.post('/user/signup-verify', {
        'email': email,
        'password': password,
        'temp_password': tempPassword
      });

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        _errorMessageResetingPassword = errorData['message'] ?? 'An unknown error occurred';
        throw Exception(_errorMessageResetingPassword);
      }

      final loginData = jsonDecode(response.body);
      int expiresInSeconds = loginData['ExpiresIn'];
      DateTime expiryDate = DateTime.now().add(Duration(seconds: expiresInSeconds));

      await Future.wait([
        StorageService.setString(keyAccessToken, loginData['AccessToken']),
        StorageService.setString(keyIdToken, loginData['IdToken']),
        StorageService.setString(keyExpiresIn, expiryDate.millisecondsSinceEpoch.toString()),
        StorageService.setString(keyRefreshToken, loginData['RefreshToken']),
        StorageService.setString(keyTokenType, loginData['TokenType']),
      ]);
      
      _isAuthenticated = true;
      
      // 🚀 THE FIX: Fetch the user profile here too!
      await fetchUserDetails();
      
      manageSession(); 
      notifyListeners();
    } catch (error) {
      _errorMessageResetingPassword = error.toString().replaceAll('Exception: ', '');
      _isAuthenticated = false;
      _user = null;
      rethrow;
    } finally {
      _resetingPassword = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isExplicitLogout = true;
    
    _refreshTimer?.cancel();
    await StorageService.clearAll();
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
    
    Future.microtask(() => _isExplicitLogout = false);
  }
}

final authController = AuthController.instance;