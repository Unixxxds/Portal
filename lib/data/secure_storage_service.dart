import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class SecureStorageService {
  static final SecureStorageService instance = SecureStorageService._init();
  SecureStorageService._init();

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  Future<void> saveCurrentUserId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.currentUserIdKey, id);
  }

  Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.currentUserIdKey);
  }

  Future<void> saveUserPinnedChannelId(int userId, int? channelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (channelId != null && channelId > 0) {
      await prefs.setInt('user_pinned_channel_$userId', channelId);
    } else {
      await prefs.remove('user_pinned_channel_$userId');
    }
  }

  Future<int?> getUserPinnedChannelId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_pinned_channel_$userId');
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.currentUserIdKey);
  }
}
