import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class NotificationsAndSoundsScreen extends StatefulWidget {
  const NotificationsAndSoundsScreen({super.key});

  @override
  State<NotificationsAndSoundsScreen> createState() => _NotificationsAndSoundsScreenState();
}

class _NotificationsAndSoundsScreenState extends State<NotificationsAndSoundsScreen> {
  bool _isLoading = true;

  // Messages
  bool _privateChats = true;
  bool _channels = true;
  bool _showPreview = true;

  // Sounds & Vibration
  bool _messageSound = true;
  bool _vibration = true;
  bool _inAppSounds = true;
  bool _sentSound = true;

  // Events
  bool _giftNotifications = true;
  bool _reactionNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _privateChats = prefs.getBool('portal_notif_private_chats') ?? true;
        _channels = prefs.getBool('portal_notif_channels') ?? true;
        _showPreview = prefs.getBool('portal_notif_preview') ?? true;
        _messageSound = prefs.getBool('portal_notif_sounds') ?? true;
        _vibration = prefs.getBool('portal_notif_vibration') ?? true;
        _inAppSounds = prefs.getBool('portal_notif_in_app') ?? true;
        _sentSound = prefs.getBool('portal_notif_sent_sound') ?? true;
        _giftNotifications = prefs.getBool('portal_notif_gifts') ?? true;
        _reactionNotifications = prefs.getBool('portal_notif_reactions') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSetting(String key, bool val) async {
    HapticFeedback.selectionClick();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Сбросить настройки?'),
        content: const Text('Все параметры уведомлений и звуков вернутся к значениям по умолчанию.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('portal_notif_private_chats');
      await prefs.remove('portal_notif_channels');
      await prefs.remove('portal_notif_preview');
      await prefs.remove('portal_notif_sounds');
      await prefs.remove('portal_notif_vibration');
      await prefs.remove('portal_notif_in_app');
      await prefs.remove('portal_notif_sent_sound');
      await prefs.remove('portal_notif_gifts');
      await prefs.remove('portal_notif_reactions');

      setState(() {
        _privateChats = true;
        _channels = true;
        _showPreview = true;
        _messageSound = true;
        _vibration = true;
        _inAppSounds = true;
        _sentSound = true;
        _giftNotifications = true;
        _reactionNotifications = true;
      });

      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Настройки уведомлений сброшены'),
            duration: Duration(milliseconds: 1500),
            backgroundColor: Color(0xFF1E222D),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Уведомления и звуки',
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(radius: 14, color: Colors.white70),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
              children: [
                // 1. СООБЩЕНИЯ
                _buildSectionHeader('УВЕДОМЛЕНИЯ О СООБЩЕНИЯХ'),
                _buildGroupedCard([
                  _buildSwitchTile(
                    icon: Icons.person_rounded,
                    iconBg: const Color(0xFF007AFF),
                    title: 'Личные чаты',
                    subtitle: 'Оповещения от собеседников',
                    value: _privateChats,
                    onChanged: (val) {
                      setState(() => _privateChats = val);
                      _updateSetting('portal_notif_private_chats', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.campaign_rounded,
                    iconBg: const Color(0xFFFF9500),
                    title: 'Группы и каналы',
                    subtitle: 'Оповещения о новых постах',
                    value: _channels,
                    onChanged: (val) {
                      setState(() => _channels = val);
                      _updateSetting('portal_notif_channels', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.visibility_rounded,
                    iconBg: const Color(0xFF34C759),
                    title: 'Показывать текст',
                    subtitle: 'Отображать текст в уведомлениях',
                    value: _showPreview,
                    onChanged: (val) {
                      setState(() => _showPreview = val);
                      _updateSetting('portal_notif_preview', val);
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // 2. ЗВУКИ И ВИБРАЦИЯ
                _buildSectionHeader('ЗВУКИ И ВИБРАЦИЯ'),
                _buildGroupedCard([
                  _buildSwitchTile(
                    icon: Icons.volume_up_rounded,
                    iconBg: const Color(0xFFFF2D55),
                    title: 'Звук сообщений',
                    subtitle: 'Воспроизводить сигнал при входящих',
                    value: _messageSound,
                    onChanged: (val) {
                      setState(() => _messageSound = val);
                      _updateSetting('portal_notif_sounds', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.vibration_rounded,
                    iconBg: const Color(0xFF5856D6),
                    title: 'Вибрация',
                    subtitle: 'Тактильный отклик при оповещениях',
                    value: _vibration,
                    onChanged: (val) {
                      setState(() => _vibration = val);
                      _updateSetting('portal_notif_vibration', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.music_note_rounded,
                    iconBg: const Color(0xFF30B0C7),
                    title: 'Звуки в приложении',
                    subtitle: 'Звуки при открытии и действиях',
                    value: _inAppSounds,
                    onChanged: (val) {
                      setState(() => _inAppSounds = val);
                      _updateSetting('portal_notif_in_app', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.send_rounded,
                    iconBg: const Color(0xFF007AFF),
                    title: 'Звук отправки сообщения',
                    subtitle: 'Короткий сигнал при отправке',
                    value: _sentSound,
                    onChanged: (val) {
                      setState(() => _sentSound = val);
                      _updateSetting('portal_notif_sent_sound', val);
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // 3. СОБЫТИЯ
                _buildSectionHeader('СОБЫТИЯ'),
                _buildGroupedCard([
                  _buildSwitchTile(
                    icon: Icons.card_giftcard_rounded,
                    iconBg: const Color(0xFFAF52DE),
                    title: 'Получение подарков',
                    subtitle: 'Когда кто-то дарит вам подарок',
                    value: _giftNotifications,
                    onChanged: (val) {
                      setState(() => _giftNotifications = val);
                      _updateSetting('portal_notif_gifts', val);
                    },
                  ),
                  _buildSwitchTile(
                    icon: Icons.favorite_rounded,
                    iconBg: const Color(0xFFFF3B30),
                    title: 'Реакции',
                    subtitle: 'Оповещения о реакциях на сообщения',
                    value: _reactionNotifications,
                    onChanged: (val) {
                      setState(() => _reactionNotifications = val);
                      _updateSetting('portal_notif_reactions', val);
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // 4. СБРОС НАСТРОЕК
                _buildGroupedCard([
                  InkWell(
                    onTap: _resetToDefaults,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.restore_rounded, color: Color(0xFFFF3B30), size: 22),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Сбросить настройки уведомлений',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFFF3B30),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontDisplay,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildGroupedCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                color: Color(0x1AFFFFFF),
                height: 1,
                indent: 52,
                endIndent: 0,
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 12.5,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: const Color(0xFF34C759),
            trackColor: const Color(0xFF39393D),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

