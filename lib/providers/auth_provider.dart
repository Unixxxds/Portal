import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/user.dart';
import '../data/secure_storage_service.dart';
import '../data/database_helper.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

enum AuthStatus { initial, checking, authenticated, unauthenticated }
enum AuthStep { email, code, cloudPassword }

class AuthProvider with ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  AuthStep _step = AuthStep.email;
  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  String? _cloudTempToken;
  String? _cloudPasswordHint;

  AuthStatus get status => _status;
  AuthStep get step => _step;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String? get cloudPasswordHint => _cloudPasswordHint;

  Future<void> checkAuth() async {
    _status = AuthStatus.checking;
    notifyListeners();

    try {
      final token = await SecureStorageService.instance.getToken();
      final userId = await SecureStorageService.instance.getCurrentUserId();

      if (token != null && token.isNotEmpty) {
        if (userId != null) {
          _currentUser = await DatabaseHelper.instance.getUser(userId);
        }
        _status = AuthStatus.authenticated;
        WebSocketService.instance.connect();
        // Refresh full profile & real Sparks balance from database asynchronously
        refreshCurrentUser();
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> sendCode(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.sendCode(email);
      _isLoading = false;
      if (res['success'] == true) {
        _step = AuthStep.code;
        notifyListeners();
        return true;
      }
      throw Exception(res['message'] ?? 'Не удалось отправить код');
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyCode(String email, String code) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.verifyCode(email, code);
      if (res['success'] == true) {
        // Проверка на облачный пароль (2FA)
        if (res['requiresCloudPassword'] == true) {
          _cloudTempToken = res['tempToken']?.toString();
          _cloudPasswordHint = res['hint']?.toString();
          _step = AuthStep.cloudPassword;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        // Прямой вход без 2FA
        if (res['token'] != null) {
          final token = res['token'].toString();
          await SecureStorageService.instance.saveToken(token);

          if (res['user'] != null && res['user'] is Map<String, dynamic>) {
            _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
            await SecureStorageService.instance.saveCurrentUserId(_currentUser!.id);
            final db = await DatabaseHelper.instance.database;
            await db.insert('users', _currentUser!.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          }

          _status = AuthStatus.authenticated;
          _isLoading = false;
          notifyListeners();

          WebSocketService.instance.connect();
          return true;
        }
      }
      throw Exception(res['error'] ?? res['message'] ?? 'Неверный ответ сервера');
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyCloudPassword(String email, String password) async {
    if (_cloudTempToken == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.verifyCloudPassword(_cloudTempToken!, password);
      if (res['success'] == true && res['token'] != null) {
        final token = res['token'].toString();
        await SecureStorageService.instance.saveToken(token);

        if (res['user'] != null && res['user'] is Map<String, dynamic>) {
          _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
          await SecureStorageService.instance.saveCurrentUserId(_currentUser!.id);
          final db = await DatabaseHelper.instance.database;
          await db.insert('users', _currentUser!.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        }

        _cloudTempToken = null;
        _cloudPasswordHint = null;
        _status = AuthStatus.authenticated;
        _isLoading = false;
        notifyListeners();

        WebSocketService.instance.connect();
        return true;
      } else {
        throw Exception(res['error'] ?? 'Неверный облачный пароль');
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void resetToEmailStep() {
    _step = AuthStep.email;
    _errorMessage = null;
    notifyListeners();
  }

  void returnToCodeStep() {
    _step = AuthStep.code;
    _errorMessage = null;
    notifyListeners();
  }

  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? username,
    String? description,
    String? avatar,
    String? bannerUrl,
  }) async {
    if (_currentUser == null) return;

    final cleanUsername = username != null
        ? username.replaceFirst(RegExp(r'^@+'), '').trim()
        : _currentUser!.username;

    final updated = _currentUser!.copyWith(
      firstName: firstName ?? _currentUser!.firstName,
      lastName: lastName ?? _currentUser!.lastName,
      username: cleanUsername,
      description: description ?? _currentUser!.description,
      avatar: avatar ?? _currentUser!.avatar,
      bannerUrl: bannerUrl ?? _currentUser!.bannerUrl,
    );

    _currentUser = updated;
    notifyListeners();

    // 1. Сохраняем в локальную SQLite БД
    await DatabaseHelper.instance.updateUserProfile(updated);

    // 2. Отправляем изменения на сервер через API
    try {
      final res = await ApiService.instance.updateProfile(
        firstName: updated.firstName,
        lastName: updated.lastName,
        username: cleanUsername,
        description: updated.description,
        avatar: updated.avatar,
        bannerUrl: updated.bannerUrl,
      );
      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        final serverUser = User.fromJson(res['user'] as Map<String, dynamic>);
        final finalUser = (serverUser.bannerUrl == null || serverUser.bannerUrl!.isEmpty) &&
                (updated.bannerUrl != null && updated.bannerUrl!.isNotEmpty)
            ? serverUser.copyWith(bannerUrl: updated.bannerUrl)
            : serverUser;
        _currentUser = finalUser;
        notifyListeners();
        await DatabaseHelper.instance.updateUserProfile(finalUser);
      }
    } catch (e) {
      debugPrint('Profile API sync note: $e');
      rethrow;
    }
  }

  void deductSparks(int amount) {
    if (_currentUser != null) {
      final currentSparks = _currentUser!.sparks;
      final newSparks = (currentSparks - amount) < 0 ? 0 : (currentSparks - amount);
      _currentUser = _currentUser!.copyWith(sparks: newSparks);
      notifyListeners();
      DatabaseHelper.instance.updateUserSparks(_currentUser!.id, newSparks);
    }
  }

  void setSparks(int sparks) {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(sparks: sparks);
      notifyListeners();
      DatabaseHelper.instance.updateUserSparks(_currentUser!.id, sparks);
    }
  }

  Future<void> refreshCurrentUser() async {
    try {
      final res = await ApiService.instance.getMe();
      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        final serverUser = User.fromJson(res['user'] as Map<String, dynamic>);
        _currentUser = serverUser;
        notifyListeners();
        await DatabaseHelper.instance.updateUserProfile(serverUser);
        await DatabaseHelper.instance.updateUserSparks(serverUser.id, serverUser.sparks);
      }
    } catch (e) {
      debugPrint('AuthProvider.refreshCurrentUser error: $e');
    }
  }

  Future<void> logout() async {
    WebSocketService.instance.disconnect();
    await SecureStorageService.instance.clearAll();
    await DatabaseHelper.instance.clearAll();
    _currentUser = null;
    _step = AuthStep.email;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
