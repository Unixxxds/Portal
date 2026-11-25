import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account_session.dart';
import '../models/user.dart';
import '../data/secure_storage_service.dart';
import '../data/database_helper.dart';
import '../services/api_service.dart';
import '../services/multi_account_service.dart';
import '../services/websocket_service.dart';
import '../services/push_notification_service.dart';
import 'chat_provider.dart';

enum AuthStatus { initial, checking, authenticated, unauthenticated }
enum AuthStep { email, code, cloudPassword, profileSetup }

class AuthProvider with ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  AuthStep _step = AuthStep.email;
  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  String? _cloudTempToken;
  String? _cloudPasswordHint;
  StreamSubscription? _wsSub;

  AuthProvider() {
    ApiService.instance.onUnauthorized = () {
      if (_status == AuthStatus.authenticated && !_isLoading) {
        logout();
      }
    };
  }

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
        ApiService.instance.setAuthToken(token);
        if (userId != null) {
          await DatabaseHelper.setActiveUserId(userId);
          _currentUser = await DatabaseHelper.instance.getUser(userId);
        }
        if (_currentUser != null &&
            !_currentUser!.profileCompleted &&
            _currentUser!.firstName.trim().isEmpty) {
          _status = AuthStatus.unauthenticated;
          _step = AuthStep.profileSetup;
          _isLoading = false;
          notifyListeners();
          return;
        }
        _status = AuthStatus.authenticated;
        await MultiAccountService.instance.init(currentUser: _currentUser, currentToken: token);
        WebSocketService.instance.connect();
        _listenWs();
        // Refresh full profile & real Sparks balance from database asynchronously
        refreshCurrentUser();
        PushNotificationService.instance.requestPermissionAndRegister();
      } else {
        _status = AuthStatus.unauthenticated;
        await MultiAccountService.instance.init();
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
          ApiService.instance.setAuthToken(token);
          await SecureStorageService.instance.saveToken(token);

          if (res['user'] != null && res['user'] is Map<String, dynamic>) {
            _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
            await DatabaseHelper.setActiveUserId(_currentUser!.id);
            await SecureStorageService.instance.saveCurrentUserId(_currentUser!.id);
            await DatabaseHelper.instance.insertUser(_currentUser!);

            await MultiAccountService.instance.saveAccount(
              AccountSession(
                userId: _currentUser!.id,
                token: token,
                user: _currentUser!,
                lastActive: DateTime.now(),
              ),
            );
          }

          // Проверка на нового пользователя (требуется настройка профиля)
          final isNewUser = _currentUser == null ||
              !_currentUser!.profileCompleted ||
              _currentUser!.firstName.trim().isEmpty;

          if (isNewUser) {
            _step = AuthStep.profileSetup;
            _status = AuthStatus.unauthenticated;
            _isLoading = false;
            notifyListeners();
            return true;
          }

          _status = AuthStatus.authenticated;
          _isLoading = false;
          notifyListeners();

          WebSocketService.instance.connect();
          _listenWs();
          PushNotificationService.instance.requestPermissionAndRegister();
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
        ApiService.instance.setAuthToken(token);
        await SecureStorageService.instance.saveToken(token);

        if (res['user'] != null && res['user'] is Map<String, dynamic>) {
          _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
          await DatabaseHelper.setActiveUserId(_currentUser!.id);
          await SecureStorageService.instance.saveCurrentUserId(_currentUser!.id);
          await DatabaseHelper.instance.insertUser(_currentUser!);

          await MultiAccountService.instance.saveAccount(
            AccountSession(
              userId: _currentUser!.id,
              token: token,
              user: _currentUser!,
              lastActive: DateTime.now(),
            ),
          );
        }

        _cloudTempToken = null;
        _cloudPasswordHint = null;

        // Проверка на нового пользователя
        final isNewUser = _currentUser == null ||
            !_currentUser!.profileCompleted ||
            _currentUser!.firstName.trim().isEmpty;

        if (isNewUser) {
          _step = AuthStep.profileSetup;
          _status = AuthStatus.unauthenticated;
          _isLoading = false;
          notifyListeners();
          return true;
        }

        _status = AuthStatus.authenticated;
        _isLoading = false;
        notifyListeners();

        WebSocketService.instance.connect();
        _listenWs();
        PushNotificationService.instance.requestPermissionAndRegister();
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

  Future<bool> completeProfileSetup({
    required String firstName,
    String? lastName,
    String? description,
    String? avatarPath,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String? avatarUrl = _currentUser?.avatar;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          final uploaded = await ApiService.instance.uploadAvatar(File(avatarPath));
          if (uploaded.isNotEmpty) {
            avatarUrl = uploaded;
          }
        } catch (e) {
          debugPrint('Upload avatar error in setup: $e');
        }
      }

      final res = await ApiService.instance.updateProfile(
        firstName: firstName.trim(),
        lastName: (lastName ?? '').trim(),
        description: (description ?? '').trim(),
        avatar: avatarUrl,
      );

      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
      } else {
        final currentId = _currentUser?.id ?? (await SecureStorageService.instance.getCurrentUserId()) ?? 0;
        _currentUser = (_currentUser ?? User(
          id: currentId,
          firstName: firstName.trim(),
          lastName: (lastName ?? '').trim(),
          username: '',
          avatar: avatarUrl ?? '',
        )).copyWith(
          firstName: firstName.trim(),
          lastName: (lastName ?? '').trim(),
          description: (description ?? '').trim(),
          avatar: avatarUrl ?? '',
          profileCompleted: true,
        );
      }

      if (_currentUser != null) {
        await DatabaseHelper.setActiveUserId(_currentUser!.id);
        await SecureStorageService.instance.saveCurrentUserId(_currentUser!.id);
        await DatabaseHelper.instance.insertUser(_currentUser!);

        final token = await SecureStorageService.instance.getToken();
        if (token != null) {
          await MultiAccountService.instance.saveAccount(
            AccountSession(
              userId: _currentUser!.id,
              token: token,
              user: _currentUser!,
              lastActive: DateTime.now(),
            ),
          );
        }
      }

      _status = AuthStatus.authenticated;
      _step = AuthStep.email;
      _isLoading = false;
      notifyListeners();

      WebSocketService.instance.connect();
      _listenWs();
      PushNotificationService.instance.requestPermissionAndRegister();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void cancelProfileSetup() {
    _step = AuthStep.email;
    _errorMessage = null;
    SecureStorageService.instance.clearAll();
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
    int? pinnedChannelId,
    bool clearPinnedChannel = false,
  }) async {
    if (_currentUser == null) return;

    final cleanUsername = username != null
        ? username.replaceFirst(RegExp(r'^@+'), '').trim()
        : _currentUser!.username;

    final effectivePinnedChannelId = clearPinnedChannel
        ? null
        : (pinnedChannelId ?? _currentUser!.pinnedChannelId);

    final updated = _currentUser!.copyWith(
      firstName: firstName ?? _currentUser!.firstName,
      lastName: lastName ?? _currentUser!.lastName,
      username: cleanUsername,
      description: description ?? _currentUser!.description,
      avatar: avatar ?? _currentUser!.avatar,
      bannerUrl: bannerUrl ?? _currentUser!.bannerUrl,
      pinnedChannelId: effectivePinnedChannelId,
      clearPinnedChannel: clearPinnedChannel,
    );

    _currentUser = updated;
    notifyListeners();

    // 1. Сохраняем в локальную SQLite БД и SecureStorage
    await DatabaseHelper.instance.updateUserProfile(updated);
    await SecureStorageService.instance.saveUserPinnedChannelId(updated.id, effectivePinnedChannelId);

    // 2. Отправляем изменения на сервер через API
    try {
      final res = await ApiService.instance.updateProfile(
        firstName: updated.firstName,
        lastName: updated.lastName,
        username: cleanUsername,
        description: updated.description,
        avatar: updated.avatar,
        bannerUrl: updated.bannerUrl,
        pinnedChannelId: effectivePinnedChannelId,
      );
      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        final serverUser = User.fromJson(res['user'] as Map<String, dynamic>);
        var finalUser = (serverUser.bannerUrl == null || serverUser.bannerUrl!.isEmpty) &&
                (updated.bannerUrl != null && updated.bannerUrl!.isNotEmpty)
            ? serverUser.copyWith(bannerUrl: updated.bannerUrl)
            : serverUser;
        if (finalUser.pinnedChannelId == null && effectivePinnedChannelId != null && !clearPinnedChannel) {
          finalUser = finalUser.copyWith(pinnedChannelId: effectivePinnedChannelId);
        }
        _currentUser = finalUser;
        notifyListeners();
        await DatabaseHelper.instance.updateUserProfile(finalUser);
      }
    } catch (e) {
      debugPrint('Profile API sync note: $e');
      rethrow;
    }
  }

  Future<void> updateProfileColor(String colorId) async {
    if (_currentUser == null) return;
    final isDefault = colorId.isEmpty || colorId == 'default';
    final updated = _currentUser!.copyWith(
      profileColor: isDefault ? '' : colorId,
      clearProfileColor: isDefault,
    );
    _currentUser = updated;
    notifyListeners();

    await DatabaseHelper.instance.updateUserProfile(updated);
    await SecureStorageService.instance.saveUserProfileColor(updated.id, colorId);
    await MultiAccountService.instance.updateUser(updated);

    try {
      await ApiService.instance.updateProfileColor(colorId);
    } catch (_) {}
    try {
      await ApiService.instance.updateProfile(
        firstName: updated.firstName,
        lastName: updated.lastName,
        username: updated.username,
        avatar: updated.avatar,
        profileColor: colorId,
      );
    } catch (e) {
      debugPrint('updateProfileColor API error: $e');
    }
  }

  Future<void> updatePrivacy({
    String? privacyLastSeen,
    String? privacySparks,
    String? privacyAvatar,
  }) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(
      privacyLastSeen: privacyLastSeen ?? _currentUser!.privacyLastSeen,
      privacySparks: privacySparks ?? _currentUser!.privacySparks,
      privacyAvatar: privacyAvatar ?? _currentUser!.privacyAvatar,
    );
    _currentUser = updated;
    notifyListeners();

    await DatabaseHelper.instance.updateUserProfile(updated);
    await MultiAccountService.instance.updateUser(updated);

    try {
      final res = await ApiService.instance.updatePrivacySettings(
        privacyLastSeen: privacyLastSeen,
        privacySparks: privacySparks,
        privacyAvatar: privacyAvatar,
      );
      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        final serverUser = User.fromJson(res['user'] as Map<String, dynamic>);
        _currentUser = serverUser;
        notifyListeners();
        await DatabaseHelper.instance.updateUserProfile(serverUser);
        await MultiAccountService.instance.updateUser(serverUser);
      }
    } catch (e) {
      debugPrint('updatePrivacy API error: $e');
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
      MultiAccountService.instance.updateUser(_currentUser!);
    }
  }

  void setSparks(int sparks) {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(sparks: sparks);
      notifyListeners();
      DatabaseHelper.instance.updateUserSparks(_currentUser!.id, sparks);
      MultiAccountService.instance.updateUser(_currentUser!);
    }
  }

  void deductArtifacts(int amount) {
    if (_currentUser != null) {
      final current = _currentUser!.artifacts;
      final updated = (current - amount) < 0 ? 0 : (current - amount);
      _currentUser = _currentUser!.copyWith(artifacts: updated);
      notifyListeners();
      DatabaseHelper.instance.updateUserProfile(_currentUser!);
    }
  }

  void setArtifacts(int artifacts) {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(artifacts: artifacts);
      notifyListeners();
      DatabaseHelper.instance.updateUserProfile(_currentUser!);
    }
  }

  Future<void> refreshCurrentUser() async {
    try {
      final res = await ApiService.instance.getMe();
      if (res['user'] != null && res['user'] is Map<String, dynamic>) {
        var serverUser = User.fromJson(res['user'] as Map<String, dynamic>);
        if (serverUser.pinnedChannelId == null) {
          final cachedChannelId = await SecureStorageService.instance.getUserPinnedChannelId(serverUser.id);
          if (cachedChannelId != null && cachedChannelId > 0) {
            serverUser = serverUser.copyWith(pinnedChannelId: cachedChannelId);
          }
        }
        if (serverUser.profileColor == null || serverUser.profileColor!.isEmpty) {
          final cachedColor = await SecureStorageService.instance.getUserProfileColor(serverUser.id);
          if (cachedColor != null && cachedColor.isNotEmpty) {
            serverUser = serverUser.copyWith(profileColor: cachedColor);
          }
        }
        _currentUser = serverUser;
        notifyListeners();
        await DatabaseHelper.instance.updateUserProfile(serverUser);
        await DatabaseHelper.instance.updateUserSparks(serverUser.id, serverUser.sparks);
        await MultiAccountService.instance.updateUser(serverUser);
      }
    } catch (e) {
      debugPrint('AuthProvider.refreshCurrentUser error: $e');
      if (_status == AuthStatus.authenticated && !_isLoading) {
        if (e.toString().contains('401') ||
            e.toString().contains('Недействительный токен') ||
            e.toString().contains('Необходима авторизация')) {
          await logout();
        }
      }
    }
  }

  Future<void> switchAccount(AccountSession targetSession, BuildContext context) async {
    if (_currentUser?.id == targetSession.userId) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Отключаем WebSocket текущего аккаунта
      WebSocketService.instance.disconnect();

      // 2. Устанавливаем новый токен и ID пользователя в хранилище
      ApiService.instance.setAuthToken(targetSession.token);
      await SecureStorageService.instance.saveToken(targetSession.token);
      await SecureStorageService.instance.saveCurrentUserId(targetSession.userId);

      // 3. Переключаем SQLite на изолированную БД целевого пользователя
      await DatabaseHelper.setActiveUserId(targetSession.userId);

      // 4. Фиксируем активный аккаунт в сервисе
      await MultiAccountService.instance.setActiveAccount(targetSession.userId);

      // 5. Переключаем пользователя в памяти
      _currentUser = targetSession.user;
      _status = AuthStatus.authenticated;

      // 6. Очищаем старые сообщения и чаты и загружаем данные нового аккаунта
      if (context.mounted) {
        await context.read<ChatProvider>().switchAccountData(onUserLoaded: (u) {
          _currentUser = u;
          notifyListeners();
        });
      }

      // 7. Подключаем WebSocket с новым токеном
      WebSocketService.instance.reconnectWithNewToken();

      _isLoading = false;
      notifyListeners();

      // 8. Фоном обновляем актуальный профиль с сервера
      refreshCurrentUser();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Error switching account: $e');
    }
  }

  Future<void> logout({BuildContext? context}) async {
    final activeId = _currentUser?.id;
    final accounts = MultiAccountService.instance.accounts;

    if (activeId != null && accounts.length > 1) {
      await MultiAccountService.instance.removeAccount(activeId);
      final remaining = MultiAccountService.instance.activeAccount ?? MultiAccountService.instance.accounts.first;
      if (context != null && context.mounted) {
        await switchAccount(remaining, context);
      }
      return;
    }

    ApiService.instance.clearAuthToken();
    WebSocketService.instance.disconnect();
    PushNotificationService.instance.unregister();
    await SecureStorageService.instance.clearAll();
    await DatabaseHelper.instance.clearAll();
    if (activeId != null) {
      await MultiAccountService.instance.removeAccount(activeId);
    }
    _currentUser = null;
    _step = AuthStep.email;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _listenWs() {
    _wsSub?.cancel();
    _wsSub = WebSocketService.instance.events.listen((event) {
      final type = event['type']?.toString();
      if (type == 'sparks_updated') {
        final sparks = event['sparks'] is int
            ? event['sparks'] as int
            : int.tryParse(event['sparks']?.toString() ?? '');
        if (sparks != null && _currentUser != null) {
          setSparks(sparks);
        }
      } else if (type == 'user_profile_updated') {
        final userId = event['userId'] is int
            ? event['userId'] as int
            : int.tryParse(event['userId']?.toString() ?? '');
        if (_currentUser != null && (_currentUser!.id == userId || userId == null)) {
          if (event['sparks'] != null) {
            final sparks = event['sparks'] is int
                ? event['sparks'] as int
                : int.tryParse(event['sparks'].toString());
            if (sparks != null) {
              setSparks(sparks);
            }
          }
          if (event['artifacts'] != null) {
            final art = event['artifacts'] is int
                ? event['artifacts'] as int
                : int.tryParse(event['artifacts'].toString()) ?? _currentUser!.artifacts;
            _currentUser = _currentUser!.copyWith(artifacts: art);
            notifyListeners();
            DatabaseHelper.instance.updateUserProfile(_currentUser!);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
