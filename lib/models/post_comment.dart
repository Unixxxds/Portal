class PostComment {
  final int id;
  final int messageId;
  final int userId;
  final String text;
  final String createdAt;
  final String firstName;
  final String lastName;
  final String username;
  final String avatar;
  final String verification;
  final bool isPremium;

  PostComment({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.firstName = '',
    this.lastName = '',
    this.username = '',
    this.avatar = '',
    this.verification = 'none',
    this.isPremium = false,
  });

  String get displayName {
    final full = '$firstName $lastName'.trim();
    if (full.isNotEmpty) return full;
    if (username.isNotEmpty) return username;
    return 'Пользователь';
  }

  String get effectiveVerification {
    final v = verification.trim().toLowerCase();
    if (v.isNotEmpty && v != 'none' && v != 'null' && v != 'false' && v != '0') {
      return v;
    }
    final u = username.toLowerCase().trim();
    if (u == 'portal') return 'verified';
    if (u == 'revs') return 'dev';
    if (u == 'botfather') return 'verified';
    return 'none';
  }

  bool get isVerified => effectiveVerification != 'none';
  bool get isDev => effectiveVerification == 'dev';

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final rawVerif = json['verification']?.toString() ??
        json['user_verification']?.toString() ??
        'none';
    return PostComment(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id'].toString()) ?? 0,
      messageId: json['message_id'] is int ? json['message_id'] as int : int.tryParse(json['message_id'].toString()) ?? 0,
      userId: json['user_id'] is int ? json['user_id'] as int : int.tryParse(json['user_id'].toString()) ?? 0,
      text: json['text']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      verification: rawVerif,
      isPremium: json['is_premium'] == 1 || json['is_premium'] == true || json['isPremium'] == true,
    );
  }
}

