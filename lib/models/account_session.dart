import '../models/user.dart';

class AccountSession {
  final int userId;
  final String token;
  final User user;
  final int unreadCount;
  final DateTime lastActive;

  AccountSession({
    required this.userId,
    required this.token,
    required this.user,
    this.unreadCount = 0,
    required this.lastActive,
  });

  AccountSession copyWith({
    int? userId,
    String? token,
    User? user,
    int? unreadCount,
    DateTime? lastActive,
  }) {
    return AccountSession(
      userId: userId ?? this.userId,
      token: token ?? this.token,
      user: user ?? this.user,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'token': token,
    'user': user.toMap(),
    'unreadCount': unreadCount,
    'lastActive': lastActive.toIso8601String(),
  };

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    User parsedUser;
    if (rawUser is Map<String, dynamic>) {
      try {
        parsedUser = rawUser.containsKey('first_name')
            ? User.fromMap(rawUser)
            : User.fromJson(rawUser);
      } catch (_) {
        parsedUser = User.fromJson(rawUser);
      }
    } else {
      final uid = int.tryParse(json['userId']?.toString() ?? '0') ?? 0;
      parsedUser = User(
        id: uid,
        firstName: '',
        lastName: '',
        username: '',
        avatar: '',
      );
    }

    final parsedUserId = int.tryParse(json['userId']?.toString() ?? '') ?? parsedUser.id;

    return AccountSession(
      userId: parsedUserId,
      token: json['token']?.toString() ?? '',
      user: parsedUser,
      unreadCount: int.tryParse(json['unreadCount']?.toString() ?? '0') ?? 0,
      lastActive: json['lastActive'] != null
          ? DateTime.tryParse(json['lastActive'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

