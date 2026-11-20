import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/profile_color_theme.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';

class ProfileColorScreen extends StatefulWidget {
  const ProfileColorScreen({super.key});

  @override
  State<ProfileColorScreen> createState() => _ProfileColorScreenState();
}

class _ProfileColorScreenState extends State<ProfileColorScreen> {
  late String _selectedThemeId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    _selectedThemeId = (user?.profileColor != null && user!.profileColor!.isNotEmpty)
        ? user.profileColor!
        : 'default';
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
            // TOP BAR: Back button + Title "Профиль"
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Профиль',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // =================================================================
            // BOTTOM BUTTON: "Применить" (белая и максимально скругленная)
            // =================================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white.withOpacity(0.6),
                    elevation: 0,
                    shape: const StadiumBorder(),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Применить',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
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
    const all = ProfileColorTheme.allPresets;
    final row1 = all.take(8).toList();
    final row2 = all.skip(8).take(8).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
    const centerY = 85.0;

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

