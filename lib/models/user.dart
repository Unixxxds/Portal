class User {
  final int id;
  final String firstName;
  final String lastName;
  final String username;
  final String avatar;
  final String? bannerUrl;
  final String? description;
  final String? phone;
  final String? email;
  final int sparks;
  final bool isPremium;
  final String verification;
  final bool isOnline;
  final String? lastSeen;
  final List<String> secondaryUsernames;

  User({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.avatar,
    this.bannerUrl,
    this.description,
    this.phone,
    this.email,
    this.sparks = 250,
    this.isPremium = false,
    this.verification = 'none',
    this.isOnline = false,
    this.lastSeen,
    this.secondaryUsernames = const [],
  });

  String get fullName {
    if (lastName.isEmpty) return firstName;
    if (firstName.isEmpty) return lastName;
    return '$firstName $lastName'.trim();
  }

  String get displayName => fullName.isNotEmpty ? fullName : (username.isNotEmpty ? '@$username' : 'Пользователь');

  String get effectiveVerification {
    final v = verification.trim().toLowerCase();
    if (v.isNotEmpty && v != 'none' && v != 'null' && v != 'false' && v != '0') {
      return v;
    }
    final u = username.toLowerCase().trim();
    if (u == 'revs') return 'dev';
    if (u == 'botfather' || u == 'portal') return 'verified';
    return 'none';
  }

  bool get isVerified {
    final v = effectiveVerification;
    return v != 'none' && v.isNotEmpty;
  }

  bool get isDev => effectiveVerification == 'dev';

  int get sparksBalance => sparks;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      bannerUrl: json['banner_url']?.toString() ?? json['banner']?.toString(),
      description: json['description']?.toString() ?? json['about']?.toString() ?? json['bio']?.toString(),
      phone: json['phone']?.toString() ?? json['phone_number']?.toString() ?? json['phoneNumber']?.toString(),
      email: json['email']?.toString(),
      sparks: json['sparks'] is int ? json['sparks'] : int.tryParse(json['sparks']?.toString() ?? '250') ?? 250,
      isPremium: json['is_premium'] == true || json['is_premium'] == 1,
      verification: json['verification']?.toString() ?? 'none',
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      lastSeen: json['last_seen']?.toString(),
      secondaryUsernames: (json['secondary_usernames'] is List)
          ? (json['secondary_usernames'] as List)
              .map((e) => e.toString().trim().replaceFirst(RegExp(r'^@+'), ''))
              .where((e) => e.isNotEmpty)
              .toList()
          : (json['secondaryUsernames'] is List)
              ? (json['secondaryUsernames'] as List)
                  .map((e) => e.toString().trim().replaceFirst(RegExp(r'^@+'), ''))
                  .where((e) => e.isNotEmpty)
                  .toList()
              : (json['secondary_usernames'] is String && (json['secondary_usernames'] as String).isNotEmpty)
                  ? (json['secondary_usernames'] as String)
                      .split(',')
                      .map((e) => e.trim().replaceFirst(RegExp(r'^@+'), ''))
                      .where((e) => e.isNotEmpty)
                      .toList()
                  : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'avatar': avatar,
      'banner_url': bannerUrl ?? '',
      'description': description ?? '',
      'phone': phone ?? '',
      'email': email ?? '',
      'sparks': sparks,
      'is_premium': isPremium ? 1 : 0,
      'verification': verification,
      'is_online': isOnline ? 1 : 0,
      'last_seen': lastSeen ?? '',
      'secondary_usernames': secondaryUsernames.join(','),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int,
      firstName: map['first_name']?.toString() ?? '',
      lastName: map['last_name']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      avatar: map['avatar']?.toString() ?? '',
      bannerUrl: map['banner_url']?.toString(),
      description: map['description']?.toString(),
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      sparks: map['sparks'] as int? ?? 250,
      isPremium: (map['is_premium'] as int? ?? 0) == 1,
      verification: map['verification']?.toString() ?? 'none',
      isOnline: (map['is_online'] as int? ?? 0) == 1,
      lastSeen: map['last_seen']?.toString(),
      secondaryUsernames: (map['secondary_usernames'] is String && (map['secondary_usernames'] as String).isNotEmpty)
          ? (map['secondary_usernames'] as String)
              .split(',')
              .map((e) => e.trim().replaceFirst(RegExp(r'^@+'), ''))
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
    );
  }

  User copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? username,
    String? avatar,
    String? bannerUrl,
    String? description,
    String? phone,
    String? email,
    int? sparks,
    bool? isPremium,
    String? verification,
    bool? isOnline,
    String? lastSeen,
    List<String>? secondaryUsernames,
  }) {
    return User(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      description: description ?? this.description,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      sparks: sparks ?? this.sparks,
      isPremium: isPremium ?? this.isPremium,
      verification: verification ?? this.verification,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      secondaryUsernames: secondaryUsernames ?? this.secondaryUsernames,
    );
  }
}
