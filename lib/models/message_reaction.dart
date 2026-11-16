class MessageReaction {
  final int? id;
  final int messageId;
  final int chatId;
  final int userId;
  final String emoji;
  final String userName;
  final String userAvatar;
  final String createdAt;

  MessageReaction({
    this.id,
    required this.messageId,
    required this.chatId,
    required this.userId,
    required this.emoji,
    this.userName = '',
    this.userAvatar = '',
    required this.createdAt,
  });

  MessageReaction copyWith({
    int? id,
    int? messageId,
    int? chatId,
    int? userId,
    String? emoji,
    String? userName,
    String? userAvatar,
    String? createdAt,
  }) {
    return MessageReaction(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      chatId: chatId ?? this.chatId,
      userId: userId ?? this.userId,
      emoji: emoji ?? this.emoji,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'message_id': messageId,
      'chat_id': chatId,
      'user_id': userId,
      'emoji': emoji,
      'user_name': userName,
      'user_avatar': userAvatar,
      'created_at': createdAt,
    };
  }

  factory MessageReaction.fromMap(Map<String, dynamic> map) {
    return MessageReaction(
      id: map['id'] as int?,
      messageId: (map['message_id'] as int? ?? map['messageId'] as int? ?? 0),
      chatId: (map['chat_id'] as int? ?? map['chatId'] as int? ?? 0),
      userId: (map['user_id'] as int? ?? map['userId'] as int? ?? 0),
      emoji: map['emoji']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? map['userName']?.toString() ?? '',
      userAvatar: map['user_avatar']?.toString() ?? map['userAvatar']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? map['createdAt']?.toString() ?? '',
    );
  }
}

