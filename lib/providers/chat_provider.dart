import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/user_gift.dart';
import '../data/database_helper.dart';
import '../data/secure_storage_service.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ChatProvider with ChangeNotifier {
  List<Chat> _chats = [];
  final Map<int, List<Message>> _messagesByChat = {};
  int? _activeChatId;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _syncError;

  // Realtime typing status: {chatId: Set of userIds}
  final Map<int, Set<int>> _typingUsers = {};
  // Realtime presence: {userId: bool}
  final Map<int, bool> _userPresence = {};
  // Realtime pinned message per chat: {chatId: Message?}
  final Map<int, Message?> _pinnedMessages = {};

  StreamSubscription? _wsSubscription;

  List<Chat> get chats => _chats;
  int? get activeChatId => _activeChatId;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;

  Message? getPinnedMessage(int chatId) => _pinnedMessages[chatId];

  List<Message> get activeMessages {
    if (_activeChatId == null) return [];
    return _messagesByChat[_activeChatId] ?? [];
  }

  bool isUserTyping(int chatId) {
    return (_typingUsers[chatId]?.isNotEmpty) ?? false;
  }

  bool isUserOnline(int userId) {
    return _userPresence[userId] ?? false;
  }

  void init() {
    _listenToWebSocket();
    loadLocalData();
  }

  void _listenToWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService.instance.events.listen((event) {
      _handleWebSocketEvent(event);
    });
  }

  Future<void> loadLocalData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _chats = await DatabaseHelper.instance.getChats();
    } catch (e) {
      debugPrint('Error loading local chats: $e');
    }

    _isLoading = false;
    notifyListeners();

    // Запускаем фоновый Fast Sync Bootstrap
    syncBootstrap();
  }

  Future<void> syncBootstrap({Function(User)? onUserLoaded}) async {
    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final data = await ApiService.instance.getBootstrap();
      if (data['success'] == true) {
        final userData = data['user'];
        final chatsData = data['chats'] as List? ?? [];
        final messagesData = data['recent_messages'] as Map<String, dynamic>? ?? {};

        if (userData != null && userData is Map<String, dynamic> && onUserLoaded != null) {
          final user = User.fromJson(userData);
          onUserLoaded(user);
        }

        // Сохраняем в SQLite в одной быстрой транзакции
        await DatabaseHelper.instance.saveBootstrap(
          user: userData is Map<String, dynamic> ? userData : {},
          chats: chatsData,
          recentMessages: messagesData,
        );

        // Перезагружаем список чатов из локальной БД
        _chats = await DatabaseHelper.instance.getChats();

        // Если активен какой-то чат, перезагружаем его сообщения
        if (_activeChatId != null) {
          _messagesByChat[_activeChatId!] = await DatabaseHelper.instance.getMessages(_activeChatId!);
        }
      }
    } catch (e) {
      debugPrint('Bootstrap sync error: $e');
      _syncError = e.toString();
    }

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> openChat(int chatId) async {
    _activeChatId = chatId;
    // Сбросить непрочитанные локально в БД и в UI
    await DatabaseHelper.instance.resetUnread(chatId);
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1) {
      _chats[chatIdx] = _chats[chatIdx].copyWith(unreadCount: 0);

      // Актуализируем статус пользователя (онлайн/был недавно)
      final chat = _chats[chatIdx];
      if (!chat.isChannel && !chat.isSaved) {
        final targetId = chat.participantId ?? chat.id;
        ApiService.instance.getUserProfile(targetId).then((data) {
          if (data != null) {
            final isOnline = data['is_online'] == true || data['is_online'] == 1;
            final lastSeen = data['last_seen']?.toString();
            final pId = data['id'] is int ? data['id'] as int : targetId;
            final verif = data['verification']?.toString();
            final isPrem = data['is_premium'] == true || data['is_premium'] == 1;
            updatePresence(
              userId: pId,
              chatId: chatId,
              isOnline: isOnline,
              lastSeen: lastSeen,
              verification: verif,
              isPremium: isPrem,
            );
          }
        }).catchError((_) {});
      } else if (chat.isChannel) {
        ApiService.instance.getChannel(chatId).then((data) {
          if (data != null) {
            final verif = data['verification']?.toString();
            if (verif != null && verif.isNotEmpty && verif != 'none') {
              updateChatVerification(chatId: chatId, verification: verif);
            }
          }
        }).catchError((_) {});
      }
    }

    // Загружаем сообщения из SQLite
    _messagesByChat[chatId] = await DatabaseHelper.instance.getMessages(chatId);
    notifyListeners();

    // Загружаем закрепленное сообщение
    loadPinnedMessage(chatId);

    // Загружаем актуальную историю с сервера
    try {
      final remoteMsgs = await ApiService.instance.getChatHistory(chatId);
      if (remoteMsgs.isNotEmpty) {
        for (final m in remoteMsgs) {
          final msgObj = Message.fromJson(m);
          await DatabaseHelper.instance.insertMessage(msgObj);
          final trimmedText = msgObj.text.trim();
          if (trimmedText.startsWith('[PORTAL_GIFT]:') ||
              (trimmedText.startsWith('{') && trimmedText.contains('"type":"gift_card"'))) {
            try {
              final jsonStr = trimmedText.startsWith('[PORTAL_GIFT]:')
                  ? trimmedText.substring('[PORTAL_GIFT]:'.length).trim()
                  : trimmedText;
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              final rId = map['recipientId'] is int
                  ? map['recipientId'] as int
                  : (int.tryParse(map['recipientId']?.toString() ?? '') ?? chatId);
              final gift = UserGift.fromJson(map, fallbackUserId: rId);
              await DatabaseHelper.instance.insertUserGift(gift);
            } catch (_) {}
          }
        }
        _messagesByChat[chatId] = await DatabaseHelper.instance.getMessages(chatId);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> updatePresence({
    required int userId,
    int? chatId,
    required bool isOnline,
    String? lastSeen,
    String? verification,
    bool? isPremium,
  }) async {
    _userPresence[userId] = isOnline;
    if (chatId != null) {
      _userPresence[chatId] = isOnline;
    }

    // 1. Сохраняем в SQLite
    await DatabaseHelper.instance.updateUserPresence(
      userId: userId,
      isOnline: isOnline,
      lastSeen: lastSeen,
    );

    if (verification != null && verification.isNotEmpty && verification != 'none') {
      if (chatId != null) {
        await DatabaseHelper.instance.updateChatVerification(
          chatId: chatId,
          verification: verification,
          isPremium: isPremium,
        );
      }
    }

    // 2. Обновляем в локальном списке чатов
    bool changed = false;
    for (int i = 0; i < _chats.length; i++) {
      if (_chats[i].participantId == userId || _chats[i].id == (chatId ?? userId)) {
        final cleanVerif = (verification != null && verification.isNotEmpty && verification != 'none')
            ? verification
            : _chats[i].verification;
        _chats[i] = _chats[i].copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen ?? _chats[i].lastSeen,
          participantId: userId,
          verification: cleanVerif,
          isPremium: isPremium ?? _chats[i].isPremium,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> updateChatVerification({
    required int chatId,
    required String verification,
    bool? isPremium,
  }) async {
    await DatabaseHelper.instance.updateChatVerification(
      chatId: chatId,
      verification: verification,
      isPremium: isPremium,
    );

    bool changed = false;
    for (int i = 0; i < _chats.length; i++) {
      if (_chats[i].id == chatId) {
        _chats[i] = _chats[i].copyWith(
          verification: verification,
          isPremium: isPremium ?? _chats[i].isPremium,
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void closeChat() {
    _activeChatId = null;
    notifyListeners();
  }

  Future<void> loadPinnedMessage(int chatId) async {
    try {
      final res = await ApiService.instance.getPinnedMessage(chatId);
      if (res != null && res['pinnedMessage'] != null) {
        _pinnedMessages[chatId] = Message.fromJson(res['pinnedMessage'] as Map<String, dynamic>);
      } else {
        _pinnedMessages.remove(chatId);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> togglePinMessage(int chatId, int messageId) async {
    try {
      final res = await ApiService.instance.togglePinMessage(chatId, messageId);
      if (res != null && res['success'] == true) {
        if (res['isPinned'] == true && res['pinnedMessage'] != null) {
          _pinnedMessages[chatId] = Message.fromJson(res['pinnedMessage'] as Map<String, dynamic>);
        } else {
          _pinnedMessages.remove(chatId);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to toggle pin message: $e');
    }
  }

  Future<void> unpinMessage(int chatId) async {
    try {
      await ApiService.instance.togglePinMessage(chatId, null);
      _pinnedMessages.remove(chatId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> editMessage(int chatId, int messageId, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    // 1. Оптимистично обновляем в памяти
    if (_messagesByChat.containsKey(chatId)) {
      final list = _messagesByChat[chatId]!;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(text: trimmed, isEdited: true);
      }
    }
    if (_pinnedMessages[chatId]?.id == messageId) {
      _pinnedMessages[chatId] = _pinnedMessages[chatId]!.copyWith(text: trimmed, isEdited: true);
    }
    notifyListeners();

    // 2. Локальная база данных
    await DatabaseHelper.instance.editMessage(messageId, trimmed);

    // 3. Синхронизация через WebSocket и REST
    WebSocketService.instance.editMessage(messageId, trimmed);
    await ApiService.instance.editMessage(messageId, trimmed);
  }

  Future<void> deleteMessage(int chatId, int messageId) async {
    // 1. Оптимистично удаляем из памяти
    if (_messagesByChat.containsKey(chatId)) {
      _messagesByChat[chatId]?.removeWhere((m) => m.id == messageId);
    }
    if (_pinnedMessages[chatId]?.id == messageId) {
      _pinnedMessages.remove(chatId);
    }
    notifyListeners();

    // 2. Уведомляем по WS и REST
    WebSocketService.instance.deleteMessage(chatId, messageId);
    await ApiService.instance.deleteMessage(messageId);
    await DatabaseHelper.instance.deleteMessage(messageId);
  }

  Future<void> sendMessage(int chatId, String text, {int? replyToMessageId}) async {
    if (text.trim().isEmpty) return;

    final currentUserId = await SecureStorageService.instance.getCurrentUserId() ?? 0;
    final tempId = -DateTime.now().millisecondsSinceEpoch; // отрицательный ID для pending
    final nowIso = DateTime.now().toIso8601String();

    final optimisticMsg = Message(
      id: tempId,
      chatId: chatId,
      senderId: currentUserId,
      text: text.trim(),
      replyToMessageId: replyToMessageId,
      createdAt: nowIso,
      isRead: false,
      isPending: true,
    );

    // 1. Оптимистично добавляем в список сообщений
    if (!_messagesByChat.containsKey(chatId)) {
      _messagesByChat[chatId] = [];
    }
    _messagesByChat[chatId]!.add(optimisticMsg);

    // 2. Обновляем превью в списке чатов
    _updateChatPreview(chatId, text.trim(), nowIso);
    notifyListeners();

    // 3. Отправляем на бэкенд через REST
    try {
      final res = await ApiService.instance.sendMessage(chatId, text.trim(), replyToMessageId: replyToMessageId);
      if (res['success'] == true && res['message'] != null) {
        final serverMsg = Message.fromJson(res['message'] as Map<String, dynamic>);
        
        // Заменяем временное сообщение реальным
        final list = _messagesByChat[chatId];
        if (list != null) {
          final idx = list.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            list[idx] = serverMsg;
          }
        }
        await DatabaseHelper.instance.insertMessage(serverMsg);
      }
    } catch (e) {
      debugPrint('Failed to send message: $e');
      // Помечаем ошибку отправки если нужно
      final list = _messagesByChat[chatId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          list[idx] = list[idx].copyWith(isPending: false);
        }
      }
    }

    notifyListeners();
  }

  void cancelPendingMessage(int chatId, int messageId) {
    final list = _messagesByChat[chatId];
    if (list != null) {
      list.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  Future<void> sendPhotoMessage(
    int chatId, {
    required List<File> files,
    required String caption,
    int? replyToMessageId,
  }) async {
    if (files.isEmpty) return;

    final currentUserId = await SecureStorageService.instance.getCurrentUserId() ?? 0;
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();

    final localPaths = files.map((f) => f.path).toList();
    final optimisticPayload = '[PORTAL_PHOTO]:' +
        jsonEncode({
          'url': localPaths.first,
          'urls': localPaths,
          'caption': caption,
        });

    final optimisticMsg = Message(
      id: tempId,
      chatId: chatId,
      senderId: currentUserId,
      text: optimisticPayload,
      replyToMessageId: replyToMessageId,
      createdAt: nowIso,
      isRead: false,
      isPending: true,
    );

    if (!_messagesByChat.containsKey(chatId)) {
      _messagesByChat[chatId] = [];
    }
    _messagesByChat[chatId]!.add(optimisticMsg);
    _updateChatPreview(chatId, '📷 Фотография', nowIso);
    notifyListeners();

    try {
      final List<String> uploadedUrls = [];
      for (final file in files) {
        final uploadedUrl = await ApiService.instance.uploadPhoto(file);
        if (uploadedUrl.isNotEmpty) {
          uploadedUrls.add(uploadedUrl);
        }
      }

      if (uploadedUrls.isEmpty) throw Exception('Не удалось загрузить фотографии');

      final serverPayload = '[PORTAL_PHOTO]:' +
          jsonEncode({
            'url': uploadedUrls.first,
            'urls': uploadedUrls,
            'caption': caption,
          });

      final res = await ApiService.instance.sendMessage(
        chatId,
        serverPayload,
        replyToMessageId: replyToMessageId,
      );

      if (res['success'] == true && res['message'] != null) {
        final serverMsg = Message.fromJson(res['message'] as Map<String, dynamic>);
        final list = _messagesByChat[chatId];
        if (list != null) {
          final idx = list.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            list[idx] = serverMsg;
          }
        }
        await DatabaseHelper.instance.insertMessage(serverMsg);
      }
    } catch (e) {
      debugPrint('Failed to send photo message: $e');
      final list = _messagesByChat[chatId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          list[idx] = list[idx].copyWith(isPending: false);
        }
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendVoiceMessage(
    int chatId, {
    required File voiceFile,
    required int durationSec,
    int? replyToMessageId,
  }) async {
    final currentUserId = await SecureStorageService.instance.getCurrentUserId() ?? 0;
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();

    final optimisticPayload = '[PORTAL_VOICE]:' +
        jsonEncode({
          'url': voiceFile.path,
          'localPath': voiceFile.path,
          'duration': durationSec,
        });

    final optimisticMsg = Message(
      id: tempId,
      chatId: chatId,
      senderId: currentUserId,
      text: optimisticPayload,
      replyToMessageId: replyToMessageId,
      createdAt: nowIso,
      isRead: false,
      isPending: true,
    );

    if (!_messagesByChat.containsKey(chatId)) {
      _messagesByChat[chatId] = [];
    }
    _messagesByChat[chatId]!.add(optimisticMsg);
    _updateChatPreview(chatId, '🎤 Голосовое сообщение', nowIso);
    notifyListeners();

    try {
      final uploadedUrl = await ApiService.instance.uploadVoice(voiceFile);
      final serverPayload = '[PORTAL_VOICE]:' +
          jsonEncode({
            'url': uploadedUrl,
            'duration': durationSec,
          });

      final res = await ApiService.instance.sendMessage(
        chatId,
        serverPayload,
        replyToMessageId: replyToMessageId,
      );

      if (res['success'] == true && res['message'] != null) {
        final serverMsg = Message.fromJson(res['message'] as Map<String, dynamic>);
        final list = _messagesByChat[chatId];
        if (list != null) {
          final idx = list.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            list[idx] = serverMsg;
          }
        }
        await DatabaseHelper.instance.insertMessage(serverMsg);
      }
    } catch (e) {
      debugPrint('Failed to send voice message: $e');
      final list = _messagesByChat[chatId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          list[idx] = list[idx].copyWith(isPending: false);
        }
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> addOrUpdateChat(Chat chat) async {
    final idx = _chats.indexWhere((c) => c.id == chat.id);
    if (idx != -1) {
      _chats[idx] = chat;
    } else {
      _chats.insert(0, chat);
    }
    _sortChats();
    await DatabaseHelper.instance.insertChat(chat);
    notifyListeners();
  }

  Future<bool> togglePinChat(int chatId, bool isPremium) async {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return false;

    final chat = _chats[idx];
    final willPin = !chat.isPinned;

    if (willPin) {
      final currentPinnedCount = _chats.where((c) => c.isPinned).length;
      final maxPins = isPremium ? 10 : 3;
      if (currentPinnedCount >= maxPins) {
        return false;
      }
    }

    _chats[idx] = chat.copyWith(isPinned: willPin);
    _sortChats();
    await DatabaseHelper.instance.updateChatPinned(chatId, willPin);
    notifyListeners();

    try {
      await ApiService.instance.togglePinChat(chatId);
    } catch (_) {}

    return true;
  }

  Future<void> deleteChat(int chatId) async {
    _chats.removeWhere((c) => c.id == chatId);
    _messagesByChat.remove(chatId);
    _sortChats();
    notifyListeners();

    await DatabaseHelper.instance.deleteChat(chatId);

    try {
      await ApiService.instance.deleteChat(chatId);
    } catch (_) {}

    try {
      WebSocketService.instance.send({
        'type': 'delete_chat',
        'chat_id': chatId,
      });
    } catch (_) {}
  }

  void updateMessageViews(int messageId, int viewsCount) {
    bool updated = false;
    for (final entry in _messagesByChat.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(viewsCount: viewsCount, isViewed: true);
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
      DatabaseHelper.instance.updateMessageViews(messageId, viewsCount);
    }
  }

  void updateMessageCommentsCount(int messageId, int commentsCount) {
    bool updated = false;
    for (final entry in _messagesByChat.entries) {
      final list = entry.value;
      final idx = list.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(commentsCount: commentsCount);
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
      DatabaseHelper.instance.updateMessageCommentsCount(messageId, commentsCount);
    }
  }

  void _updateChatPreview(int chatId, String text, String time) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx != -1) {
      final updated = _chats[idx].copyWith(
        lastMessageText: text,
        lastMessageTime: time,
      );
      _chats.removeAt(idx);
      // Переносим наверх списка (с учетом pinned)
      _chats.insert(0, updated);
      _sortChats();
    }
  }

  void _sortChats() {
    _chats.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
  }

  void _handleWebSocketEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();

    switch (type) {
      case 'new_message':
        final msgData = event['message'];
        if (msgData is Map<String, dynamic>) {
          final msg = Message.fromJson(msgData);
          await DatabaseHelper.instance.insertMessage(msg);

          final trimmedText = msg.text.trim();
          if (trimmedText.startsWith('[PORTAL_GIFT]:') ||
              (trimmedText.startsWith('{') && trimmedText.contains('"type":"gift_card"'))) {
            try {
              final jsonStr = trimmedText.startsWith('[PORTAL_GIFT]:')
                  ? trimmedText.substring('[PORTAL_GIFT]:'.length).trim()
                  : trimmedText;
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              final rId = map['recipientId'] is int
                  ? map['recipientId'] as int
                  : (int.tryParse(map['recipientId']?.toString() ?? '') ?? msg.chatId);
              final gift = UserGift.fromJson(map, fallbackUserId: rId);
              await DatabaseHelper.instance.insertUserGift(gift);
            } catch (_) {}
          }

          // Если чат открыт
          if (_activeChatId == msg.chatId) {
            final list = _messagesByChat[msg.chatId] ?? [];
            if (!list.any((m) => m.id == msg.id)) {
              list.add(msg);
              _messagesByChat[msg.chatId] = list;
            }
          }

          // Обновляем список чатов
          final unreadDelta = (_activeChatId == msg.chatId) ? 0 : 1;
          await DatabaseHelper.instance.updateChatLastMessage(
            msg.chatId,
            msg.text,
            msg.createdAt,
            unreadDelta: unreadDelta,
          );
          _chats = await DatabaseHelper.instance.getChats();
          notifyListeners();
        }
        break;

      case 'typing':
      case 'user_typing':
        final chatId = event['chat_id'] is int
            ? event['chat_id'] as int
            : int.tryParse(event['chat_id']?.toString() ?? '') ??
                (event['chatId'] is int ? event['chatId'] as int : int.tryParse(event['chatId']?.toString() ?? '') ?? 0);
        final userId = event['user_id'] is int
            ? event['user_id'] as int
            : int.tryParse(event['user_id']?.toString() ?? '') ??
                (event['userId'] is int ? event['userId'] as int : int.tryParse(event['userId']?.toString() ?? '') ?? 0);
        final isTyping = event['is_typing'] == true || event['isTyping'] == true || !event.containsKey('is_typing');

        if (chatId > 0) {
          if (isTyping) {
            _typingUsers.putIfAbsent(chatId, () => {}).add(userId > 0 ? userId : 1);
            notifyListeners();

            Timer(const Duration(milliseconds: 3500), () {
              if (_typingUsers.containsKey(chatId)) {
                _typingUsers[chatId]?.remove(userId > 0 ? userId : 1);
                notifyListeners();
              }
            });
          } else {
            _typingUsers[chatId]?.remove(userId > 0 ? userId : 1);
            notifyListeners();
          }
        }
        break;

      case 'user_presence':
      case 'user_status':
      case 'status':
        final userId = event['user_id'] is int
            ? event['user_id'] as int
            : int.tryParse(event['user_id']?.toString() ?? '') ??
                (event['userId'] is int ? event['userId'] as int : int.tryParse(event['userId']?.toString() ?? '') ?? 0);
        final isOnline = event['is_online'] == true || event['is_online'] == 1 || event['status'] == 'online';
        final lastSeen = event['last_seen']?.toString();

        if (userId > 0) {
          _userPresence[userId] = isOnline;

          // 1. Сохраняем онлайн-активность в SQLite базу данных
          await DatabaseHelper.instance.updateUserPresence(
            userId: userId,
            isOnline: isOnline,
            lastSeen: lastSeen,
          );

          // 2. Обновляем локальные объекты чатов в памяти
          bool changed = false;
          for (int i = 0; i < _chats.length; i++) {
            if (_chats[i].participantId == userId || _chats[i].id == userId) {
              _chats[i] = _chats[i].copyWith(
                isOnline: isOnline,
                lastSeen: lastSeen ?? _chats[i].lastSeen,
              );
              changed = true;
            }
          }
          if (changed) {
            notifyListeners();
          }
        }
        break;

      case 'messages_read':
        final chatId = event['chat_id'] is int ? event['chat_id'] as int : int.tryParse(event['chat_id'].toString()) ?? 0;
        if (chatId > 0 && _messagesByChat.containsKey(chatId)) {
          final list = _messagesByChat[chatId]!;
          _messagesByChat[chatId] = list.map((m) => m.copyWith(isRead: true)).toList();
          notifyListeners();
        }
        break;

      case 'message_deleted':
        final chatId = event['chat_id'] is int
            ? event['chat_id'] as int
            : int.tryParse(event['chat_id']?.toString() ?? '') ??
                (event['chatId'] is int ? event['chatId'] as int : int.tryParse(event['chatId']?.toString() ?? '') ?? 0);
        final messageId = event['message_id'] is int
            ? event['message_id'] as int
            : int.tryParse(event['message_id']?.toString() ?? '') ??
                (event['messageId'] is int ? event['messageId'] as int : int.tryParse(event['messageId']?.toString() ?? '') ?? 0);
        if (messageId > 0) {
          if (chatId > 0 && _messagesByChat.containsKey(chatId)) {
            _messagesByChat[chatId]?.removeWhere((m) => m.id == messageId);
          } else {
            for (final list in _messagesByChat.values) {
              list.removeWhere((m) => m.id == messageId);
            }
          }
          if (_pinnedMessages[chatId]?.id == messageId) {
            _pinnedMessages.remove(chatId);
          }
          await DatabaseHelper.instance.deleteMessage(messageId);
          notifyListeners();
        }
        break;

      case 'chat_pinned_message':
        final chatId = event['chat_id'] is int
            ? event['chat_id'] as int
            : int.tryParse(event['chat_id']?.toString() ?? '') ??
                (event['chatId'] is int ? event['chatId'] as int : int.tryParse(event['chatId']?.toString() ?? '') ?? 0);
        final isPinned = event['isPinned'] == true || event['is_pinned'] == true;
        if (chatId > 0) {
          if (isPinned && event['pinnedMessage'] != null) {
            _pinnedMessages[chatId] = Message.fromJson(event['pinnedMessage'] as Map<String, dynamic>);
          } else {
            _pinnedMessages.remove(chatId);
          }
          notifyListeners();
        }
        break;

      case 'chat_deleted':
      case 'delete_chat':
        final chatId = event['chat_id'] is int
            ? event['chat_id'] as int
            : int.tryParse(event['chat_id']?.toString() ?? '') ??
                (event['chatId'] is int ? event['chatId'] as int : int.tryParse(event['chatId']?.toString() ?? '') ?? 0);
        if (chatId > 0) {
          _chats.removeWhere((c) => c.id == chatId);
          _messagesByChat.remove(chatId);
          await DatabaseHelper.instance.deleteChat(chatId);
          notifyListeners();
        }
        break;

      case 'message_edited':
        final msgData = event['message'];
        if (msgData is Map<String, dynamic>) {
          final editedMsg = Message.fromJson(msgData);
          final cId = editedMsg.chatId;
          if (_messagesByChat.containsKey(cId)) {
            final list = _messagesByChat[cId]!;
            final idx = list.indexWhere((m) => m.id == editedMsg.id);
            if (idx != -1) {
              list[idx] = editedMsg;
            }
          }
          await DatabaseHelper.instance.insertMessage(editedMsg);
          if (_pinnedMessages[cId]?.id == editedMsg.id) {
            _pinnedMessages[cId] = editedMsg;
          }
          notifyListeners();
        }
        break;

      case 'message_viewed':
      case 'post_viewed':
        final messageId = event['message_id'] is int
            ? event['message_id'] as int
            : int.tryParse(event['message_id']?.toString() ?? '') ??
                (event['messageId'] is int ? event['messageId'] as int : int.tryParse(event['messageId']?.toString() ?? '') ?? 0);
        final viewsCount = event['views_count'] is int
            ? event['views_count'] as int
            : int.tryParse(event['views_count']?.toString() ?? '') ??
                (event['viewsCount'] is int ? event['viewsCount'] as int : int.tryParse(event['viewsCount']?.toString() ?? '') ?? 0);
        if (messageId > 0 && viewsCount > 0) {
          updateMessageViews(messageId, viewsCount);
        }
        break;

      case 'comment_added':
      case 'post_comment':
        final messageId = event['message_id'] is int
            ? event['message_id'] as int
            : int.tryParse(event['message_id']?.toString() ?? '') ??
                (event['messageId'] is int ? event['messageId'] as int : int.tryParse(event['messageId']?.toString() ?? '') ?? 0);
        final commentsCount = event['comments_count'] is int
            ? event['comments_count'] as int
            : int.tryParse(event['comments_count']?.toString() ?? '') ??
                (event['commentsCount'] is int ? event['commentsCount'] as int : int.tryParse(event['commentsCount']?.toString() ?? '') ?? 0);
        if (messageId > 0 && commentsCount > 0) {
          updateMessageCommentsCount(messageId, commentsCount);
        }
        break;
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }
}
