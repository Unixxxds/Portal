import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/account_session.dart';
import '../../../models/user.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/multi_account_service.dart';
import '../../theme.dart';
import '../../widgets/add_account_modal.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/badges.dart';
import '../data_and_storage_screen.dart';

class SettingsTab extends StatelessWidget {
  final VoidCallback onOpenProfile;

  const SettingsTab({super.key, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Top Bar
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                'Настройки',
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),

            // Profile Card (Tap to open Me Tab)
            if (user != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: onOpenProfile,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        AvatarWidget(
                          avatarUrl: user.avatar,
                          title: user.fullName.isNotEmpty ? user.fullName : user.username,
                          size: 58,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (user.isVerified) ...[
                                    VerificationBadge(
                                      verification: user.effectiveVerification,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Flexible(
                                    child: Text(
                                      user.fullName.isNotEmpty ? user.fullName : user.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (user.isPremium) ...[
                                    const SizedBox(width: 5),
                                    const PremiumBadge(size: 19),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                user.username.isNotEmpty ? '@${user.username}' : (user.email ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF48484A), size: 15),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // =================================================================
            // MULTI-ACCOUNT SWITCHER CARD (Telegram / iOS Style)
            // =================================================================
            if (user != null)
              _buildAccountSwitcherCard(context, auth, user),

            const SizedBox(height: 24),

            // Section 1: Security & Account
            _buildSectionHeader('БЕЗОПАСНОСТЬ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.lock_rounded,
                iconBg: const Color(0xFF007AFF), // iOS System Blue
                title: 'Облачный пароль (2FA)',
                subtitle: 'Двухэтапная аутентификация',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.devices_rounded,
                iconBg: const Color(0xFF34C759), // iOS System Green
                title: 'Устройства и сессии',
                subtitle: '1 активная сессия',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 24),

            // Section 2: General Preferences
            _buildSectionHeader('ОСНОВНЫЕ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.notifications_rounded,
                iconBg: const Color(0xFFFF3B30), // iOS System Red
                title: 'Уведомления и звуки',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.pie_chart_rounded,
                iconBg: const Color(0xFF34C759), // iOS System Green
                title: 'Данные и память',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DataAndStorageScreen(),
                    ),
                  );
                },
              ),
              _buildSettingTile(
                icon: Icons.palette_rounded,
                iconBg: const Color(0xFF5856D6), // iOS System Indigo/Purple
                title: 'Оформление',
                trailingText: 'Portal Midnight',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.language_rounded,
                iconBg: const Color(0xFF30B0C7), // iOS System Teal
                title: 'Язык',
                trailingText: 'Русский',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 24),

            // Section 3: About
            _buildSectionHeader('О ПРИЛОЖЕНИИ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.info_rounded,
                iconBg: const Color(0xFF8E8E93), // iOS System Grey
                title: 'Portal Mobile',
                trailingText: 'v1.0.0 (Build 1)',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.privacy_tip_rounded,
                iconBg: const Color(0xFF636366), // iOS System Dark Grey
                title: 'Конфиденциальность',
                onTap: () {},
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSwitcherCard(BuildContext context, AuthProvider auth, User user) {
    return ListenableBuilder(
      listenable: MultiAccountService.instance,
      builder: (context, _) {
        final accounts = MultiAccountService.instance.accounts;
        final activeId = auth.currentUser?.id ?? user.id;

        // Ensure current active user is always represented even if accounts list is initializing
        final List<AccountSession> displayAccounts = List.from(accounts);
        if (displayAccounts.isEmpty && user.id > 0) {
          displayAccounts.add(
            AccountSession(
              userId: user.id,
              token: '',
              user: user,
              lastActive: DateTime.now(),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
          ),
          child: Column(
            children: [
              // List of accounts
              ...List.generate(displayAccounts.length, (index) {
                final acc = displayAccounts[index];
                final isActive = (acc.userId == activeId);
                final displayName = acc.user.fullName.isNotEmpty ? acc.user.fullName : acc.user.username;

                return Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        if (!isActive) {
                          HapticFeedback.lightImpact();
                          await auth.switchAccount(acc, context);
                        }
                      },
                      onLongPress: () {
                        if (displayAccounts.length > 1) {
                          _showAccountOptions(context, auth, acc);
                        }
                      },
                      borderRadius: BorderRadius.vertical(
                        top: index == 0 ? const Radius.circular(26) : Radius.zero,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Avatar
                            AvatarWidget(
                              avatarUrl: acc.user.avatar,
                              title: displayName,
                              size: 46,
                            ),
                            const SizedBox(width: 14),

                            // Name & Username
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (acc.user.isVerified) ...[
                                        VerificationBadge(
                                          verification: acc.user.effectiveVerification,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            color: Colors.white,
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (acc.user.isPremium) ...[
                                        const SizedBox(width: 4),
                                        const PremiumBadge(size: 17),
                                      ],
                                    ],
                                  ),
                                  if (acc.user.username.isNotEmpty) ...[
                                    const SizedBox(height: 1.5),
                                    Text(
                                      '@${acc.user.username}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontText,
                                        color: Color(0xFF8E8E93),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Active checkmark OR unread badge
                            if (isActive)
                              const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF007AFF),
                                size: 22,
                              )
                            else if (acc.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  acc.unreadCount > 999
                                      ? '${(acc.unreadCount / 1000).toStringAsFixed(1)}K'
                                      : '${acc.unreadCount}',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(
                      color: Color(0x1AFFFFFF),
                      thickness: 0.5,
                      indent: 76,
                      height: 1,
                    ),
                  ],
                );
              }),

              // Bottom "+ Добавить аккаунт"
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  AddAccountModal.show(context);
                },
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_rounded,
                        color: Color(0xFF007AFF),
                        size: 24,
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Добавить аккаунт',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Color(0xFF007AFF),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAccountOptions(BuildContext context, AuthProvider auth, AccountSession session) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(session.user.fullName.isNotEmpty ? session.user.fullName : session.user.username),
        actions: [
          if (session.userId != auth.currentUser?.id)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                auth.switchAccount(session, context);
              },
              child: const Text('Переключиться на этот аккаунт'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await MultiAccountService.instance.removeAccount(session.userId);
            },
            child: const Text('Удалить аккаунт из списка'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontDisplay,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupedCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                const Divider(
                  color: Color(0x1AFFFFFF),
                  thickness: 0.5,
                  indent: 58,
                  height: 1,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    String? subtitle,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            // iOS authentic rounded square icon
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: Colors.white, size: 17.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Color(0xFF8E8E93),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  color: Color(0xFF8E8E93),
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF48484A), size: 14),
          ],
        ),
      ),
    );
  }
}
