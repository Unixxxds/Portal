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

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      chatId: json['chat_id'] is int ? json['chat_id'] : int.tryParse(json['chat_id'].toString()) ?? 0,
      senderId: json['sender_id'] is int ? json['sender_id'] : int.tryParse(json['sender_id'].toString()) ?? 0,
      text: json['text']?.toString() ?? '',
      replyToMessageId: json['reply_to_message_id'] != null
          ? (json['reply_to_message_id'] is int
              ? json['reply_to_message_id']
              : int.tryParse(json['reply_to_message_id'].toString()))
          : null,
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      isRead: json['is_read'] == 1 || json['is_read'] == true,
      senderName: json['sender_name']?.toString() ?? '',
      senderAvatar: json['sender_avatar']?.toString() ?? '',
      isPending: false,
      isEdited: json['is_edited'] == 1 || json['is_edited'] == true || json['isEdited'] == true,
      commentsCount: json['comments_count'] is int
          ? json['comments_count'] as int
          : (json['commentsCount'] is int
              ? json['commentsCount'] as int
              : int.tryParse(json['comments_count']?.toString() ?? json['commentsCount']?.toString() ?? '') ?? 0),
      viewsCount: json['views_count'] is int
          ? json['views_count'] as int
          : (json['viewsCount'] is int
              ? json['viewsCount'] as int
              : int.tryParse(json['views_count']?.toString() ?? json['viewsCount']?.toString() ?? '') ?? 1),
      isViewed: json['is_viewed'] == 1 || json['is_viewed'] == true || json['isViewed'] == true,
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

