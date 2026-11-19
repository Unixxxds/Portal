import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/database_helper.dart';
import '../ui/screens/chat_screen.dart';
import '../ui/widgets/telegram_chat_route.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FCM Background message: ${message.messageId} - ${message.notification?.title}');
}

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._internal();
  PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  String? _fcmToken;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'portal_high_importance_channel',
    'Сообщения и каналы',
    description: 'Уведомления о новых сообщениях от пользователей и каналов Portal',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  GlobalKey<NavigatorState>? navigatorKey;

  Future<void> init({GlobalKey<NavigatorState>? navKey}) async {
    if (_isInitialized) return;
    navigatorKey = navKey;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Local notifications setup for Heads-up alerts
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final data = jsonDecode(response.payload!) as Map<String, dynamic>;
              _handleNotificationClick(data);
            } catch (e) {
              debugPrint('Notification payload decode error: $e');
            }
          }
        },
      );

      // Create notification channel on Android
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_channel);
      }

      // Do NOT show system notifications while the user is actively in the app
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      // Foreground message listener: silent handling while user is actively in the app
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM message received in foreground (suppressed because user is active in app)');
      });

      // App opened from background by clicking notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp: ${message.data}');
        _handleNotificationClick(message.data);
      });

      // Check if launched from a terminated state notification
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM launched from initialMessage: ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationClick(initialMessage.data);
        });
      }

      // Token refresh listener
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        ApiService.instance.registerFcmToken(newToken);
      });

      _isInitialized = true;
      debugPrint('PushNotificationService successfully initialized with Firebase');
    } catch (e) {
      debugPrint('PushNotificationService init note (Firebase config pending): $e');
    }
  }

  /// Запрос разрешения на уведомления сразу при входе юзера в приложение
  Future<bool> requestPermissionAndRegister() async {
    try {
      // 1. Android 13+ (POST_NOTIFICATIONS) and iOS Permission
      final permStatus = await Permission.notification.request();
      
      // 2. Firebase Messaging permission
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final isAuthorized = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional ||
          permStatus.isGranted;

      if (isAuthorized) {
        debugPrint('Notification permission GRANTED');
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _fcmToken = token;
          debugPrint('FCM Device Token: $token');
          await ApiService.instance.registerFcmToken(token);
        }
        return true;
      } else {
        debugPrint('Notification permission DENIED or NOT_DETERMINED');
        return false;
      }
    } catch (e) {
      debugPrint('requestPermissionAndRegister error: $e');
      return false;
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'Portal';
    final body = notification?.body ?? message.data['body'] ?? 'Новое сообщение';

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _localNotifications.show(
      notificationId,
      title,
      body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleNotificationClick(Map<String, dynamic> data) async {
    final rawChatId = data['chatId'] ?? data['chat_id'];
    if (rawChatId == null) return;

    final chatId = int.tryParse(rawChatId.toString());
    if (chatId == null || chatId <= 0) return;

    debugPrint('Navigating to chat from push notification: chatId=$chatId');

    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    try {
      final chat = await DatabaseHelper.instance.getChat(chatId);
      if (chat != null && nav.mounted) {
        nav.push(
          TelegramChatRoute(
            builder: (_) => ChatScreen(chat: chat),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to chat from push notification: $e');
    }
  }

  Future<void> unregister() async {
    try {
      if (_fcmToken != null) {
        await ApiService.instance.deleteFcmToken(_fcmToken!);
      }
      await FirebaseMessaging.instance.deleteToken();
      _fcmToken = null;
    } catch (e) {
      debugPrint('FCM unregister error: $e');
    }
  }
}
