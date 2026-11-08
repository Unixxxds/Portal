import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/constants.dart';
import '../data/secure_storage_service.dart';
import '../models/post_comment.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  late final Dio _dio;

  ApiService._init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await SecureStorageService.instance.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) {
          // Log errors or handle 401 unauth
          return handler.next(error);
        },
      ),
    );
  }

  // 1. Отправка проверочного кода на email / телефон
  Future<Map<String, dynamic>> sendCode(String identifier) async {
    try {
      final clean = identifier.trim();
      final isEmail = clean.contains('@');
      final payload = {
        'identifier': clean,
        if (isEmail) 'email': clean else 'phone': clean,
      };

      final response = await _dio.post(
        '/api/auth/send-code',
        data: payload,
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true, 'message': 'Код отправлен'};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['error'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка при отправке кода');
    }
  }

  // 2. Подтверждение кода и вход
  Future<Map<String, dynamic>> verifyCode(String identifier, String code) async {
    try {
      final clean = identifier.trim();
      final isEmail = clean.contains('@');
      final payload = {
        'identifier': clean,
        'code': code.trim(),
        if (isEmail) 'email': clean else 'phone': clean,
      };

      final response = await _dio.post(
        '/api/auth/verify-code',
        data: payload,
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Неверный формат ответа сервера');
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['error'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Неверный код подтверждения');
    }
  }

  // 2.1 Подтверждение облачного пароля (2FA)
  Future<Map<String, dynamic>> verifyCloudPassword(String tempToken, String password) async {
    try {
      final response = await _dio.post(
        '/api/auth/verify-cloud-password',
        data: {
          'tempToken': tempToken,
          'password': password,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Неверный формат ответа сервера');
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.response!.data['error'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Неверный облачный пароль');
    }
  }

  // 3. Fast Sync Bootstrap
  Future<Map<String, dynamic>> getBootstrap({int limit = 30}) async {
    try {
      final response = await _dio.get(
        '/api/sync/bootstrap',
        queryParameters: {'limit': limit},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Некорректный ответ bootstrap');
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка синхронизации данных');
    }
  }

  // 4. Fast Sync Delta
  Future<Map<String, dynamic>> getDelta(String since) async {
    try {
      final response = await _dio.get(
        '/api/sync/delta',
        queryParameters: {'since': since},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': false};
    } catch (_) {
      return {'success': false};
    }
  }

  // 5. Загрузка истории сообщений чата
  Future<List<Map<String, dynamic>>> getChatHistory(int chatId, {int? before, int limit = 50}) async {
    try {
      final query = <String, dynamic>{'limit': limit};
      if (before != null) query['before'] = before;
      
      final response = await _dio.get(
        '/api/sync/chat/$chatId/history',
        queryParameters: query,
      );
      if (response.data is Map && response.data['messages'] is List && (response.data['messages'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(response.data['messages']);
      }
    } catch (_) {}

    try {
      final response = await _dio.get('/api/chats/$chatId/messages');
      if (response.data is Map && response.data['messages'] is List && (response.data['messages'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(response.data['messages']);
      } else if (response.data is List && (response.data as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } catch (_) {}

    try {
      final response = await _dio.get('/api/channels/$chatId/posts');
      if (response.data is Map && response.data['posts'] is List && (response.data['posts'] as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(response.data['posts']);
      } else if (response.data is List && (response.data as List).isNotEmpty) {
        return List<Map<String, dynamic>>.from(response.data);
      }
    } catch (_) {}

    return [];
  }

  // 6. Отправка сообщения
  Future<Map<String, dynamic>> sendMessage(int chatId, String text, {int? replyToMessageId}) async {
    try {
      final response = await _dio.post(
        '/api/chats/$chatId/messages',
        data: {
          'text': text.trim(),
          'replyToMessageId': replyToMessageId,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Не удалось отправить сообщение');
    }
  }

  // 6.1 Удаление сообщения
  Future<bool> deleteMessage(int messageId) async {
    try {
      final response = await _dio.delete('/api/messages/$messageId');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService.deleteMessage error: $e');
      return false;
    }
  }

  // 6.1.1 Редактирование сообщения
  Future<Map<String, dynamic>?> editMessage(int messageId, String text) async {
    try {
      final response = await _dio.put(
        '/api/messages/$messageId',
        data: {'text': text.trim()},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.editMessage error: $e');
    }
    return null;
  }

  // 6.2 Закрепление / открепление сообщения
  Future<Map<String, dynamic>?> togglePinMessage(int chatId, int? messageId) async {
    try {
      final response = await _dio.post(
        '/api/chats/$chatId/pin',
        data: {'messageId': messageId},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.togglePinMessage error: $e');
    }
    return null;
  }

  // 6.3 Получение закрепленного сообщения
  Future<Map<String, dynamic>?> getPinnedMessage(int chatId) async {
    try {
      final response = await _dio.get('/api/chats/$chatId/pin');
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.getPinnedMessage error: $e');
    }
    return null;
  }

  // 7. Получение текущего профиля авторизованного пользователя
  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _dio.get('/api/users/me');
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ApiService.getMe error: $e');
    }
    return {};
  }

  // 7.1 Получение профиля пользователя по ID
  Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      final response = await _dio.get('/api/users/$userId');
      if (response.data is Map) {
        final map = response.data as Map;
        if (map['user'] is Map) {
          return Map<String, dynamic>.from(map['user'] as Map);
        } else if (map['data'] is Map) {
          return Map<String, dynamic>.from(map['data'] as Map);
        } else if (map.containsKey('id') || map.containsKey('username')) {
          return Map<String, dynamic>.from(map);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 8. Поиск пользователя или канала по имени / @username
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final clean = query.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.isEmpty) return [];

    final List<Map<String, dynamic>> results = [];
    final Set<String> seen = {};

    void addItems(dynamic list, {bool isChannelFallback = false}) {
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            if (isChannelFallback) {
              map['is_channel'] = 1;
            }
            final id = map['chat_id'] ?? map['id'] ?? map['username'];
            final isChannel = map['is_channel'] == 1 || map['is_channel'] == true || map['type'] == 'channel';
            final key = '${isChannel ? 'c' : 'u'}_$id';
            if (!seen.contains(key)) {
              seen.add(key);
              results.add(map);
            }
          }
        }
      }
    }

    // 1. Поиск в /api/users/search
    try {
      final response = await _dio.get(
        '/api/users/search',
        queryParameters: {'q': clean},
      );
      if (response.data is Map) {
        final map = response.data as Map;
        addItems(map['users'] ?? map['data'] ?? map['results'] ?? map['items']);
        if (map['channels'] != null) {
          addItems(map['channels'], isChannelFallback: true);
        }
      } else if (response.data is List) {
        addItems(response.data);
      }
    } catch (_) {}

    // 2. Если в результатах нет каналов, пробуем /api/channels/search
    try {
      final response = await _dio.get(
        '/api/channels/search',
        queryParameters: {'q': clean},
      );
      if (response.data is Map) {
        final map = response.data as Map;
        addItems(map['channels'] ?? map['data'] ?? map['results'] ?? map['items'], isChannelFallback: true);
      } else if (response.data is List) {
        addItems(response.data, isChannelFallback: true);
      }
    } catch (_) {}

    return results;
  }

  // 9. Получение подарков пользователя
  Future<List<Map<String, dynamic>>> getUserGifts(int userId) async {
    try {
      List<Map<String, dynamic>> parseGifts(dynamic data) {
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (data is Map) {
          final map = data as Map;
          final list = map['gifts'] ?? map['user_gifts'] ?? map['userGifts'] ?? map['data'] ?? map['items'];
          if (list is List) {
            return list
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
        return [];
      }

      // 1. Primary endpoint
      try {
        final res = await _dio.get('/api/users/$userId/gifts');
        final items = parseGifts(res.data);
        if (items.isNotEmpty) return items;
      } catch (_) {}

      // 2. Alternative endpoint
      try {
        final res = await _dio.get('/api/gifts/user/$userId');
        final items = parseGifts(res.data);
        if (items.isNotEmpty) return items;
      } catch (_) {}

      return [];
    } catch (_) {
      return [];
    }
  }

  // 10. Отправка подарка
  Future<Map<String, dynamic>> sendGift({
    required String giftId,
    String? recipientUsername,
    int? recipientId,
    String? comment,
  }) async {
    try {
      final payload = <String, dynamic>{
        'giftId': giftId,
        if (recipientUsername != null && recipientUsername.isNotEmpty)
          'recipientUsername': recipientUsername.replaceFirst(RegExp(r'^@+'), '').trim(),
        if (recipientId != null && recipientId > 0)
          'recipientId': recipientId,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      };

      final response = await _dio.post(
        '/api/gifts/send',
        data: payload,
      );

      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true, 'data': response.data};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка при отправке подарка');
    }
  }

  // 10.1 Улучшение подарка (Upgrade gift)
  Future<Map<String, dynamic>?> upgradeGift({
    required int giftRecordId,
    Map<String, dynamic>? preselected,
  }) async {
    try {
      final payload = <String, dynamic>{
        'giftRecordId': giftRecordId,
        if (preselected != null) 'preselected': preselected,
      };
      final res = await _dio.post('/api/gifts/upgrade', data: payload);
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data);
      }
      return null;
    } catch (e) {
      debugPrint('Error upgrading gift: $e');
      return null;
    }
  }

  // 11. Создание или получение прямого диалога
  Future<Map<String, dynamic>> createDirectChat(int targetUserId) async {
    try {
      final response = await _dio.post(
        '/api/chats/direct',
        data: {'targetUserId': targetUserId},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true, 'data': response.data};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка при создании чата');
    }
  }

  // 12. Получение данных канала
  Future<Map<String, dynamic>?> getChannel(int chatId) async {
    try {
      final response = await _dio.get('/api/channels/$chatId');
      if (response.data is Map) {
        final map = response.data as Map;
        if (map['channel'] is Map) {
          return Map<String, dynamic>.from(map['channel'] as Map);
        }
        return Map<String, dynamic>.from(map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 13. Подписка / отписка от канала
  Future<Map<String, dynamic>> toggleChannelSubscription(int chatId, bool isSubscribed) async {
    try {
      final endpoint = isSubscribed
          ? '/api/channels/$chatId/unsubscribe'
          : '/api/channels/$chatId/subscribe';
      final response = await _dio.post(endpoint);
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true, 'is_subscribed': !isSubscribed};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка подписки на канал');
    }
  }

  // 13.1 Проверка доступности имени пользователя канала
  Future<bool> checkChannelUsername(String username) async {
    final clean = username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.length < 5 || clean.length > 12) return false;
    try {
      final response = await _dio.get(
        '/api/channels/check-username',
        queryParameters: {'username': clean},
      );
      if (response.data is Map) {
        return response.data['available'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('ApiService.checkChannelUsername error: $e');
      return false;
    }
  }

  // 13.2 Создание нового канала
  Future<Map<String, dynamic>> createChannel({
    required String title,
    required String username,
    String description = '',
    String avatar = '',
  }) async {
    try {
      final cleanUsername = username.trim().replaceFirst(RegExp(r'^@+'), '');
      final response = await _dio.post(
        '/api/channels',
        data: {
          'title': title.trim(),
          'username': cleanUsername,
          'description': description.trim(),
          'avatar': avatar.trim(),
        },
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true, 'data': response.data};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Ошибка при создании канала');
    }
  }

  // 13.3 Получение комментариев к посту
  Future<List<PostComment>> getPostComments(int messageId) async {
    try {
      final response = await _dio.get('/api/messages/$messageId/comments');
      if (response.data is Map && response.data['comments'] is List) {
        final list = response.data['comments'] as List;
        return list.map((item) => PostComment.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      }
      return [];
    } catch (e) {
      debugPrint('ApiService.getPostComments error: $e');
      return [];
    }
  }

  // 13.4 Отправка комментария к посту
  Future<Map<String, dynamic>> sendPostComment(int messageId, String text) async {
    try {
      final response = await _dio.post(
        '/api/messages/$messageId/comments',
        data: {'text': text.trim()},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return {'success': true};
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['error'] ?? e.response!.data['message'] ?? e.message)
          : e.message;
      throw Exception(msg ?? 'Не удалось отправить комментарий');
    }
  }

  // 13.5 Регистрация просмотра сообщения / поста
  Future<int?> viewMessage(int messageId) async {
    try {
      final response = await _dio.post('/api/messages/$messageId/view');
      if (response.data is Map && response.data['viewsCount'] != null) {
        final raw = response.data['viewsCount'];
        return raw is int ? raw : int.tryParse(raw.toString());
      }
    } catch (_) {}
    return null;
  }

  // 14. Загрузка файла фотографии на сервер
  Future<String> uploadPhoto(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(file.path, filename: fileName),
    });

    final res = await _dio.post('/api/upload-photo', data: formData);
    if (res.data is Map && res.data['url'] != null) {
      return res.data['url'].toString();
    }
    throw Exception('Не удалось загрузить изображение');
  }

  // 14.5 Загрузка голосового сообщения на сервер
  Future<String> uploadVoice(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    try {
      final formData = FormData.fromMap({
        'voice': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await _dio.post('/api/upload-voice', data: formData);
      if (res.data is Map && res.data['url'] != null) {
        return res.data['url'].toString();
      }
    } catch (_) {}

    try {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await _dio.post('/api/upload-voice', data: formData);
      if (res.data is Map && res.data['url'] != null) {
        return res.data['url'].toString();
      }
    } catch (_) {}

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await _dio.post('/api/upload-file', data: formData);
      if (res.data is Map && res.data['url'] != null) {
        return res.data['url'].toString();
      }
    } catch (_) {}

    try {
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await _dio.post('/api/upload-photo', data: formData);
      if (res.data is Map && res.data['url'] != null) {
        return res.data['url'].toString();
      }
    } catch (_) {}

    throw Exception('Не удалось загрузить голосовое сообщение');
  }

  // 15. Загрузка аватарки пользователя
  Future<String> uploadAvatar(File file) async {
    try {
      final url = await uploadPhoto(file);
      if (url.isNotEmpty) return url;
    } catch (_) {}

    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : (ext == 'gif' ? 'image/gif' : 'image/jpeg'));
    final base64String = 'data:$mime;base64,${base64Encode(bytes)}';

    final res = await _dio.post(
      '/api/upload/avatar',
      data: {'imageBase64': base64String},
    );
    if (res.data is Map && res.data['url'] != null) {
      return res.data['url'].toString();
    }
    throw Exception('Не удалось сохранить аватарку');
  }

  // 16. Загрузка баннера профиля
  Future<String> uploadBanner(File file) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'banner': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await _dio.post('/api/user/banner', data: formData);
      if (res.data is Map && (res.data['banner_url'] != null || res.data['url'] != null)) {
        return (res.data['banner_url'] ?? res.data['url']).toString();
      }
    } catch (_) {}

    final photoUrl = await uploadPhoto(file);
    try {
      await _dio.post('/api/user/banner', data: {'banner_url': photoUrl});
    } catch (_) {}
    return photoUrl;
  }

  // 17. Обновление профиля пользователя
  Future<Map<String, dynamic>> updateProfile({
    required String firstName,
    String? lastName,
    String? username,
    String? description,
    String? avatar,
    String? bannerUrl,
  }) async {
    final cleanUsername = username != null
        ? username.replaceFirst(RegExp(r'^@+'), '').trim().toLowerCase()
        : '';

    final payload = <String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': (lastName ?? '').trim(),
      'first_name': firstName.trim(),
      'last_name': (lastName ?? '').trim(),
      if (cleanUsername.isNotEmpty) 'username': cleanUsername,
      'description': (description ?? '').trim(),
      if (avatar != null && avatar.isNotEmpty) 'avatar': avatar.trim(),
      if (bannerUrl != null) 'bannerUrl': bannerUrl.trim(),
      if (bannerUrl != null) 'banner_url': bannerUrl.trim(),
    };

    final res = await _dio.post('/api/users/profile', data: payload);

    if (bannerUrl != null) {
      try {
        await _dio.post('/api/user/banner', data: {'banner_url': bannerUrl.trim()});
      } catch (e) {
        debugPrint('Banner update note: $e');
      }
    }

    if (res.data is Map<String, dynamic>) {
      return res.data as Map<String, dynamic>;
    }
    return {'success': true, 'data': payload};
  }
}

