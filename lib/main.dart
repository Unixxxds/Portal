import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'services/media_cache_service.dart';
import 'services/push_notification_service.dart';
import 'ui/theme.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/main_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background pre-warming of gift assets & disk cache
  MediaCacheService.instance.precacheGifts();

  // Initialize push notification system
  await PushNotificationService.instance.init(navKey: rootNavigatorKey);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuth()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const PortalApp(),
    ),
  );
}

class PortalApp extends StatelessWidget {
  const PortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _askedPermission = false;

  void _checkAndRequestPush() {
    if (!_askedPermission) {
      _askedPermission = true;
      PushNotificationService.instance.requestPermissionAndRegister();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.checking:
      case AuthStatus.initial:
        return Scaffold(
          backgroundColor: AppTheme.appBg,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/portal-logo.png',
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.flash_on_rounded,
                    size: 56,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: AppTheme.accentBlue,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
          ),
        );

      case AuthStatus.authenticated:
        // As requested: prompt user for push notifications as soon as they enter the app!
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndRequestPush());
        return const MainScreen();

      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
