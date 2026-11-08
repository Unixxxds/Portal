import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
import '../data/secure_storage_service.dart';

class WebSocketService {
  static final WebSocketService instance = WebSocketService._init();
  WebSocketService._init();

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isDisposed = false;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;
    final token = await SecureStorageService.instance.getToken();
    if (token == null || token.isEmpty) return;

    try {
      final uri = Uri.parse('${AppConstants.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);
      
      _isConnected = true;
      _startPing();

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map<String, dynamic>) {
              if (decoded['type'] == 'pong') {
                // Heartbeat received
                return;
              }
              _eventController.add(decoded);
            }
          } catch (e) {
            debugPrint('WS decode error: $e');
          }
        },
        onError: (error) {
          debugPrint('WS error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WS closed');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WS connection failed: $e');
      _handleDisconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _channel = null;

    if (!_isDisposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 4), () {
        connect();
      });
    }
  }

  void sendTyping(int chatId, {bool isTyping = true}) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'user_typing',
          'chatId': chatId,
          'chat_id': chatId,
          'isTyping': isTyping,
          'is_typing': isTyping,
        }));
        _channel!.sink.add(jsonEncode({
          'type': 'typing',
          'chat_id': chatId,
          'chatId': chatId,
          'is_typing': isTyping,
        }));
      } catch (_) {}
    }
  }

  void sendPresence({required bool isOnline}) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'user_status',
          'is_online': isOnline,
          'status': isOnline ? 'online' : 'offline',
        }));
      } catch (_) {}
    }
  }

  void deleteMessage(int chatId, int messageId) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'delete_message',
          'chatId': chatId,
          'messageId': messageId,
        }));
      } catch (_) {}
    }
  }

  void editMessage(int messageId, String text) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'edit_message',
          'messageId': messageId,
          'text': text.trim(),
        }));
      } catch (_) {}
    }
  }

  void pinMessage(int chatId, int? messageId) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'pin_message',
          'chatId': chatId,
          'messageId': messageId,
        }));
      } catch (_) {}
    }
  }

  void send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (_) {}
    }
  }

  void deleteChat(int chatId) {
    send({
      'type': 'delete_chat',
      'chatId': chatId,
      'chat_id': chatId,
    });
  }

  void disconnect() {
    _isDisposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}

