import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
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
import '../../widgets/profile_gift_bubbles_avatar.dart';
import '../../widgets/telegram_chat_route.dart';
import '../../widgets/telegram_profile_route.dart';
import '../chat_screen.dart';
import '../edit_profile_screen.dart';
import '../profile_qr_screen.dart';

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
    final auth = context.read<AuthProvider>();
    if (auth.currentUser != null) {
      // 1. Instant 0 ms SQLite cache load before any network call
      DatabaseHelper.instance.getUserGifts(auth.currentUser!.id).then((cached) {
        if (cached.isNotEmpty && mounted && _userGifts.isEmpty) {
          setState(() {
            _userGifts = cached;
          });
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  Future<void> _pickAndUploadProfileAvatar(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (picked != null && picked.path.isNotEmpty) {
        final file = File(picked.path);
        if (await file.exists()) {
          final url = await ApiService.instance.uploadAvatar(file);
          if (context.mounted && url.isNotEmpty) {
            final auth = context.read<AuthProvider>();
            final u = auth.currentUser;
            if (u != null) {
              await auth.updateProfile(
                firstName: u.firstName,
                lastName: u.lastName,
                username: u.username,
                description: u.description,
                avatar: url,
                bannerUrl: u.bannerUrl,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Фото профиля обновлено', style: TextStyle(color: Colors.white)),
                  backgroundColor: const Color(0xFF191919),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: const Color(0xFF191919)),
        );
      }
    }
  }

  Future<void> _pickAndUploadProfileBanner(BuildContext context, {bool pickMedia = false}) async {
    final auth = context.read<AuthProvider>();
    final u = auth.currentUser;
    if (u == null) return;
    if (!u.isPremium) {
      _showPremiumBannerNotice(context);
      return;
    }
    try {
      final picker = ImagePicker();
      XFile? picked;
      if (pickMedia) {
        try {
          picked = await picker.pickMedia();
        } catch (_) {
          picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
        }
      } else {
        picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      }
      if (picked != null && picked.path.isNotEmpty) {
        final file = File(picked.path);
        if (await file.exists()) {
          final url = await ApiService.instance.uploadBanner(file);
          if (context.mounted && url.isNotEmpty) {
            await auth.updateProfile(
              firstName: u.firstName,
              lastName: u.lastName,
              username: u.username,
              description: u.description,
              avatar: u.avatar,
              bannerUrl: url,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Баннер профиля обновлен', style: TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFF191919),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: const Color(0xFF191919)),
        );
      }
    }
  }

  void _showPremiumBannerNotice(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B98FF).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: PremiumBadge(size: 32),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Баннер только с Premium',
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Кастомный баннер доступен только с подпиской Premium. Оформите Premium, чтобы персонализировать фон своего профиля.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 14,
                    color: Color(0xFF929292),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B98FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'Понятно',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProfileEditMenu(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final isPremium = user?.isPremium ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Редактировать профиль',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Имя, фамилия, юзернейм, о себе',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                    );
                  },
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 19),
                  ),
                  title: const Text(
                    'Изменить фото профиля',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Выбрать новое фото из галереи',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadProfileAvatar(context);
                  },
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPremium ? Icons.panorama_outlined : Icons.star_rounded,
                      color: isPremium ? Colors.white : const Color(0xFF3B98FF),
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: [
                      const Text(
                        'Изменить баннер',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!isPremium) ...[
                        const SizedBox(width: 8),
                        const PremiumBadge(size: 14),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    isPremium
                        ? 'Статичный фон, Live-фото или GIF/WebP анимация'
                        : 'Доступно только с подпиской Premium',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: isPremium ? const Color(0xFF929292) : const Color(0xFF3B98FF),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isPremium) {
                      _pickAndUploadProfileBanner(context);
                    } else {
                      _showPremiumBannerNotice(context);
                    }
                  },
                ),
                if (user != null && user.username.isNotEmpty) ...[
                  const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFF242424),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                    ),
                    title: const Text(
                      'Скопировать ссылку на профиль',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '@${user.username}',
                      style: const TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: 'https://t.me/${user.username}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Ссылка скопирована в буфер', style: TextStyle(color: Colors.white)),
                          backgroundColor: const Color(0xFF191919),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatSubscribersCount(int count) {
    if (count <= 0) return '0 подписчиков';
    final mod10 = count % 10;
    final mod100 = count % 100;
    String word = 'подписчиков';
    if (mod100 < 11 || mod100 > 14) {
      if (mod10 == 1) {
        word = 'подписчик';
      } else if (mod10 >= 2 && mod10 <= 4) {
        word = 'подписчика';
      }
    }
    return '$count $word';
  }

  String _formatPostTime(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return '';
    try {
      DateTime dt;
      final trimmed = dateStr.trim();
      if (RegExp(r'^\d+$').hasMatch(trimmed)) {
        final val = int.parse(trimmed);
        if (val > 1000000000000) {
          dt = DateTime.fromMillisecondsSinceEpoch(val).toLocal();
        } else {
          dt = DateTime.fromMillisecondsSinceEpoch(val * 1000).toLocal();
        }
      } else {
        dt = DateTime.parse(trimmed).toLocal();
      }

      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');

      if (isToday) {
        return '$hour:$minute';
      }

      final yesterday = now.subtract(const Duration(days: 1));
      final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
      if (isYesterday) {
        return 'Вчера';
      }

      if (dt.year == now.year) {
        const months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
        return '${dt.day} ${months[dt.month - 1]}';
      } else {
        final d = dt.day.toString().padLeft(2, '0');
        final mo = dt.month.toString().padLeft(2, '0');
        final y = (dt.year % 100).toString().padLeft(2, '0');
        return '$d.$mo.$y';
      }
    } catch (_) {
      if (dateStr.length <= 5 && dateStr.contains(':')) {
        return dateStr.trim();
      }
      return '';
    }
  }

  String _cleanPostText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Нет публикаций';
    if (trimmed.startsWith('[PORTAL_PHOTO]:')) {
      try {
        final jsonStr = trimmed.substring('[PORTAL_PHOTO]:'.length).trim();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final caption = map['caption']?.toString() ?? '';
        return caption.isNotEmpty ? '📷 $caption' : '📷 Фотография';
      } catch (_) {
        return '📷 Фотография';
      }
    }
    if (trimmed.startsWith('[PORTAL_STICKER]:')) return 'Стикер';
    if (trimmed.startsWith('[PORTAL_VOICE]:')) return '🎤 Голосовое сообщение';
    return trimmed;
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
                            CachedNetworkImage(
                              imageUrl: formattedBanner,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: const Color(0xFF191919),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF191919),
                              ),
                              fadeInDuration: const Duration(milliseconds: 140),
                              fadeOutDuration: const Duration(milliseconds: 140),
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

                    // Top Bar over banner: Круглая кнопка с QR-кодом + "Изм."
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 18,
                      right: 16,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                TelegramProfileRoute(
                                  builder: (_) => const ProfileQrScreen(),
                                ),
                              );
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xCC191919),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0x33FFFFFF), width: 1.0),
                              ),
                              child: const Icon(
                                Icons.qr_code_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _showProfileEditMenu(context),
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

                    // Avatar overlapping banner bottom with 3D Orbiting Gift Bubbles
                    Positioned(
                      bottom: -32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ProfileGiftBubblesAvatar(
                          avatarRadius: 45,
                          gifts: _userGifts,
                          onAvatarTap: () => _showProfileEditMenu(context),
                          onGiftTap: (gift) {
                            GiftDetailModal.show(
                              context,
                              gift: gift,
                              ownerName: user.fullName.isNotEmpty ? user.fullName : user.username,
                              ownerAvatar: user.avatar,
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
                          child: Stack(
                            children: [
                              AvatarWidget(
                                avatarUrl: user.avatar,
                                title: user.fullName.isNotEmpty ? user.fullName : user.username,
                                size: 90,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.appBg, width: 2),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: Color(0xFF090909),
                                      size: 13,
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
              const SizedBox(height: 42),
            ] else ...[
              // ===============================================================
              // TOP BAR: "Профиль" + Кнопка "Изм." (Default without banner)
              // ===============================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 16, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          TelegramProfileRoute(
                            builder: (_) => const ProfileQrScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                        ),
                        child: const Icon(
                          Icons.qr_code_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showProfileEditMenu(context),
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

              // PROFILE HEADER: Avatar with 3D Orbiting Gift Bubbles
              Center(
                child: ProfileGiftBubblesAvatar(
                  avatarRadius: 46,
                  gifts: _userGifts,
                  onAvatarTap: () => _showProfileEditMenu(context),
                  onGiftTap: (gift) {
                    GiftDetailModal.show(
                      context,
                      gift: gift,
                      ownerName: user.fullName.isNotEmpty ? user.fullName : user.username,
                      ownerAvatar: user.avatar,
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
                  child: Stack(
                    children: [
                      AvatarWidget(
                        avatarUrl: user.avatar,
                        title: user.fullName.isNotEmpty ? user.fullName : user.username,
                        size: 92,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.appBg, width: 2),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF090909),
                              size: 13,
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
            const SizedBox(height: 12),

            // =================================================================
            // PINNED CHANNEL CARD (Канал в профиле)
            // =================================================================
            Builder(
              builder: (context) {
                final pinnedChannel = user.pinnedChannelId != null
                    ? chatProvider.chats.where((c) => c.isChannel && c.id == user.pinnedChannelId).firstOrNull
                    : null;
                if (pinnedChannel == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Над плашкой: слева "КАНАЛ", справа "(кол-во) подписчиков"
                      Padding(
                        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'КАНАЛ',
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                            Text(
                              _formatSubscribersCount(pinnedChannel.subscribersCount),
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Сама скругленная плашка
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                TelegramChatRoute(
                                  builder: (_) => ChatScreen(chat: pinnedChannel),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Слева аватарка канала
                                  AvatarWidget(
                                    avatarUrl: pinnedChannel.avatar,
                                    title: pinnedChannel.title,
                                    size: 46,
                                  ),
                                  const SizedBox(width: 12),

                                  // Около аватарки: название канала + галочка, снизу текст последнего поста
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                pinnedChannel.title,
                                                style: const TextStyle(
                                                  fontFamily: AppTheme.fontDisplay,
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (pinnedChannel.isVerified) ...[
                                              const SizedBox(width: 5),
                                              VerificationBadge(
                                                verification: pinnedChannel.effectiveVerification,
                                                size: 15,
                                              ),
                                            ],
                                            const SizedBox(width: 8),
                                            // В правом верхнем углу время отправки последнего поста
                                            Text(
                                              _formatPostTime(pinnedChannel.lastMessageTime),
                                              style: const TextStyle(
                                                fontFamily: AppTheme.fontText,
                                                fontSize: 12.5,
                                                color: Color(0xFF8E8E93),
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _cleanPostText(pinnedChannel.lastMessageText),
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 13.5,
                                            color: Color(0xFF929292),
                                            height: 1.25,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

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
                          TelegramChatRoute(builder: (context) => ChatScreen(chat: savedMessagesChat)),
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
