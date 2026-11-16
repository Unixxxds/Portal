import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/secure_storage_service.dart';
import '../models/account_session.dart';
import '../models/user.dart';

class MultiAccountService with ChangeNotifier {
  static final MultiAccountService instance = MultiAccountService._init();
  MultiAccountService._init();

  static const String _accountsKey = 'portal_saved_accounts_v1';
  static const String _activeAccountKey = 'portal_active_account_id_v1';

  final List<AccountSession> _accounts = [];
  int? _activeUserId;
  bool _isInitialized = false;

  List<AccountSession> get accounts => List.unmodifiable(_accounts);
  int? get activeUserId => _activeUserId;
  AccountSession? get activeAccount {
    if (_activeUserId == null) return _accounts.isNotEmpty ? _accounts.first : null;
    return _accounts.firstWhere(
      (a) => a.userId == _activeUserId,
      orElse: () => _accounts.first,
    );
  }

  Future<void> init({User? currentUser, String? currentToken}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeUserId = prefs.getInt(_activeAccountKey) ?? await SecureStorageService.instance.getCurrentUserId();

      final jsonStr = prefs.getString(_accountsKey);
      final List<AccountSession> loadedAccounts = [];

      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                try {
                  final session = AccountSession.fromJson(item);
                  if (session.userId > 0) {
                    loadedAccounts.add(session);
                  }
                } catch (e) {
                  debugPrint('Failed to parse account session: $e');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Failed to decode accounts json: $e');
        }
      }

      if (loadedAccounts.isNotEmpty) {
        _accounts.clear();
        _accounts.addAll(loadedAccounts);
      }

      // Auto-register current session if not yet in accounts list
      final token = currentToken ?? await SecureStorageService.instance.getToken();
      final secureUserId = await SecureStorageService.instance.getCurrentUserId();
      final userId = currentUser?.id ?? secureUserId;

      if (token != null && token.isNotEmpty && userId != null && userId > 0) {
        final existingIdx = _accounts.indexWhere((a) => a.userId == userId);
        if (existingIdx == -1) {
          if (currentUser != null) {
            _accounts.add(AccountSession(
              userId: userId,
              token: token,
              user: currentUser,
              lastActive: DateTime.now(),
            ));
          }
        } else {
          // Update user info
          _accounts[existingIdx] = _accounts[existingIdx].copyWith(
            user: currentUser ?? _accounts[existingIdx].user,
            token: token,
            lastActive: DateTime.now(),
          );
        }
      }

      _isInitialized = true;
      if (_accounts.isNotEmpty) {
        await _persist();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('MultiAccountService.init error: $e');
    }
  }

  Future<void> saveAccount(AccountSession session) async {
    if (!_isInitialized) {
      await init();
    }
    final idx = _accounts.indexWhere((a) => a.userId == session.userId);
    if (idx != -1) {
      _accounts[idx] = session;
    } else {
      _accounts.add(session);
    }
    _activeUserId = session.userId;
    _isInitialized = true;
    await _persist();
    notifyListeners();
  }

  Future<void> setActiveAccount(int userId) async {
    if (!_isInitialized) {
      await init();
    }
    _activeUserId = userId;
    final idx = _accounts.indexWhere((a) => a.userId == userId);
    if (idx != -1) {
      _accounts[idx] = _accounts[idx].copyWith(lastActive: DateTime.now());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeAccountKey, userId);
    await _persist();
    notifyListeners();
  }

  Future<void> updateUser(User user) async {
    if (!_isInitialized) {
      await init();
    }
    final idx = _accounts.indexWhere((a) => a.userId == user.id);
    if (idx != -1) {
      _accounts[idx] = _accounts[idx].copyWith(user: user);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> updateUnread(int userId, int unreadCount) async {
    if (!_isInitialized) {
      await init();
    }
    final idx = _accounts.indexWhere((a) => a.userId == userId);
    if (idx != -1 && _accounts[idx].unreadCount != unreadCount) {
      _accounts[idx] = _accounts[idx].copyWith(unreadCount: unreadCount);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> removeAccount(int userId) async {
    if (!_isInitialized) {
      await init();
    }
    _accounts.removeWhere((a) => a.userId == userId);
    if (_activeUserId == userId) {
      _activeUserId = _accounts.isNotEmpty ? _accounts.first.userId : null;
    }
    await _persist();

    // Delete isolated SQLite database file for this removed account
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(docs.path, 'portal_user_$userId.db'));
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
      final walFile = File(p.join(docs.path, 'portal_user_$userId.db-wal'));
      if (walFile.existsSync()) {
        walFile.deleteSync();
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _persist() async {
    if (!_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _accounts.map((a) => a.toJson()).toList();
      await prefs.setString(_accountsKey, jsonEncode(list));
      if (_activeUserId != null) {
        await prefs.setInt(_activeAccountKey, _activeUserId!);
      }
    } catch (e) {
      debugPrint('MultiAccountService._persist error: $e');
    }
  }
}

