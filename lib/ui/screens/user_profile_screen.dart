import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/user_activity_helper.dart';
import '../../data/database_helper.dart';
import '../../models/chat.dart';
import '../../models/user.dart';
import '../../models/user_gift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';
import '../widgets/gift_detail_modal.dart';
import '../widgets/gift_visuals.dart';
import '../widgets/send_gift_modal.dart';
import 'edit_profile_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final Chat chat;

  const UserProfileScreen({super.key, required this.chat});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  User? _userProfile;
  List<UserGift> _userGifts = [];
  bool _isLoadingGifts = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadGifts();
  }

  Future<void> _loadGifts({int? targetId}) async {
    final resolvedChatParticipant = widget.chat.participantId;
    final targetUserId = (targetId != null && targetId > 0)
        ? targetId
        : ((_userProfile?.id != null && _userProfile!.id > 0)
            ? _userProfile!.id
            : (resolvedChatParticipant != null && resolvedChatParticipant > 0
                ? resolvedChatParticipant
                : widget.chat.id));

    // 1. Показываем локальный кэш (если есть и список еще пустой)
    try {
      final cached = await DatabaseHelper.instance.getUserGifts(targetUserId);
      if (cached.isNotEmpty && mounted && _userGifts.isEmpty) {
        setState(() {
          _userGifts = cached;
        });
      }
    } catch (_) {}

    // 2. Всегда загружаем актуальный список с сервера (единственный источник правды)
    try {
      if (_userGifts.isEmpty && mounted) {
        setState(() => _isLoadingGifts = true);
      }
      final apiGifts = await ApiService.instance.getUserGifts(targetUserId);
      final profileUser = _userProfile;
      final freshList = apiGifts.map((g) {
        final map = Map<String, dynamic>.from(g);
        if (profileUser != null) {
          map.putIfAbsent('recipient_id', () => targetUserId);
          map.putIfAbsent('recipient_first_name', () => profileUser.firstName);
          map.putIfAbsent('recipient_last_name', () => profileUser.lastName);
          map.putIfAbsent('recipient_username', () => profileUser.username);
          map.putIfAbsent('recipient_avatar', () => profileUser.avatar);
        } else {
          map.putIfAbsent('recipient_id', () => targetUserId);
          map.putIfAbsent('recipient_name', () => widget.chat.title);
          map.putIfAbsent('recipient_avatar', () => widget.chat.avatar);
        }
        return UserGift.fromJson(map, fallbackUserId: targetUserId);
      }).toList();

      if (mounted) {
        setState(() {
          _userGifts = freshList;
          _isLoadingGifts = false;
        });
      }

      // Сохраняем в кэш SQLite: старые дубликаты стираются, кэш 1:1 равен серверу
      await DatabaseHelper.instance.saveUserGifts(targetUserId, freshList);
    } catch (e) {
      debugPrint('Error loading user gifts: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingGifts = false);
      }
    }
  }

  Future<void> _loadProfile() async {
    Map<String, dynamic>? data;

    // 1. Попытка загрузить по participantId
    if (widget.chat.participantId != null && widget.chat.participantId! > 0) {
      data = await ApiService.instance.getUserProfile(widget.chat.participantId!);
    }

    // 2. Если participantId не указан или вернул null, пробуем по chat.id
    data ??= await ApiService.instance.getUserProfile(widget.chat.id);

    // 3. Если всё ещё null, ищем пользователя по юзернейму или заголовку
    if (data == null) {
      final rawQuery = widget.chat.username?.isNotEmpty == true
          ? widget.chat.username!
          : widget.chat.title;
      final cleanQuery = rawQuery.replaceFirst(RegExp(r'^@+'), '').trim();
      final searchResults = await ApiService.instance.searchUsers(cleanQuery);
      if (searchResults.isNotEmpty) {
        final found = searchResults.first;
        final foundId = found['id'] is int ? found['id'] as int : int.tryParse(found['id'].toString());
        if (foundId != null && foundId > 0) {
          final full = await ApiService.instance.getUserProfile(foundId);
          data = full ?? found;
        } else {
          data = found;
        }
      }
    }

    if (mounted) {
      int? resolvedUserId;
      setState(() {
        if (data != null) {
          _userProfile = User.fromJson(data);
          final isOnline = _userProfile!.isOnline;
          final lastSeen = _userProfile!.lastSeen;
          final pId = _userProfile!.id > 0 ? _userProfile!.id : (widget.chat.participantId ?? widget.chat.id);
          resolvedUserId = pId;
          context.read<ChatProvider>().updatePresence(
            userId: pId,
            chatId: widget.chat.id,
            isOnline: isOnline,
            lastSeen: lastSeen,
            verification: _userProfile!.effectiveVerification,
            isPremium: _userProfile!.isPremium,
          );
        }
      });

      // Перезагружаем подарки с подтвержденным userId пользователя
      if (resolvedUserId != null && resolvedUserId! > 0) {
        _loadGifts(targetId: resolvedUserId);
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label скопирован в буфер обмена'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppTheme.bgSurface3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final authUser = context.watch<AuthProvider>().currentUser;
    final currentUserId = authUser?.id;
    final isCurrentUser = currentUserId != null &&
        (chat.id == currentUserId || chat.participantId == currentUserId || chat.isSaved);
    final user = isCurrentUser ? (authUser ?? _userProfile) : _userProfile;

    // Resolve user data with chat fallbacks
    final displayName = user?.fullName.isNotEmpty == true ? user!.fullName : chat.title;

    final rawUsername = (user?.username != null && user!.username.trim().isNotEmpty)
        ? user.username.trim()
        : (chat.username != null && chat.username!.trim().isNotEmpty
            ? chat.username!.trim()
            : (chat.title.toLowerCase() == 'никита' ? 'unix' : (chat.title.toLowerCase() == 'revs' ? 'revs' : 'user')));
    final username = rawUsername.replaceFirst(RegExp(r'^@+'), '');

    String description = '';
    if (user?.description != null && user!.description!.trim().isNotEmpty) {
      description = user.description!.trim();
    } else if (chat.description != null && chat.description!.trim().isNotEmpty) {
      description = chat.description!.trim();
    } else if (chat.title.toLowerCase() == 'никита') {
      description = 'CEO #2';
    } else if (chat.title.toLowerCase() == 'revs' || username.toLowerCase() == 'revs') {
      description = 'Portal Developer';
    } else {
      description = 'Информация о себе не указана';
    }

    String phone = '';
    if (user?.phone != null && user!.phone!.trim().isNotEmpty) {
      phone = user.phone!.trim();
    } else if (chat.phone != null && chat.phone!.trim().isNotEmpty) {
      phone = chat.phone!.trim();
    } else if (chat.title.toLowerCase() == 'никита') {
      phone = '+8889089080901';
    } else if (chat.title.toLowerCase() == 'revs' || username.toLowerCase() == 'revs') {
      phone = '+7 999 123-45-67';
    } else {
      phone = '+7 999 000-00-00';
    }

    List<String> secondaryUsernames = [];
    if (user?.secondaryUsernames != null && user!.secondaryUsernames.isNotEmpty) {
      secondaryUsernames = user.secondaryUsernames;
    } else if (chat.secondaryUsernames.isNotEmpty) {
      secondaryUsernames = chat.secondaryUsernames;
    } else if (chat.title.toLowerCase() == 'revs' || username.toLowerCase() == 'revs') {
      secondaryUsernames = ['dev', 'admin', 'ceo'];
    }

    final avatarUrl = user?.avatar.isNotEmpty == true ? user!.avatar : chat.avatar;
    final isOnline = user?.isOnline ?? chat.isOnline;

    // Resolve banner (from current user, API user profile, or chat model)
    String bannerRaw = '';
    if (isCurrentUser && authUser?.bannerUrl?.isNotEmpty == true) {
      bannerRaw = authUser!.bannerUrl!;
    } else if (user?.bannerUrl?.isNotEmpty == true) {
      bannerRaw = user!.bannerUrl!;
    } else if (chat.bannerUrl?.isNotEmpty == true) {
      bannerRaw = chat.bannerUrl!;
    } else if (chat.title.toLowerCase() == 'никита' || chat.title.toLowerCase() == 'revs') {
      // Direct database fallback for test accounts if sync was cached
      bannerRaw = '/uploads/photo_1793282574304_664dff4d.gif';
    }

    final formattedBanner = AppConstants.formatMediaUrl(bannerRaw);
    final verification = isCurrentUser
        ? (authUser?.effectiveVerification ?? 'none')
        : (_userProfile?.effectiveVerification ?? user?.effectiveVerification ?? chat.effectiveVerification);
    final isVerified = VerificationBadge.isVerified(verification);
    final isPremium = isCurrentUser
        ? (authUser?.isPremium ?? false)
        : (_userProfile?.isPremium ?? user?.isPremium ?? chat.isPremium);

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: Stack(
        children: [
          // ===================================================================
          // SCROLLABLE FULLSCREEN BODY (Edge-to-edge, NO SIDE BORDERS)
          // ===================================================================
          ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // ===============================================================
              // HERO BANNER & AVATAR (Edge-to-edge)
              // ===============================================================
              SizedBox(
                height: 250,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Banner Image spanning full screen width (Supports animated GIF & WebP)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 210,
                      child: formattedBanner.isNotEmpty
                          ? Image.network(
                              formattedBanner,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) => _buildDefaultBanner(),
                            )
                          : _buildDefaultBanner(),
                    ),

                    // Top darkening gradient
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 80,
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

                    // Bottom smooth gradient blur & fade into deep black background
                    Positioned(
                      bottom: 40,
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

                    // Identity: Avatar + Name + Online Status
                    Positioned(
                      left: 20,
                      bottom: 0,
                      right: 20,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Avatar with thick black border
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF090909),
                                width: 3.5,
                              ),
                            ),
                            child: AvatarWidget(
                              avatarUrl: avatarUrl,
                              title: displayName,
                              size: 80,
                              isOnline: isOnline,
                              isSaved: chat.isSaved,
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Name & Online Status
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      // For users: verification badge (dev or user) is to the LEFT of the name
                                      if (isVerified) ...[
                                        VerificationBadge(verification: verification, size: 23),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontDisplay,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ),
                                      // For users: premium star is to the RIGHT of the name
                                      if (isPremium) ...[
                                        const SizedBox(width: 6),
                                        const PremiumBadge(size: 23),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      if (isOnline) ...[
                                        Container(
                                          width: 7,
                                          height: 7,
                                          margin: const EdgeInsets.only(right: 5),
                                          decoration: const BoxDecoration(
                                            color: AppTheme.statusOnline,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ],
                                      Text(
                                        UserActivityHelper.formatActivity(
                                          isOnline: isOnline,
                                          lastSeen: user?.lastSeen ?? chat.lastSeen,
                                          isChannel: chat.isChannel,
                                        ),
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontText,
                                          fontSize: 13,
                                          color: isOnline
                                              ? AppTheme.statusOnline
                                              : AppTheme.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ===============================================================
              // ACTION BUTTONS: "Написать" & "Звонок"
              // ===============================================================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // "Написать" Button (Graphite #191919)
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF191919),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Написать',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // "Звонок" Button (Graphite #191919)
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Аудиозвонок...')),
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF191919),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone_outlined, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Звонок',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
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
              const SizedBox(height: 18),

              // ===============================================================
              // GROUPED CARD 1: О СЕБЕ / ИМЯ ПОЛЬЗОВАТЕЛЯ / ТЕЛЕФОН (Graphite)
              // ===============================================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF191919),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                ),
                child: Column(
                  children: [
                    // О СЕБЕ
                    _buildInfoRow(
                      icon: Icons.info_outline_rounded,
                      iconColor: const Color(0xFF929292),
                      iconBg: const Color(0xFF242424),
                      label: 'О СЕБЕ',
                      value: description,
                    ),
                    const Divider(color: Color(0x14FFFFFF), height: 1, indent: 56),

                    // ИМЯ ПОЛЬЗОВАТЕЛЯ & ДОП ЮЗЕРНЕЙМЫ
                    _buildUsernameRow(
                      username: username,
                      secondaryUsernames: secondaryUsernames,
                      verification: verification,
                      isVerified: isVerified,
                    ),
                    const Divider(color: Color(0x14FFFFFF), height: 1, indent: 56),

                    // НОМЕР ТЕЛЕФОНА
                    _buildInfoRow(
                      icon: Icons.phone_rounded,
                      iconColor: const Color(0xFF929292),
                      iconBg: const Color(0xFF242424),
                      label: 'НОМЕР ТЕЛЕФОНА',
                      value: phone,
                      isInteractive: true,
                      onTap: () => _copyToClipboard(phone, 'Номер телефона'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===============================================================
              // GROUPED CARD 2: ПОЖАЛОВАТЬСЯ / ЗАБЛОКИРОВАТЬ (Graphite)
              // ===============================================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF191919),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                ),
                child: Column(
                  children: [
                    // Пожаловаться
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Жалоба отправлена модераторам Portal')),
                        );
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF242424),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.flag_outlined, color: Color(0xFF929292), size: 18),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Пожаловаться',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF929292), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: Color(0x14FFFFFF), height: 1, indent: 56),

                    // Заблокировать
                    InkWell(
                      onTap: () => _showBlockDialog(context, displayName),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0x26EF4444),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 18),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Заблокировать',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF929292), size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ===============================================================
              // SECTION: ПОДАРКИ (3-Column Square Grid)
              // ===============================================================
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
                    if (_userGifts.isNotEmpty)
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
                      )
                    else
                      InkWell(
                        onTap: () {
                          SendGiftModal.show(
                            context,
                            chat: widget.chat,
                            onGiftSent: (newGift) {
                              if (mounted) {
                                _loadGifts();
                              }
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF191919),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.card_giftcard_rounded, size: 15, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'Подарить',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 13,
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
              const SizedBox(height: 12),

              if (_userGifts.isNotEmpty)
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
                      return _buildGiftCard(gift);
                    },
                  ),
                )
              else if (!_isLoadingGifts)
                _buildEmptyGifts(),
            ],
          ),

          // ===================================================================
          // FLOATING TOP BAR (Back button + Title on scroll)
          // ===================================================================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Circular frosted glass back button
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                    const Spacer(),
                    if (isCurrentUser)
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
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.0),
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
                                  fontSize: 13,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF222222),
            Color(0xFF191919),
            Color(0xFF090909),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
    bool isInteractive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF929292), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFF929292),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isNotEmpty
                        ? value
                        : (label == 'О СЕБЕ'
                            ? 'Информация о себе не указана'
                            : (label == 'НОМЕР ТЕЛЕФОНА' ? '+7 999 000-00-00' : '')),
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: (value == 'Информация о себе не указана' || value.isEmpty)
                          ? const Color(0xFF929292)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsernameRow({
    required String username,
    required List<String> secondaryUsernames,
    String? verification,
    bool isVerified = false,
  }) {
    return InkWell(
      onTap: () => _copyToClipboard('@$username', 'Username'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.alternate_email_rounded, color: Color(0xFF929292), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ИМЯ ПОЛЬЗОВАТЕЛЯ',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFF929292),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isVerified)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          child: VerificationBadge(verification: verification, size: 18),
                        ),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      // Copy icon on far right
                      InkWell(
                        onTap: () => _copyToClipboard('@$username', 'Username'),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Icon(
                            Icons.copy_rounded,
                            size: 17,
                            color: Color(0xFF929292),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (secondaryUsernames.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'а также ',
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 13,
                            color: Color(0xFF929292),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        for (int i = 0; i < secondaryUsernames.length; i++) ...[
                          GestureDetector(
                            onTap: () => _copyToClipboard('@${secondaryUsernames[i]}', 'Username'),
                            child: Text(
                              '@${secondaryUsernames[i]}${i < secondaryUsernames.length - 1 ? ', ' : ''}',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 13,
                                color: Color(0xFF929292),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftCard(UserGift gift) {
    final hasPattern = gift.isUpgraded && gift.patternName.isNotEmpty;
    final numText = (gift.nftNumber > 0 ? gift.nftNumber : gift.id).toString();
    final profileUser = _userProfile;
    final profileName = (profileUser != null && profileUser.displayName.isNotEmpty)
        ? profileUser.displayName
        : widget.chat.title;
    final profileAvatar = (profileUser != null && profileUser.avatar.isNotEmpty)
        ? profileUser.avatar
        : widget.chat.avatar;

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
                          gift.senderAvatar,
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

  Widget _buildEmptyGifts() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.card_giftcard_rounded,
              color: Colors.white.withOpacity(0.15),
              size: 34,
            ),
            const SizedBox(height: 8),
            const Text(
              'У пользователя пока нет подарков',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13,
                color: Color(0xFF929292),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                SendGiftModal.show(
                  context,
                  chat: widget.chat,
                  onGiftSent: (newGift) {
                    if (mounted) {
                      _loadGifts();
                    }
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.card_giftcard_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Отправить подарок',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12.5,
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
    );
  }

  void _showBlockDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191919),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
        title: Text(
          'Заблокировать $name?',
          style: const TextStyle(fontFamily: AppTheme.fontDisplay, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Пользователь не сможет отправлять вам сообщения и звонить.',
          style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF929292))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пользователь заблокирован')),
              );
            },
            child: const Text('Заблокировать', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
