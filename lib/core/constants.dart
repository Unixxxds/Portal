class AppConstants {
  static const String appName = 'Portal';
  
  // Base URLs
  static const String baseUrl = 'https://web.portalmsg.ru';
  static const String wsUrl = 'wss://web.portalmsg.ru/ws';
  
  // Storage keys
  static const String tokenKey = 'portal_jwt_token';
  static const String currentUserIdKey = 'portal_current_user_id';
  
  // Full URL helper for avatars and media
  static String formatMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$cleanPath';
  }
}

