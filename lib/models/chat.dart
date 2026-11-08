import 'dart:convert';

class Chat {
  final int id;
  final String title;
  final String type;
  final String avatar;
  final String lastMessageText;
  final String lastMessageTime;
  final int unreadCount;
  final bool isPinned;
  final bool isChannel;
  final bool isOnline;
  final String? lastSeen;
  final int? participantId;
  final int? ownerId;
  final String? bannerUrl;
  final String? description;
  final String? phone;
  final String? username;
  final String? verification;
  final bool isPremium;
  final List<String> secondaryUsernames;
  final int subscribersCount;
  final bool isSubscribed;

  Chat({
    required this.id,
    required this.title,
    required this.type,
    required this.avatar,
    this.lastMessageText = '',
    this.lastMessageTime = '',
    this.unreadCount = 0,
    this.isPinned = false,
    this.isChannel = false,
    this.isOnline = false,
    this.lastSeen,
    this.participantId,
    this.ownerId,
    this.bannerUrl,
    this.description,
    this.phone,
    this.username,
    this.verification,
    this.isPremium = false,
    this.secondaryUsernames = const [],
    this.subscribersCount = 0,
    this.isSubscribed = false,
  });

  String get effectiveVerification {
    if (verification != null) {
      final v = verification!.trim().toLowerCase();
      if (v.isNotEmpty &&
          v != 'none' &&
          v != 'null' &&
          v != 'false' &&
          v != '0') {
        return v;
      }
    }
    final u = username?.toLowerCase().trim();
    final t = title.toLowerCase().trim();
    if (u == 'portal' ||
        (isChannel && (t == 'portal' || t.contains('portal')))) {
      return 'verified';
    }
    if (u == 'revs') return 'dev';
    if (u == 'botfather') return 'verified';
    return 'none';
  }

  bool get isVerified {
    final v = effectiveVerification;
    return v != 'none' && v.isNotEmpty;
  }

  bool get isDev {
    return effectiveVerification == 'dev';
  }

  String get lastMessageDate => lastMessageTime;
  bool get isSaved =>
      type == 'saved' ||
      title.toLowerCase().contains('избранное') ||
      title.toLowerCase().contains('сохранен');
  bool get isDirect =>
      type == 'direct' || type == 'dialog' || type == 'private' || !isChannel;

  String get displayLastMessage {
    final text = lastMessageText.trim();
    if (text.startsWith('[PORTAL_STICKER]:') || text.contains('[PORTAL_STICKER]:')) {
      return '✨ Стикер';
    }
    if (text.startsWith('[PORTAL_GIFT]:') ||
        text.contains('[PORTAL_GIFT]:') ||
        (text.startsWith('{') && text.contains('"type":"gift_card"'))) {
      return '🎁 Подарок';
    }
    if (text.startsWith('[PORTAL_PHOTO]:') ||
        text.contains('[PORTAL_PHOTO]:')) {
      try {
        final startIdx = text.indexOf('{');
        final endIdx = text.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          final jsonStr = text.substring(startIdx, endIdx + 1);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final caption = map['caption']?.toString() ?? '';
          if (caption.isNotEmpty) {
            return '📷 $caption';
          }
        }
      } catch (_) {}
      final capMatch = RegExp(r'"caption"\s*:\s*"([^"]*)"').firstMatch(text);
      final cap = capMatch?.group(1);
      if (cap != null && cap.isNotEmpty) {
        return '📷 $cap';
      }
      return '📷 Фотография';
    }
    if (text.startsWith('[PORTAL_AUDIO]:') ||
        text.contains('[PORTAL_AUDIO]:')) {
      return '🎤 Голосовое сообщение';
    }
    if (text.startsWith('[PORTAL_DOCUMENT]:') ||
        text.contains('[PORTAL_DOCUMENT]:')) {
      return '📄 Документ';
    }
    return lastMessageText;
  }

  Chat copyWith({
    int? id,
    String? title,
    String? type,
    String? avatar,
    String? lastMessageText,
    String? lastMessageTime,
    int? unreadCount,
    bool? isPinned,
    bool? isChannel,
    bool? isOnline,
    String? lastSeen,
    int? participantId,
    int? ownerId,
    String? bannerUrl,
    String? description,
    String? phone,
    String? username,
    String? verification,
    bool? isPremium,
    List<String>? secondaryUsernames,
    int? subscribersCount,
    bool? isSubscribed,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      avatar: avatar ?? this.avatar,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isChannel: isChannel ?? this.isChannel,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      participantId: participantId ?? this.participantId,
      ownerId: ownerId ?? this.ownerId,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      description: description ?? this.description,
      phone: phone ?? this.phone,
      username: username ?? this.username,
      verification: verification ?? this.verification,
      isPremium: isPremium ?? this.isPremium,
      secondaryUsernames: secondaryUsernames ?? this.secondaryUsernames,
      subscribersCount: subscribersCount ?? this.subscribersCount,
      isSubscribed: isSubscribed ?? this.isSubscribed,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    final lastMsg = json['last_message'];
    String lastText = '';
    String lastTime = '';
    if (lastMsg is Map<String, dynamic>) {
      lastText = lastMsg['text']?.toString() ?? '';
      lastTime = lastMsg['created_at']?.toString() ?? '';
    } else if (json['last_message_text'] != null) {
      lastText = json['last_message_text'].toString();
      lastTime = json['last_message_time']?.toString() ?? '';
    }

    final pId = json['participant_id'] is int
        ? json['participant_id'] as int
        : int.tryParse(json['participant_id']?.toString() ?? '') ??
            (json['user_id'] is int ? json['user_id'] as int : null);

    final oId = json['owner_id'] is int
        ? json['owner_id'] as int
        : int.tryParse(json['owner_id']?.toString() ?? '');

    final secUsers = (json['secondary_usernames'] is List)
        ? (json['secondary_usernames'] as List)
            .map((e) => e.toString().trim().replaceFirst(RegExp(r'^@+'), ''))
            .where((e) => e.isNotEmpty)
            .toList()
        : (json['secondaryUsernames'] is List)
            ? (json['secondaryUsernames'] as List)
                .map(
                    (e) => e.toString().trim().replaceFirst(RegExp(r'^@+'), ''))
                .where((e) => e.isNotEmpty)
                .toList()
            : (json['secondary_usernames'] is String &&
                    (json['secondary_usernames'] as String).isNotEmpty)
                ? (json['secondary_usernames'] as String)
                    .split(',')
                    .map((e) => e.trim().replaceFirst(RegExp(r'^@+'), ''))
                    .where((e) => e.isNotEmpty)
                    .toList()
                : const <String>[];

    final rawVerif = json['verification']?.toString() ??
        json['channel_verification']?.toString() ??
        json['sender_verification']?.toString() ??
        json['user_verification']?.toString();
    final cleanVerif =
        (rawVerif != null && rawVerif.isNotEmpty && rawVerif != 'none')
            ? rawVerif
            : null;

    final titleStr = json['title']?.toString() ??
        (json['first_name'] != null
            ? '${json['first_name']} ${json['last_name'] ?? ''}'.trim()
            : (json['name']?.toString() ?? 'Чат'));

    final isChan = json['is_channel'] == 1 || json['is_channel'] == true;

    return Chat(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      title: titleStr,
      type: json['type']?.toString() ?? (isChan ? 'channel' : 'direct'),
      avatar: json['avatar']?.toString() ?? '',
      lastMessageText: lastText,
      lastMessageTime: lastTime,
      unreadCount: json['unread_count'] is int
          ? json['unread_count']
          : int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      isPinned: json['is_pinned'] == 1 || json['is_pinned'] == true,
      isChannel: isChan,
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      lastSeen: json['last_seen']?.toString(),
      participantId: pId,
      ownerId: oId,
      bannerUrl: json['banner_url']?.toString() ?? json['banner']?.toString(),
      description: json['description']?.toString() ??
          json['about']?.toString() ??
          json['bio']?.toString(),
      phone: json['phone']?.toString() ??
          json['phone_number']?.toString() ??
          json['phoneNumber']?.toString(),
      username: json['username']?.toString(),
      verification: cleanVerif,
      isPremium: json['is_premium'] == true ||
          json['is_premium'] == 1 ||
          json['isPremium'] == true,
      secondaryUsernames: secUsers,
      subscribersCount: json['subscribers_count'] is int
          ? json['subscribers_count'] as int
          : int.tryParse(json['subscribers_count']?.toString() ?? '') ?? 0,
      isSubscribed: json['is_subscribed'] == 1 || json['is_subscribed'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'avatar': avatar,
      'last_message_text': lastMessageText,
      'last_message_time': lastMessageTime,
      'unread_count': unreadCount,
      'is_pinned': isPinned ? 1 : 0,
      'is_channel': isChannel ? 1 : 0,
      'is_online': isOnline ? 1 : 0,
      'last_seen': lastSeen ?? '',
      'participant_id': participantId,
      'owner_id': ownerId,
      'banner_url': bannerUrl ?? '',
      'description': description ?? '',
      'phone': phone ?? '',
      'username': username ?? '',
      'verification': verification ?? 'none',
      'is_premium': isPremium ? 1 : 0,
      'subscribers_count': subscribersCount,
      'is_subscribed': isSubscribed ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    final rawVerif = map['verification']?.toString();
    final cleanVerif =
        (rawVerif != null && rawVerif.isNotEmpty && rawVerif != 'none')
            ? rawVerif
            : null;
    return Chat(
      id: map['id'] as int,
      title: map['title']?.toString() ?? 'Чат',
      type: map['type']?.toString() ?? 'direct',
      avatar: map['avatar']?.toString() ?? '',
      lastMessageText: map['last_message_text']?.toString() ?? '',
      lastMessageTime: map['last_message_time']?.toString() ?? '',
      unreadCount: map['unread_count'] as int? ?? 0,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isChannel: (map['is_channel'] as int? ?? 0) == 1,
      isOnline: (map['is_online'] as int? ?? 0) == 1,
      lastSeen: map['last_seen']?.toString(),
      participantId: map['participant_id'] as int?,
      ownerId: map['owner_id'] as int?,
      bannerUrl: map['banner_url']?.toString(),
      description: map['description']?.toString(),
      phone: map['phone']?.toString(),
      username: map['username']?.toString(),
      verification: cleanVerif,
      isPremium: (map['is_premium'] as int? ?? 0) == 1,
      subscribersCount: map['subscribers_count'] as int? ?? 0,
      isSubscribed: (map['is_subscribed'] as int? ?? 0) == 1,
    );
  }
}
