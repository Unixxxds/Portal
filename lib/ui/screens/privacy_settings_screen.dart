import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../theme.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  void _showSelectionModal({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String currentValue, // 'all' or 'nobody'
    required String description,
    required Function(String) onSelected,
  }) {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            String selected = currentValue;

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).padding.bottom + 16,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF48484A),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Modal Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Option 1: Все
                  _buildRadioOption(
                    title: 'Все',
                    isSelected: selected == 'all',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setModalState(() => selected = 'all');
                      onSelected('all');
                      Navigator.of(modalCtx).pop();
                    },
                  ),

                  // Divider
                  Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20),
                    child: Container(
                      height: 0.5,
                      color: const Color(0x1FFFFFFF),
                    ),
                  ),

                  // Option 2: Никто
                  _buildRadioOption(
                    title: 'Никто',
                    isSelected: selected == 'nobody',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setModalState(() => selected = 'nobody');
                      onSelected('nobody');
                      Navigator.of(modalCtx).pop();
                    },
                  ),

                  const SizedBox(height: 14),

                  // Footer explanatory text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      description,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildRadioOption({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: Color(0xFF0A84FF), // iOS system blue
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    final privacyLastSeen = user?.privacyLastSeen ?? 'all';
    final privacySparks = user?.privacySparks ?? 'all';
    final privacyAvatar = user?.privacyAvatar ?? 'all';

    final lastSeenDisplay = privacyLastSeen == 'nobody' ? 'Никто' : 'Все';
    final sparksDisplay = privacySparks == 'nobody' ? 'Никто' : 'Все';
    final avatarDisplay = privacyAvatar == 'nobody' ? 'Никто' : 'Все';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Конфиденциальность',
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section Title
          const Padding(
            padding: EdgeInsets.only(left: 14, bottom: 8, top: 4),
            child: Text(
              'КТО ВИДИТ МОИ ДАННЫЕ',
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.3,
              ),
            ),
          ),

          // Grouped Card
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
            ),
            child: Column(
              children: [
                // 1. Активность
                _buildSettingTile(
                  icon: Icons.access_time_rounded,
                  iconBg: const Color(0xFF007AFF),
                  title: 'Активность',
                  trailingText: lastSeenDisplay,
                  onTap: () {
                    _showSelectionModal(
                      context: context,
                      title: 'Кто видит, когда я в сети',
                      subtitle: 'Время захода и онлайн',
                      currentValue: privacyLastSeen,
                      description:
                          'Если вы выберете «Никто», другие пользователи будут видеть надпись «Был(а) недавно» вместо точного времени вашего онлайна.',
                      onSelected: (val) {
                        auth.updatePrivacy(privacyLastSeen: val);
                      },
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.only(left: 58),
                  child: Divider(color: Color(0x1FFFFFFF), height: 1),
                ),

                // 2. Баланс Sparks
                _buildSettingTile(
                  icon: Icons.auto_awesome_rounded,
                  iconBg: const Color(0xFFFF9500),
                  title: 'Баланс Sparks',
                  trailingText: sparksDisplay,
                  onTap: () {
                    _showSelectionModal(
                      context: context,
                      title: 'Кто видит баланс Sparks',
                      subtitle: 'Отображение в профиле',
                      currentValue: privacySparks,
                      description:
                          'Если вы выберете «Никто», плашка с балансом Sparks в вашем профиле будет скрыта для всех пользователей, кроме вас.',
                      onSelected: (val) {
                        auth.updatePrivacy(privacySparks: val);
                      },
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.only(left: 58),
                  child: Divider(color: Color(0x1FFFFFFF), height: 1),
                ),

                // 3. Аватарка
                _buildSettingTile(
                  icon: Icons.account_circle_rounded,
                  iconBg: const Color(0xFF34C759),
                  title: 'Аватарка',
                  trailingText: avatarDisplay,
                  onTap: () {
                    _showSelectionModal(
                      context: context,
                      title: 'Кто видит мою аватарку',
                      subtitle: 'Фотография профиля',
                      currentValue: privacyAvatar,
                      description:
                          'Если вы выберете «Никто», ваше фото профиля не будет видно никому — другие пользователи увидят стандартный значок с инициалами. Вы по-прежнему будете видеть свою аватарку.',
                      onSelected: (val) {
                        auth.updatePrivacy(privacyAvatar: val);
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Управляйте видимостью вашей активности, баланса Sparks и фотографии профиля в Portal.',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13,
                color: Color(0xFF8E8E93),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String trailingText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Text(
              trailingText,
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                color: Color(0xFF0A84FF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF48484A), size: 14),
          ],
        ),
      ),
    );
  }
}

