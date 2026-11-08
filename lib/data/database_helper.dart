import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user_gift.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('portal_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            first_name TEXT,
            last_name TEXT,
            username TEXT,
            avatar TEXT,
            banner_url TEXT,
            description TEXT,
            phone TEXT,
            email TEXT,
            sparks INTEGER DEFAULT 250,
            is_premium INTEGER DEFAULT 0,
            verification TEXT DEFAULT 'none',
            is_online INTEGER DEFAULT 0,
            last_seen TEXT DEFAULT '',
            secondary_usernames TEXT DEFAULT '',
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE chats (
            id INTEGER PRIMARY KEY,
            title TEXT,
            type TEXT,
            avatar TEXT,
            last_message_text TEXT,
            last_message_time TEXT,
            unread_count INTEGER DEFAULT 0,
            is_pinned INTEGER DEFAULT 0,
            is_channel INTEGER DEFAULT 0,
            is_online INTEGER DEFAULT 0,
            last_seen TEXT DEFAULT '',
            participant_id INTEGER,
            owner_id INTEGER,
            banner_url TEXT,
            description TEXT,
            phone TEXT,
            username TEXT,
            verification TEXT,
            updated_at TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY,
            chat_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            text TEXT,
            reply_to_message_id INTEGER,
            created_at TEXT,
            is_read INTEGER DEFAULT 0,
            sender_name TEXT,
            sender_avatar TEXT
          );
        ''');

        await db.execute('''
          CREATE TABLE user_gifts (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            gift_id INTEGER,
            gift_name TEXT,
            model_name TEXT,
            model_file TEXT,
            backdrop_name TEXT,
            backdrop_gradient TEXT,
            pattern_name TEXT,
            pattern_svg TEXT,
            nft_number INTEGER,
            sender_id INTEGER,
            sender_first_name TEXT,
            sender_last_name TEXT,
            sender_username TEXT,
            sender_avatar TEXT,
            created_at TEXT,
            is_upgraded INTEGER DEFAULT 0,
            is_pinned INTEGER DEFAULT 0,
            is_hidden INTEGER DEFAULT 0,
            comment TEXT
          );
        ''');

        await db.execute('CREATE INDEX idx_messages_chat ON messages(chat_id, id DESC);');
        await db.execute('CREATE INDEX idx_user_gifts_user ON user_gifts(user_id);');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _checkAndUpgradeSchema(db);
      },
    );

    // Also verify schema in case db was opened without onUpgrade
    await _checkAndUpgradeSchema(db);
    return db;
  }

  Future<void> _checkAndUpgradeSchema(Database db) async {
    try {
      final chatCols = (await db.rawQuery("PRAGMA table_info(chats)"))
          .map((e) => e['name']?.toString())
          .toSet();
      if (!chatCols.contains('participant_id')) {
        await db.execute('ALTER TABLE chats ADD COLUMN participant_id INTEGER;');
      }
      if (!chatCols.contains('owner_id')) {
        await db.execute('ALTER TABLE chats ADD COLUMN owner_id INTEGER;');
      }
      if (!chatCols.contains('banner_url')) {
        await db.execute("ALTER TABLE chats ADD COLUMN banner_url TEXT DEFAULT '';");
      }
      if (!chatCols.contains('description')) {
        await db.execute("ALTER TABLE chats ADD COLUMN description TEXT DEFAULT '';");
      }
      if (!chatCols.contains('phone')) {
        await db.execute("ALTER TABLE chats ADD COLUMN phone TEXT DEFAULT '';");
      }
      if (!chatCols.contains('username')) {
        await db.execute("ALTER TABLE chats ADD COLUMN username TEXT DEFAULT '';");
      }
      if (!chatCols.contains('verification')) {
        await db.execute("ALTER TABLE chats ADD COLUMN verification TEXT DEFAULT 'none';");
      }
      if (!chatCols.contains('is_online')) {
        await db.execute("ALTER TABLE chats ADD COLUMN is_online INTEGER DEFAULT 0;");
      }
      if (!chatCols.contains('last_seen')) {
        await db.execute("ALTER TABLE chats ADD COLUMN last_seen TEXT DEFAULT '';");
      }
      if (!chatCols.contains('subscribers_count')) {
        await db.execute("ALTER TABLE chats ADD COLUMN subscribers_count INTEGER DEFAULT 0;");
      }
      if (!chatCols.contains('is_subscribed')) {
        await db.execute("ALTER TABLE chats ADD COLUMN is_subscribed INTEGER DEFAULT 0;");
      }
      if (!chatCols.contains('is_premium')) {
        await db.execute("ALTER TABLE chats ADD COLUMN is_premium INTEGER DEFAULT 0;");
      }

      final userCols = (await db.rawQuery("PRAGMA table_info(users)"))
          .map((e) => e['name']?.toString())
          .toSet();
      if (!userCols.contains('banner_url')) {
        await db.execute("ALTER TABLE users ADD COLUMN banner_url TEXT DEFAULT '';");
      }
      if (!userCols.contains('description')) {
        await db.execute("ALTER TABLE users ADD COLUMN description TEXT DEFAULT '';");
      }
      if (!userCols.contains('phone')) {
        await db.execute("ALTER TABLE users ADD COLUMN phone TEXT DEFAULT '';");
      }
      if (!userCols.contains('email')) {
        await db.execute("ALTER TABLE users ADD COLUMN email TEXT DEFAULT '';");
      }
      if (!userCols.contains('sparks')) {
        await db.execute("ALTER TABLE users ADD COLUMN sparks INTEGER DEFAULT 250;");
      }
      if (!userCols.contains('is_premium')) {
        await db.execute("ALTER TABLE users ADD COLUMN is_premium INTEGER DEFAULT 0;");
      }
      if (!userCols.contains('verification')) {
        await db.execute("ALTER TABLE users ADD COLUMN verification TEXT DEFAULT 'none';");
      }
      if (!userCols.contains('is_online')) {
        await db.execute("ALTER TABLE users ADD COLUMN is_online INTEGER DEFAULT 0;");
      }
      if (!userCols.contains('last_seen')) {
        await db.execute("ALTER TABLE users ADD COLUMN last_seen TEXT DEFAULT '';");
      }
      if (!userCols.contains('secondary_usernames')) {
        await db.execute("ALTER TABLE users ADD COLUMN secondary_usernames TEXT DEFAULT '';");
      }
      if (!userCols.contains('updated_at')) {
        await db.execute("ALTER TABLE users ADD COLUMN updated_at TEXT DEFAULT '';");
      }

      final msgCols = (await db.rawQuery("PRAGMA table_info(messages)"))
          .map((e) => e['name']?.toString())
          .toSet();
      if (!msgCols.contains('is_edited')) {
        await db.execute("ALTER TABLE messages ADD COLUMN is_edited INTEGER DEFAULT 0;");
      }
      if (!msgCols.contains('comments_count')) {
        await db.execute("ALTER TABLE messages ADD COLUMN comments_count INTEGER DEFAULT 0;");
      }
      if (!msgCols.contains('views_count')) {
        await db.execute("ALTER TABLE messages ADD COLUMN views_count INTEGER DEFAULT 1;");
      }
      if (!msgCols.contains('is_viewed')) {
        await db.execute("ALTER TABLE messages ADD COLUMN is_viewed INTEGER DEFAULT 0;");
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_gifts (
          id INTEGER PRIMARY KEY,
          user_id INTEGER NOT NULL,
          gift_id INTEGER,
          gift_name TEXT,
          model_name TEXT,
          model_file TEXT,
          backdrop_name TEXT,
          backdrop_gradient TEXT,
          pattern_name TEXT,
          pattern_svg TEXT,
          nft_number INTEGER,
          sender_id INTEGER,
          sender_first_name TEXT,
          sender_last_name TEXT,
          sender_username TEXT,
          sender_avatar TEXT,
          created_at TEXT,
          is_upgraded INTEGER DEFAULT 0,
          is_pinned INTEGER DEFAULT 0,
          is_hidden INTEGER DEFAULT 0,
          comment TEXT
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_user_gifts_user ON user_gifts(user_id);');
    } catch (_) {}
  }

  // Обновление онлайн-статуса пользователя в БД
  Future<void> updateUserPresence({
    required int userId,
    required bool isOnline,
    String? lastSeen,
  }) async {
    try {
      final db = await instance.database;
      final nowStr = lastSeen ?? (isOnline ? '' : DateTime.now().toUtc().toIso8601String());
      await db.update(
        'chats',
        {
          'is_online': isOnline ? 1 : 0,
          if (nowStr.isNotEmpty) 'last_seen': nowStr,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'participant_id = ? OR id = ?',
        whereArgs: [userId, userId],
      );
      await db.update(
        'users',
        {
          'is_online': isOnline ? 1 : 0,
          if (nowStr.isNotEmpty) 'last_seen': nowStr,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    } catch (_) {}
  }

  // Обновление данных профиля пользователя в локальной БД
  Future<void> updateUserProfile(User user) async {
    try {
      final db = await instance.database;
      await db.update(
        'users',
        user.toMap(),
        where: 'id = ?',
        whereArgs: [user.id],
      );
      // Также обновляем чаты и сообщения, связанные с пользователем
      final title = user.fullName.isNotEmpty ? user.fullName : user.username;
      await db.update(
        'chats',
        {
          'title': title,
          'avatar': user.avatar,
          'username': user.username,
          'verification': user.effectiveVerification,
          'is_premium': user.isPremium ? 1 : 0,
          if (user.description != null) 'description': user.description,
          if (user.bannerUrl != null) 'banner_url': user.bannerUrl,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'participant_id = ?',
        whereArgs: [user.id],
      );
    } catch (_) {}
  }

  // Обновление верификации и премиум статуса чата
  Future<void> updateChatVerification({
    required int chatId,
    required String verification,
    bool? isPremium,
  }) async {
    try {
      final db = await instance.database;
      final values = <String, dynamic>{
        'verification': verification,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (isPremium != null) {
        values['is_premium'] = isPremium ? 1 : 0;
      }
      await db.update(
        'chats',
        values,
        where: 'id = ?',
        whereArgs: [chatId],
      );
    } catch (_) {}
  }

  // Обновление баланса Sparks пользователя в локальной БД
  Future<void> updateUserSparks(int userId, int sparks) async {
    try {
      final db = await instance.database;
      await db.update(
        'users',
        {
          'sparks': sparks,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    } catch (_) {}
  }

  // Быстрое сохранение бутстрапа в одной транзакции
  Future<void> saveBootstrap({
    required Map<String, dynamic> user,
    required List<dynamic> chats,
    required Map<String, dynamic> recentMessages,
  }) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Сохраняем профиль
      if (user.isNotEmpty) {
        await txn.insert(
          'users',
          {
            'id': user['id'] is int ? user['id'] : int.tryParse(user['id'].toString()) ?? 0,
            'first_name': user['first_name']?.toString() ?? '',
            'last_name': user['last_name']?.toString() ?? '',
            'username': user['username']?.toString() ?? '',
            'avatar': user['avatar']?.toString() ?? '',
            'banner_url': user['banner_url']?.toString() ?? user['banner']?.toString() ?? '',
            'description': user['description']?.toString() ?? user['about']?.toString() ?? '',
            'phone': user['phone']?.toString() ?? '',
            'email': user['email']?.toString() ?? '',
            'sparks': user['sparks'] is int ? user['sparks'] : int.tryParse(user['sparks']?.toString() ?? '250') ?? 250,
            'is_premium': (user['is_premium'] == true || user['is_premium'] == 1) ? 1 : 0,
            'verification': user['verification']?.toString() ?? 'none',
            'is_online': (user['is_online'] == true || user['is_online'] == 1) ? 1 : 0,
            'last_seen': user['last_seen']?.toString() ?? '',
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Сохраняем чаты
      final batch = txn.batch();
      for (final c in chats) {
        if (c is! Map<String, dynamic>) continue;
        final lastMsg = c['last_message'];
        String lastText = '';
        String lastTime = '';
        if (lastMsg is Map<String, dynamic>) {
          lastText = lastMsg['text']?.toString() ?? '';
          lastTime = lastMsg['created_at']?.toString() ?? '';
        } else if (c['last_message_text'] != null) {
          lastText = c['last_message_text'].toString();
          lastTime = c['last_message_time']?.toString() ?? '';
        }

        final pId = c['participant_id'] is int
            ? c['participant_id'] as int
            : int.tryParse(c['participant_id']?.toString() ?? '') ??
                (c['owner_id'] is int ? c['owner_id'] as int : null);

        final oId = c['owner_id'] is int
            ? c['owner_id'] as int
            : int.tryParse(c['owner_id']?.toString() ?? '');

        final rawVerif = c['verification']?.toString() ??
            c['channel_verification']?.toString() ??
            c['sender_verification']?.toString();
        final isChan = (c['is_channel'] == 1 || c['is_channel'] == true);
        final title = c['title']?.toString() ?? c['first_name']?.toString() ?? 'Чат';
        final uname = c['username']?.toString() ?? '';

        final effectiveV = (rawVerif != null && rawVerif.isNotEmpty && rawVerif != 'none')
            ? rawVerif
            : (uname.toLowerCase() == 'revs' ? 'dev' :
               ((uname.toLowerCase() == 'portal' || (isChan && title.toLowerCase().contains('portal'))) ? 'verified' :
                (uname.toLowerCase() == 'botfather' ? 'verified' : 'none')));

        batch.insert(
          'chats',
          {
            'id': (c['chat_id'] ?? c['id']) is int ? (c['chat_id'] ?? c['id']) : int.tryParse((c['chat_id'] ?? c['id']).toString()) ?? 0,
            'title': title,
            'type': isChan ? 'channel' : 'direct',
            'avatar': c['avatar']?.toString() ?? '',
            'last_message_text': lastText,
            'last_message_time': lastTime,
            'unread_count': c['unread_count'] is int ? c['unread_count'] : int.tryParse(c['unread_count']?.toString() ?? '0') ?? 0,
            'is_pinned': (c['is_pinned'] == 1 || c['is_pinned'] == true) ? 1 : 0,
            'is_channel': isChan ? 1 : 0,
            'is_online': (c['is_online'] == true || c['is_online'] == 1) ? 1 : 0,
            'last_seen': c['last_seen']?.toString() ?? '',
            'participant_id': pId,
            'owner_id': oId,
            'banner_url': c['banner_url']?.toString() ?? c['banner']?.toString() ?? '',
            'description': c['description']?.toString() ?? c['about']?.toString() ?? '',
            'phone': c['phone']?.toString() ?? '',
            'username': uname,
            'verification': effectiveV,
            'is_premium': (c['is_premium'] == true || c['is_premium'] == 1 || c['isPremium'] == true) ? 1 : 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Сохраняем сообщения
      recentMessages.forEach((chatIdStr, msgs) {
        if (msgs is List) {
          for (final m in msgs) {
            if (m is! Map<String, dynamic>) continue;
            batch.insert(
              'messages',
              {
                'id': m['id'] is int ? m['id'] : int.tryParse(m['id'].toString()) ?? 0,
                'chat_id': m['chat_id'] is int ? m['chat_id'] : int.tryParse(m['chat_id'].toString()) ?? 0,
                'sender_id': m['sender_id'] is int ? m['sender_id'] : int.tryParse(m['sender_id'].toString()) ?? 0,
                'text': m['text']?.toString() ?? '',
                'reply_to_message_id': m['reply_to_message_id'] as int?,
                'created_at': m['created_at']?.toString() ?? '',
                'is_read': (m['is_read'] == true || m['is_read'] == 1) ? 1 : 0,
                'sender_name': m['sender_first_name']?.toString() ?? m['sender_name']?.toString() ?? '',
                'sender_avatar': m['sender_avatar']?.toString() ?? '',
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      await batch.commit(noResult: true);
    });
  }

  // Получение списка чатов (закрепленные вверху, затем по времени последнего сообщения)
  Future<List<Chat>> getChats() async {
    final db = await instance.database;
    final result = await db.query(
      'chats',
      orderBy: 'is_pinned DESC, last_message_time DESC, id DESC',
    );
    return result.map((m) => Chat.fromMap(m)).toList();
  }

  // Получение истории сообщений по чату
  Future<List<Message>> getMessages(int chatId, {int limit = 50}) async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return result.map((m) => Message.fromMap(m)).toList();
  }

  // Сохранение одного сообщения (при отправке или получении по WS)
  Future<void> insertMessage(Message message) async {
    final db = await instance.database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Также обновляем последний текст в чате
    await updateChatLastMessage(
      message.chatId,
      message.text,
      message.createdAt,
    );
  }

  // Удаление сообщения
  Future<void> deleteMessage(int messageId) async {
    try {
      final db = await instance.database;
      await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
    } catch (_) {}
  }

  // Редактирование сообщения
  Future<void> editMessage(int messageId, String newText) async {
    try {
      final db = await instance.database;
      await db.update(
        'messages',
        {
          'text': newText,
          'is_edited': 1,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (_) {}
  }

  // Обновление количества просмотров сообщения
  Future<void> updateMessageViews(int messageId, int viewsCount) async {
    try {
      final db = await instance.database;
      await db.update(
        'messages',
        {
          'views_count': viewsCount,
          'is_viewed': 1,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (_) {}
  }

  // Обновление количества комментариев сообщения
  Future<void> updateMessageCommentsCount(int messageId, int commentsCount) async {
    try {
      final db = await instance.database;
      await db.update(
        'messages',
        {
          'comments_count': commentsCount,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (_) {}
  }

  // Обновление последнего сообщения в чате
  Future<void> updateChatLastMessage(int chatId, String text, String time, {int unreadDelta = 0}) async {
    final db = await instance.database;
    if (unreadDelta > 0) {
      await db.rawUpdate(
        'UPDATE chats SET last_message_text = ?, last_message_time = ?, unread_count = unread_count + ?, updated_at = ? WHERE id = ?',
        [text, time, unreadDelta, DateTime.now().toIso8601String(), chatId],
      );
    } else {
      await db.update(
        'chats',
        {
          'last_message_text': text,
          'last_message_time': time,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [chatId],
      );
    }
  }

  // Сброс счетчика непрочитанных
  Future<void> resetUnread(int chatId) async {
    final db = await instance.database;
    await db.update(
      'chats',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  // Добавление или обновление чата в БД
  Future<void> insertChat(Chat chat) async {
    final db = await instance.database;
    await db.insert(
      'chats',
      chat.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Обновление статуса закрепления чата
  Future<void> updateChatPinned(int chatId, bool isPinned) async {
    final db = await instance.database;
    await db.update(
      'chats',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  // Удаление чата и его сообщений из локальной БД
  Future<void> deleteChat(int chatId) async {
    final db = await instance.database;
    await db.delete(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    await db.delete(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  // Получение данных пользователя
  Future<User?> getUser(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  // Вставка одного подарка в БД (при отправке или получении)
  Future<void> insertUserGift(UserGift gift) async {
    try {
      final db = await instance.database;
      final map = gift.toMap();
      if (gift.id <= 0) {
        map.remove('id');
      }
      await db.insert(
        'user_gifts',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  // Сохранение подарков пользователя (кэш)
  Future<void> saveUserGifts(int userId, List<dynamic> gifts) async {
    try {
      final db = await instance.database;
      final batch = db.batch();
      // Очищаем старый кэш для этого пользователя
      batch.delete('user_gifts', where: 'user_id = ?', whereArgs: [userId]);
      // Удаляем любые поврежденные записи с timestamp в качестве id
      batch.delete('user_gifts', where: 'id > 1000000000');
      for (var g in gifts) {
        final UserGift parsed = g is UserGift
            ? g
            : UserGift.fromJson(Map<String, dynamic>.from(g as Map), fallbackUserId: userId);
        final map = parsed.toMap();
        if (parsed.id <= 0) {
          map.remove('id');
        }
        batch.insert('user_gifts', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  // Получение подарков пользователя из БД
  Future<List<UserGift>> getUserGifts(int userId, {int? altUserId}) async {
    final db = await instance.database;
    final rows = await db.query(
      'user_gifts',
      where: 'user_id = ? AND (id < 1000000000 OR id IS NULL)',
      whereArgs: [userId],
      orderBy: 'is_pinned DESC, id DESC',
    );
    return rows.map((r) => UserGift.fromMap(r)).toList();
  }

  // Обновление одного подарка в БД (после улучшения или изменения статуса)
  Future<void> updateUserGift(UserGift gift) async {
    try {
      final db = await instance.database;
      await db.update(
        'user_gifts',
        gift.toMap(),
        where: 'id = ?',
        whereArgs: [gift.id],
      );
    } catch (_) {}
  }

  // Очистка всех таблиц (при logout)
  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('users');
    await db.delete('chats');
    await db.delete('messages');
    await db.delete('user_gifts');
  }
}
