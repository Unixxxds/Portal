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

  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
    userId: json['userId'] as int,
    token: json['token'] as String,
    user: User.fromMap(json['user'] as Map<String, dynamic>),
    unreadCount: (json['unreadCount'] as int?) ?? 0,
    lastActive: json['lastActive'] != null
        ? DateTime.tryParse(json['lastActive'].toString()) ?? DateTime.now()
        : DateTime.now(),
  );
}

