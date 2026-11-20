import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/profile_color_theme.dart';
import '../../models/user.dart';
import '../../models/user_gift.dart';
import '../../providers/auth_provider.dart';
import '../../services/profile_cache_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';

class ProfileColorScreen extends StatefulWidget {
  const ProfileColorScreen({super.key});

  @override
  State<ProfileColorScreen> createState() => _ProfileColorScreenState();
}

class _ProfileColorScreenState extends State<ProfileColorScreen> {
  int _selectedTabIndex = 0; // 0: Профиль, 1: Имя
  late String _selectedThemeId;
  bool _isSaving = false;
  List<UserGift> _userGifts = [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    _selectedThemeId = (user?.profileColor != null && user!.profileColor!.isNotEmpty)
        ? user.profileColor!
        : 'default';

    if (user != null) {
      final cached = ProfileCacheService.getGifts(user.id);
      if (cached != null) {
        _userGifts = cached;
      }
    }
  }

  Future<void> _handleApply() async {
    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.updateProfileColor(_selectedThemeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Цвет профиля успешно обновлен',
              style: TextStyle(fontFamily: AppTheme.fontText, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF191919),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: const Color(0xFF191919),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _resetColor() {
    setState(() {
      _selectedThemeId = 'default';
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final currentTheme = ProfileColorTheme.fromId(_selectedThemeId);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // =================================================================
            // TOP BAR: Back button + Segmented Switcher [Профиль | Имя]
            // =================================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Segmented control [Профиль | Имя]
                  Container(
                    height: 34,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSegmentButton('Профиль', 0),
                        _buildSegmentButton('Имя', 1),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36), // Balance the back button
                ],
              ),
            ),

            // =================================================================
            // SCROLLABLE CONTENT
            // =================================================================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                children: [
                  // 1. LIVE PROFILE PREVIEW CARD (1:1 with Telegram)
                  _buildPreviewCard(user, currentTheme),
                  const SizedBox(height: 16),

                  // 2. PALETTE CONTAINER WITH 16 TELEGRAM CIRCLES
                  _buildPaletteCard(currentTheme),
                  const SizedBox(height: 12),

                  // 3. RESET BUTTON
                  GestureDetector(
                    onTap: _resetColor,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Сбросить цвет профиля',
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF3B98FF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 4. USE GIFT SECTION ("ИСПОЛЬЗОВАТЬ ПОДАРОК")
                  _buildGiftPresetsSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // =================================================================
            // BOTTOM BUTTON: "Применить стиль"
            // =================================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B98FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Применить стиль',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton(String title, int index) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTabIndex = index);
        if (index == 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Настройка цвета имени будет доступна в следующем обновлении'),
              duration: Duration(seconds: 1),
              backgroundColor: Color(0xFF191919),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2C2C2E) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(User? user, ProfileColorTheme theme) {
    final displayName = user?.fullName.isNotEmpty == true
        ? user!.fullName
        : (user?.username.isNotEmpty == true ? '@${user!.username}' : 'Пользователь');

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: theme.backgroundGradient,
          stops: theme.stops,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background subtle ambient glow
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.75,
                  colors: [
                    theme.ambientGlow,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Background subtle decorative pattern (Telegram style ripples)
          Positioned.fill(
            child: CustomPaint(
              painter: _TelegramPatternPainter(theme.ambientGlow.withOpacity(0.12)),
            ),
          ),

          // Avatar, Name, Status in Center
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with ambient border
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.ambientGlow.withOpacity(0.4),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: AvatarWidget(
                    avatarUrl: user?.avatar,
                    title: displayName,
                    size: 86,
                  ),
                ),
                const SizedBox(height: 12),

                // Name with optional badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user != null && user.isVerified) ...[
                      const SizedBox(width: 5),
                      VerificationBadge(
                        verification: user.effectiveVerification,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CD964),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Text(
                      'в сети',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteCard(ProfileColorTheme activeTheme) {
    final all = ProfileColorTheme.allPresets;
    final row1 = all.take(8).toList();
    final row2 = all.skip(8).take(8).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Solid base colors
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: row1.map((item) => _buildColorCircle(item)).toList(),
          ),
          const SizedBox(height: 14),

          // Row 2: Duo-tone gradients
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: row2.map((item) => _buildColorCircle(item)).toList(),
          ),
          const SizedBox(height: 16),

          const Divider(color: Color(0x14FFFFFF), height: 1),

          // Row: "Фоновый эмодзи"
          InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Кастомные фоновые эмодзи будут добавлены в следующем апдейте'),
                  duration: Duration(seconds: 1),
                  backgroundColor: Color(0xFF191919),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.layers_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Фоновый эмодзи',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.chevron_right_rounded, color: Color(0xFF8E8E93), size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),
          const Text(
            'Вы можете изменить цвет своего имени и оформление ответов на Ваши сообщения. Изменить >',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 12.5,
              color: Color(0xFF8E8E93),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorCircle(ProfileColorTheme theme) {
    final isSelected = _selectedThemeId == theme.id;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedThemeId = theme.id;
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white, width: 2.2)
              : Border.all(color: Colors.transparent, width: 2.2),
        ),
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.isDuoTone ? null : theme.previewColors.first,
            gradient: theme.isDuoTone
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.previewColors,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildGiftPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'ИСПОЛЬЗОВАТЬ ПОДАРОК',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E93),
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildGiftChip(
                icon: '🎁',
                label: 'Мои подарки',
                onTap: () {
                  if (_userGifts.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('У вас пока нет подарков для использования стиля'),
                        duration: Duration(seconds: 1),
                        backgroundColor: Color(0xFF191919),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 8),
              _buildGiftChip(
                icon: '🍦',
                label: 'Vice Cream',
                onTap: () => setState(() => _selectedThemeId = 'cyan'),
              ),
              const SizedBox(width: 8),
              _buildGiftChip(
                icon: '🗽',
                label: 'Chill Flame',
                onTap: () => setState(() => _selectedThemeId = 'duo_sunset'),
              ),
              const SizedBox(width: 8),
              _buildGiftChip(
                icon: '🧸',
                label: 'Plush Bear',
                onTap: () => setState(() => _selectedThemeId = 'caramel'),
              ),
              const SizedBox(width: 8),
              _buildGiftChip(
                icon: '🚗',
                label: 'Cyber Car',
                onTap: () => setState(() => _selectedThemeId = 'duo_violet'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGiftChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelegramPatternPainter extends CustomPainter {
  final Color color;

  _TelegramPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = 85.0;

    // Concentric subtle circular rings behind avatar
    for (double r = 48; r <= 140; r += 26) {
      canvas.drawCircle(Offset(centerX, centerY), r, paint);
    }

    // Subtle small accent dots
    final dotPaint = Paint()
      ..color = color.withOpacity(color.opacity * 1.5)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      final angle = (i * 45) * math.pi / 180;
      final x = centerX + 110 * math.cos(angle);
      final y = centerY + 110 * math.sin(angle);
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TelegramPatternPainter oldDelegate) => oldDelegate.color != color;
}

