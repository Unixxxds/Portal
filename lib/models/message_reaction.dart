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

  factory MessageReaction.fromMap(Map<String, dynamic> map, {int fallbackChatId = 0}) {
    final rawName = map['user_name'] ?? map['userName'];
    String name = rawName?.toString() ?? '';
    if (name.isEmpty) {
      final fName = map['first_name']?.toString() ?? '';
      final lName = map['last_name']?.toString() ?? '';
      name = '$fName $lName'.trim();
      if (name.isEmpty) {
        name = map['username']?.toString() ?? '';
      }
    }

    return MessageReaction(
      id: map['id'] is int ? map['id'] as int : int.tryParse(map['id']?.toString() ?? ''),
      messageId: map['message_id'] is int
          ? map['message_id'] as int
          : int.tryParse(map['message_id']?.toString() ?? map['messageId']?.toString() ?? '') ?? 0,
      chatId: map['chat_id'] is int
          ? map['chat_id'] as int
          : int.tryParse(map['chat_id']?.toString() ?? map['chatId']?.toString() ?? '') ?? fallbackChatId,
      userId: map['user_id'] is int
          ? map['user_id'] as int
          : int.tryParse(map['user_id']?.toString() ?? map['userId']?.toString() ?? '') ?? 0,
      emoji: map['emoji']?.toString() ?? '',
      userName: name,
      userAvatar: map['user_avatar']?.toString() ?? map['userAvatar']?.toString() ?? map['avatar']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? '',
    );
  }
}
