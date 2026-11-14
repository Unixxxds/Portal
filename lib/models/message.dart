class Message {
  final int id;
  final int chatId;
  final int senderId;
  final String text;
  final int? replyToMessageId;
  final String createdAt;
  final bool isRead;
  final String senderName;
  final String senderAvatar;
  final bool isPending; // for optimistic UI sending
  final bool isEdited;
  final int commentsCount;
  final int viewsCount;
  final bool isViewed;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    this.replyToMessageId,
    required this.createdAt,
    this.isRead = false,
    this.senderName = '',
    this.senderAvatar = '',
    this.isPending = false,
    this.isEdited = false,
    this.commentsCount = 0,
    this.viewsCount = 1,
    this.isViewed = false,
  });

  Message copyWith({
    int? id,
    int? chatId,
    int? senderId,
    String? text,
    int? replyToMessageId,
    String? createdAt,
    bool? isRead,
    String? senderName,
    String? senderAvatar,
    bool? isPending,
    bool? isEdited,
    int? commentsCount,
    int? viewsCount,
    bool? isViewed,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      isPending: isPending ?? this.isPending,
      isEdited: isEdited ?? this.isEdited,
      commentsCount: commentsCount ?? this.commentsCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isViewed: isViewed ?? this.isViewed,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json, {int? fallbackChatId}) {
    final rawChatId = json['chat_id'] ?? json['chatId'];
    final parsedChatId = rawChatId is int
        ? rawChatId
        : int.tryParse(rawChatId?.toString() ?? '');
    final finalChatId = (parsedChatId != null && parsedChatId > 0)
        ? parsedChatId
        : (fallbackChatId ?? 0);

    final rawSenderId = json['sender_id'] ?? json['senderId'] ?? json['user_id'] ?? json['userId'];
    final parsedSenderId = rawSenderId is int
        ? rawSenderId
        : int.tryParse(rawSenderId?.toString() ?? '') ?? 0;

    final rawReplyId = json['reply_to_message_id'] ?? json['replyToMessageId'] ?? json['reply_id'] ?? json['replyId'];
    final parsedReplyId = rawReplyId is int
        ? rawReplyId
        : int.tryParse(rawReplyId?.toString() ?? '');

    final rawCreatedAt = json['created_at'] ?? json['createdAt'];
    final createdAtStr = rawCreatedAt?.toString() ?? DateTime.now().toIso8601String();

    final isRead = json['is_read'] == 1 ||
        json['is_read'] == true ||
        json['isRead'] == 1 ||
        json['isRead'] == true;

    final senderName = json['sender_name']?.toString() ??
        json['senderName']?.toString() ??
        json['sender_first_name']?.toString() ??
        '';

    final senderAvatar = json['sender_avatar']?.toString() ??
        json['senderAvatar']?.toString() ??
        '';

    final isEdited = json['is_edited'] == 1 ||
        json['is_edited'] == true ||
        json['isEdited'] == 1 ||
        json['isEdited'] == true;

    final commentsCount = json['comments_count'] is int
        ? json['comments_count'] as int
        : (json['commentsCount'] is int
            ? json['commentsCount'] as int
            : int.tryParse(json['comments_count']?.toString() ?? json['commentsCount']?.toString() ?? '') ?? 0);

    final viewsCount = json['views_count'] is int
        ? json['views_count'] as int
        : (json['viewsCount'] is int
            ? json['viewsCount'] as int
            : int.tryParse(json['views_count']?.toString() ?? json['viewsCount']?.toString() ?? '') ?? 1);

    final isViewed = json['is_viewed'] == 1 ||
        json['is_viewed'] == true ||
        json['isViewed'] == 1 ||
        json['isViewed'] == true;

    return Message(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      chatId: finalChatId,
      senderId: parsedSenderId,
      text: json['text']?.toString() ?? json['content']?.toString() ?? '',
      replyToMessageId: parsedReplyId,
      createdAt: createdAtStr,
      isRead: isRead,
      senderName: senderName,
      senderAvatar: senderAvatar,
      isPending: false,
      isEdited: isEdited,
      commentsCount: commentsCount,
      viewsCount: viewsCount,
      isViewed: isViewed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'text': text,
      'reply_to_message_id': replyToMessageId,
      'created_at': createdAt,
      'is_read': isRead ? 1 : 0,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'is_edited': isEdited ? 1 : 0,
      'comments_count': commentsCount,
      'views_count': viewsCount,
      'is_viewed': isViewed ? 1 : 0,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as int,
      chatId: map['chat_id'] as int,
      senderId: map['sender_id'] as int,
      text: map['text']?.toString() ?? '',
      replyToMessageId: map['reply_to_message_id'] as int?,
      createdAt: map['created_at']?.toString() ?? '',
      isRead: (map['is_read'] as int? ?? 0) == 1,
      senderName: map['sender_name']?.toString() ?? '',
      senderAvatar: map['sender_avatar']?.toString() ?? '',
      isPending: false,
      isEdited: (map['is_edited'] as int? ?? 0) == 1,
      commentsCount: (map['comments_count'] as int? ?? map['commentsCount'] as int? ?? 0),
      viewsCount: (map['views_count'] as int? ?? map['viewsCount'] as int? ?? 1),
      isViewed: (map['is_viewed'] as int? ?? 0) == 1,
    );
  }
}

