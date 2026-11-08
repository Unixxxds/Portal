import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar_widget.dart';

class SettingsTab extends StatelessWidget {
  final VoidCallback onOpenProfile;

  const SettingsTab({super.key, required this.onOpenProfile});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Top Bar
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Настройки',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),

            // Profile Card (Tap to open Me Tab)
            if (user != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: onOpenProfile,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderHairline, width: 0.8),
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
                              Text(
                                user.fullName.isNotEmpty ? user.fullName : user.username,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.username.isNotEmpty ? '@${user.username}' : (user.email ?? ''),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.local_fire_department_rounded, color: AppTheme.sparksGold, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${user.sparksBalance} Sparks',
                                    style: const TextStyle(
                                      color: AppTheme.sparksGold,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textTertiary, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // Section 1: Security & Account
            _buildSectionHeader('БЕЗОПАСНОСТЬ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.shield_outlined,
                iconColor: const Color(0xFF3B98FF),
                title: 'Облачный пароль (2FA)',
                subtitle: 'Двухэтапная аутентификация',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.devices_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Устройства и сессии',
                subtitle: '1 активная сессия',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 20),

            // Section 2: General Preferences
            _buildSectionHeader('ОСНОВНЫЕ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.notifications_none_rounded,
                iconColor: const Color(0xFFEF4444),
                title: 'Уведомления и звуки',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.pie_chart_outline_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Данные и память',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.palette_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Оформление',
                trailingText: 'Portal Midnight',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF06B6D4),
                title: 'Язык',
                trailingText: 'Русский',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 20),

            // Section 3: About
            _buildSectionHeader('О ПРИЛОЖЕНИИ'),
            _buildGroupedCard([
              _buildSettingTile(
                icon: Icons.info_outline_rounded,
                iconColor: AppTheme.textSecondary,
                title: 'Portal Mobile',
                trailingText: 'v1.0.0 (Build 1)',
                onTap: () {},
              ),
              _buildSettingTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: AppTheme.textSecondary,
                title: 'Конфиденциальность',
                onTap: () {},
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupedCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderHairline, width: 0.8),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                const Divider(
                  color: AppTheme.borderHairline,
                  thickness: 0.5,
                  indent: 52,
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
    required Color iconColor,
    required String title,
    String? subtitle,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
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
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textTertiary, size: 14),
          ],
        ),
      ),
    );
  }
}

