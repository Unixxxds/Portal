import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../data/database_helper.dart';
import '../../../models/user.dart';
import '../../../models/user_gift.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/api_service.dart';
import '../../theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/badges.dart';
import '../../widgets/gift_detail_modal.dart';
import '../../widgets/gift_visuals.dart';
import '../chat_screen.dart';
import '../edit_profile_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<UserGift> _userGifts = [];
  bool _isLoadingGifts = false;
  int? _loadedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      auth.refreshCurrentUser();
      if (auth.currentUser != null) {
        _loadUserGifts(auth.currentUser!.id);
      }
    });
  }

  Future<void> _loadUserGifts(int userId) async {
    _loadedUserId = userId;

    // 1. Показываем локальный кэш
    try {
      final cached = await DatabaseHelper.instance.getUserGifts(userId);
      if (cached.isNotEmpty && mounted && _userGifts.isEmpty) {
        setState(() {
          _userGifts = cached;
        });
      }
    } catch (_) {}

    // 2. Всегда загружаем актуальный список с сервера (источник правды)
    try {
      if (_userGifts.isEmpty && mounted) {
        setState(() => _isLoadingGifts = true);
      }
      final apiGifts = await ApiService.instance.getUserGifts(userId);
      final currentUser = context.read<AuthProvider>().currentUser;
      final freshList = apiGifts.map((g) {
        final map = Map<String, dynamic>.from(g);
        if (currentUser != null) {
          map.putIfAbsent('recipient_id', () => currentUser.id);
          map.putIfAbsent('recipient_first_name', () => currentUser.firstName);
          map.putIfAbsent('recipient_last_name', () => currentUser.lastName);
          map.putIfAbsent('recipient_username', () => currentUser.username);
          map.putIfAbsent('recipient_avatar', () => currentUser.avatar);
        }
        return UserGift.fromJson(map, fallbackUserId: userId);
      }).toList();

      if (mounted) {
        setState(() {
          _userGifts = freshList;
          _isLoadingGifts = false;
        });
      }

      await DatabaseHelper.instance.saveUserGifts(userId, freshList);
    } catch (e) {
      debugPrint('Error loading user gifts in profile tab: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingGifts = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final user = auth.currentUser;

    if (user != null && _loadedUserId != user.id) {
      _loadedUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadUserGifts(user.id);
      });
    }

    if (user == null) {
      return const Scaffold(
        backgroundColor: AppTheme.appBg,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      );
    }

    final savedMessagesChat = chatProvider.chats.where((c) => c.isSaved).firstOrNull;

    final formattedBanner = AppConstants.formatMediaUrl(user.bannerUrl);

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: SafeArea(
        bottom: false,
        top: formattedBanner.isEmpty,
        child: RefreshIndicator(
          color: Colors.white,
          backgroundColor: const Color(0xFF191919),
          onRefresh: () async {
            await context.read<AuthProvider>().refreshCurrentUser();
            final cur = context.read<AuthProvider>().currentUser;
            if (cur != null) {
              await _loadUserGifts(cur.id);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
            if (formattedBanner.isNotEmpty) ...[
              // ===============================================================
              // HERO BANNER & AVATAR (Edge-to-edge with animated GIF/WebP support)
              // ===============================================================
              SizedBox(
                height: 240,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Banner Image spanning down
                    Positioned.fill(
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              formattedBanner,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF191919),
                              ),
                            ),
                            // Top subtle dark gradient for title readability
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 90,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0x99000000), Colors.transparent],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            // Bottom smooth gradient blur & fade into deep black #090909
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: 110,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Color(0x33090909),
                                      Color(0x80090909),
                                      Color(0xD9090909),
                                      Color(0xFF090909),
                                    ],
                                    stops: [0.0, 0.25, 0.55, 0.8, 1.0],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Top Bar over banner: "Профиль" title + "Изм." button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 18,
                      right: 16,
                      child: Row(
                        children: [
                          const Text(
                            'Профиль',
                            style: TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: Colors.white,
                              shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xCC191919),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0x33FFFFFF), width: 1.0),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, color: Colors.white, size: 15),
                                  SizedBox(width: 5),
                                  Text(
                                    'Изм.',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Avatar overlapping banner bottom
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                            );
                          },
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF090909), width: 4),
                                ),
                                child: AvatarWidget(
                                  avatarUrl: user.avatar,
                                  title: user.fullName.isNotEmpty ? user.fullName : user.username,
                                  size: 90,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.appBg, width: 2),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: Color(0xFF090909),
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              // ===============================================================
              // TOP BAR: "Профиль" + Кнопка "Изм." (Default without banner)
              // ===============================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 16, 16),
                child: Row(
                  children: [
                    const Text(
                      'Профиль',
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_outlined, color: Colors.white, size: 15),
                            SizedBox(width: 5),
                            Text(
                              'Изм.',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // PROFILE HEADER: Avatar
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                    );
                  },
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF191919), width: 3),
                        ),
                        child: AvatarWidget(
                          avatarUrl: user.avatar,
                          title: user.fullName.isNotEmpty ? user.fullName : user.username,
                          size: 92,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.appBg, width: 2),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF090909),
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // User Full Name + Verified + Username + Bio
            Center(
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // For user: verification badge (dev or user) to the LEFT
                      if (user.isVerified) ...[
                        VerificationBadge(verification: user.effectiveVerification, size: 22),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          user.fullName.isNotEmpty ? user.fullName : user.username,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      // For user: premium badge to the RIGHT
                      if (user.isPremium) ...[
                        const SizedBox(width: 6),
                        const PremiumBadge(size: 22),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.username.isNotEmpty ? '@${user.username}' : (user.email ?? ''),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 14.5,
                      color: Color(0xFF929292),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (user.description != null && user.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        user.description!.trim(),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 13.5,
                          color: Color(0xFF929292),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // =================================================================
            // SPARKS BALANCE CARD
            // =================================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF191919),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33F59E0B), width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1AF59E0B),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0x26F59E0B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_fire_department_rounded, color: AppTheme.sparksGold, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Баланс Sparks',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Color(0xFF929292),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${user.sparksBalance} Sparks',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Пополнение баланса доступно на web.portalmsg.ru'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF191919),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.sparksGold,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text(
                        'Купить',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // =================================================================
            // SECTION: ПОДАРКИ (3-Column Square Grid)
            // =================================================================
            if (_userGifts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'Подарки',
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF191919),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
                      ),
                      child: Text(
                        '${_userGifts.length}',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF929292),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_isLoadingGifts)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _userGifts.length,
                  itemBuilder: (context, index) {
                    final gift = _userGifts[index];
                    return _buildGiftCard(gift, user);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // =================================================================
            // QUICK ACTIONS GROUP (Graphite #191919)
            // =================================================================
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
              ),
              child: Column(
                children: [
                  // 1. Избранное
                  if (savedMessagesChat != null) ...[
                    ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 18),
                      ),
                      title: const Text(
                        'Избранное',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: const Text(
                        'Сохраненные сообщения',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Color(0xFF929292),
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF929292), size: 18),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ChatScreen(chat: savedMessagesChat)),
                        );
                      },
                    ),
                    const Divider(color: Color(0x14FFFFFF), thickness: 0.8, indent: 56, height: 1),
                  ],

                  // 2. Редактировать профиль (Имя, юзернейм, био, баннер)
                  ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF242424),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
                    ),
                    title: const Text(
                      'Редактировать профиль',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      user.username.isNotEmpty ? '@${user.username}' : 'Имя, юзернейм, описание',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Color(0xFF929292),
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF929292), size: 18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                      );
                    },
                  ),

                  // 3. Электронная почта
                  if (user.email != null && user.email!.isNotEmpty) ...[
                    const Divider(color: Color(0x14FFFFFF), thickness: 0.8, indent: 56, height: 1),
                    ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 18),
                      ),
                      title: const Text(
                        'Электронная почта',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        user.email!,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Color(0xFF929292),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // =================================================================
            // LOGOUT BUTTON
            // =================================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: () => _showLogoutDialog(context, auth),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191919),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x33EF4444), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: AppTheme.destructive, size: 19),
                      SizedBox(width: 8),
                      Text(
                        'Выйти из аккаунта',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: AppTheme.destructive,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildGiftCard(UserGift gift, User user) {
    final hasPattern = gift.isUpgraded && gift.patternName.isNotEmpty;
    final numText = (gift.nftNumber > 0 ? gift.nftNumber : gift.id).toString();
    final profileName = user.displayName.isNotEmpty ? user.displayName : user.username;
    final profileAvatar = user.avatar;

    return GestureDetector(
      onTap: () {
        GiftDetailModal.show(
          context,
          gift: gift,
          ownerName: profileName.isNotEmpty ? profileName : null,
          ownerAvatar: profileAvatar.isNotEmpty ? profileAvatar : null,
          onSenderTap: () {
            Navigator.pop(context);
          },
          onOwnerTap: () {
            Navigator.pop(context);
          },
          onGiftUpgraded: (upgraded) {
            setState(() {
              final idx = _userGifts.indexWhere((g) => g.id == upgraded.id);
              if (idx != -1) {
                _userGifts[idx] = upgraded;
              }
            });
          },
        );
      },
      child: Container(
        decoration: GiftVisuals.getBackdropDecoration(
          backdropName: gift.backdropName,
          backdropGradient: gift.backdropGradient,
          giftName: gift.giftName,
          giftId: gift.giftId,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pattern Overlay if upgraded
            if (hasPattern)
              Positioned.fill(
                child: CustomPaint(
                  painter: GiftPatternPainter(
                    patternName: gift.patternName,
                  ),
                ),
              ),

            // Subtle ambient bloom behind model
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: GiftVisuals.getAmbientGlowColor(
                      gift.backdropName,
                      gift.giftName,
                      gift.backdropGradient,
                    ).withOpacity(0.4),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),

            // 3D Gift Model
            GiftModelWidget(
              gift: gift,
              size: 68,
              animate: false,
            ),

            // Top-right ribbon badge with #number
            if (gift.nftNumber > 0 || gift.isUpgraded)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '#$numText',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Bottom-left sender avatar badge
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF090909), width: 1.5),
                  color: const Color(0xFF191919),
                ),
                child: ClipOval(
                  child: gift.senderAvatar.isNotEmpty
                      ? Image.network(
                          AppConstants.formatMediaUrl(gift.senderAvatar),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildCardSenderFallback(gift),
                        )
                      : _buildCardSenderFallback(gift),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSenderFallback(UserGift gift) {
    final letter = gift.senderDisplayName.isNotEmpty ? gift.senderDisplayName[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFF191919),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191919),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1.0),
        ),
        title: const Text(
          'Выход из аккаунта',
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Вы уверены, что хотите выйти из Portal на этом устройстве?',
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            color: Color(0xFF929292),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF929292))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: const Text('Выйти', style: TextStyle(color: AppTheme.destructive, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
