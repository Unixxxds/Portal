import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../theme.dart';
import '../widgets/liquid_glass_tab_bar.dart';
import 'tabs/chats_tab.dart';
import 'tabs/contacts_tab.dart';
import 'tabs/calls_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/profile_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _activeTabIndex = 2; // Default to Chats tab (index 2)
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _activeTabIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      final authProvider = context.read<AuthProvider>();
      chatProvider.init();
      chatProvider.syncBootstrap(onUserLoaded: (user) {
        authProvider.setCurrentUser(user);
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (_activeTabIndex != index) {
      setState(() => _activeTabIndex = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final totalUnread = chatProvider.chats.fold<int>(0, (acc, c) => acc + c.unreadCount);

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: Stack(
        children: [
          // 5 Tab Panes with PageView
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(), // tab navigation via bottom bar
            children: [
              const ContactsTab(),
              const CallsTab(),
              ChatsTab(onOpenProfile: () => _onTabSelected(4)),
              SettingsTab(onOpenProfile: () => _onTabSelected(4)),
              const ProfileTab(),
            ],
          ),

          // Floating Apple iOS Liquid Glass Tab Bar at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: LiquidGlassTabBar(
                selectedIndex: _activeTabIndex,
                onTabSelected: _onTabSelected,
                totalUnreadCount: totalUnread,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

