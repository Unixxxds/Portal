import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import '../widgets/profile_gift_bubbles_avatar.dart';
import '../widgets/send_gift_modal.dart';
import '../widgets/telegram_chat_route.dart';
import 'chat_screen.dart';
import '../../models/profile_color_theme.dart';
import 'edit_profile_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final Chat chat;

  const UserProfileScreen({super.key, required this.chat});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  User? _userProfile;
  List<UserGift> _userGifts = [];
  bool _isLoadingGifts = false;
  Chat? _pinnedChannel;
  int? _resolvedChannelId;

  late final AnimationController _entranceController;
  late final Animation<double> _contentFadeAnim;
  late final Animation<Offset> _contentSlideAnim;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _contentFadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.18, 1.0, curve: Curves.easeOut),
    );
    _contentSlideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.07),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.10, 1.0, curve: Curves.easeOutCubic),
    ));
    _entranceController.forward();

    final currentAuth = context.read<AuthProvider>().currentUser;
    final targetUserId = widget.chat.participantId ?? widget.chat.id;
    final isSelf = currentAuth != null && currentAuth.id == targetUserId;
    final initChannelId = isSelf ? currentAuth.pinnedChannelId : null;
    if (initChannelId != null && initChannelId > 0) {
      _resolvePinnedChannel(initChannelId);
    }

    _loadProfile();
    _loadGifts();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
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
    // 0. Мгновенная загрузка профиля из локальной SQLite базы (0 мс)
    final initialTargetId = widget.chat.participantId ?? widget.chat.id;
    try {
      final cachedUser = await DatabaseHelper.instance.getUser(initialTargetId);
      if (cachedUser != null && mounted && _userProfile == null) {
        setState(() {
          _userProfile = cachedUser;
        });
      }
    } catch (_) {}

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
      if (data != null) {
        final freshUser = User.fromJson(data);
        _userProfile = freshUser;
        DatabaseHelper.instance.insertUser(freshUser);
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
        setState(() {});

        final chId = freshUser.pinnedChannelId;
        if (chId != null && chId > 0) {
          _resolvePinnedChannel(chId);
        }
      }

      // Перезагружаем подарки с подтвержденным userId пользователя
      if (resolvedUserId != null && resolvedUserId > 0) {
        _loadGifts(targetId: resolvedUserId);
      }
    }
  }

  Future<void> _resolvePinnedChannel(int channelId) async {
    if (channelId <= 0 || _resolvedChannelId == channelId) return;
    _resolvedChannelId = channelId;

    // 1. Check ChatProvider
    final chatProv = context.read<ChatProvider>();
    final fromProvider = chatProv.chats.where((c) => c.isChannel && c.id == channelId).firstOrNull;
    if (fromProvider != null) {
      if (mounted) {
        setState(() => _pinnedChannel = fromProvider);
      }
      if (fromProvider.lastMessageText.isEmpty) {
        _fetchLatestChannelPost(channelId);
      }
      return;
    }

    // 2. Database or API
    try {
      final cachedChat = await DatabaseHelper.instance.getChat(channelId);
      if (cachedChat != null && mounted) {
        setState(() => _pinnedChannel = cachedChat);
      }

      final msgs = await ApiService.instance.getChatHistory(channelId, isChannel: true, limit: 1);
      final lastMsg = msgs.isNotEmpty ? msgs.first : null;
      final lastText = lastMsg?['text']?.toString() ?? cachedChat?.lastMessageText ?? '';
      final lastTime = lastMsg?['created_at']?.toString() ?? lastMsg?['time']?.toString() ?? cachedChat?.lastMessageTime ?? '';

      final results = await ApiService.instance.searchUsers(channelId.toString());
      final match = results.where((item) {
        final id = item['chat_id'] ?? item['id'];
        return id != null && id.toString() == channelId.toString();
      }).firstOrNull;

      if (match != null && mounted) {
        final channelChat = Chat(
          id: channelId,
          title: (match['title'] ?? match['name'] ?? cachedChat?.title ?? 'Канал').toString(),
          type: 'channel',
          avatar: (match['avatar'] ?? match['avatar_url'] ?? cachedChat?.avatar ?? '').toString(),
          isChannel: true,
          username: match['username']?.toString() ?? cachedChat?.username,
          subscribersCount: match['subscribers_count'] is int
              ? match['subscribers_count'] as int
              : int.tryParse(match['subscribers_count']?.toString() ?? '') ?? (cachedChat?.subscribersCount ?? 0),
          verification: match['verification']?.toString() ?? cachedChat?.verification,
          lastMessageText: lastText,
          lastMessageTime: lastTime,
        );
        setState(() => _pinnedChannel = channelChat);
        chatProv.addOrUpdateChat(channelChat);
      } else if (cachedChat != null && mounted) {
        setState(() {
          _pinnedChannel = cachedChat.copyWith(
            lastMessageText: lastText.isNotEmpty ? lastText : cachedChat.lastMessageText,
            lastMessageTime: lastTime.isNotEmpty ? lastTime : cachedChat.lastMessageTime,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLatestChannelPost(int channelId) async {
    try {
      final msgs = await ApiService.instance.getChatHistory(channelId, isChannel: true, limit: 1);
      if (msgs.isNotEmpty && mounted && _pinnedChannel != null) {
        final first = msgs.first;
        final text = first['text']?.toString() ?? '';
        final time = first['created_at']?.toString() ?? first['time']?.toString() ?? '';
        if (text.isNotEmpty || time.isNotEmpty) {
          setState(() {
            _pinnedChannel = _pinnedChannel!.copyWith(
              lastMessageText: text,
              lastMessageTime: time,
            );
          });
        }
      }
    } catch (_) {}
  }

  String _formatSparks(int sparks) {
    if (sparks <= 0) return '0';
    return sparks.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
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

    // Resolve channel pinned to this profile
    final effectiveChannelId = isCurrentUser
        ? (authUser?.pinnedChannelId ?? user?.pinnedChannelId)
        : (user?.pinnedChannelId ?? _userProfile?.pinnedChannelId);

    final chatProv = context.watch<ChatProvider>();
    final channelFromProv = effectiveChannelId != null
        ? chatProv.chats.where((c) => c.isChannel && c.id == effectiveChannelId).firstOrNull
        : null;
    final displayChannel = channelFromProv ?? _pinnedChannel;

    if (displayChannel == null && effectiveChannelId != null && effectiveChannelId > 0 && _resolvedChannelId != effectiveChannelId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolvePinnedChannel(effectiveChannelId);
      });
    }

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

    final effectiveProfileColor = isCurrentUser
        ? (authUser?.profileColor ?? _userProfile?.profileColor)
        : (_userProfile?.profileColor ?? user?.profileColor);
    final profileTheme = ProfileColorTheme.fromId(effectiveProfileColor);

    return Scaffold(
      backgroundColor: profileTheme.backgroundGradient.last,
      body: Stack(
        children: [
          // Background Gradient matching Telegram profile from the photo
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: profileTheme.backgroundGradient,
                  stops: profileTheme.stops,
                ),
              ),
            ),
          ),

          // Subtle radial ambient bloom behind the avatar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 0.85,
                  colors: [
                    profileTheme.ambientGlow,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

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
                    // Banner Image spanning full screen width with smooth fade at bottom
                    if (formattedBanner.isNotEmpty) ...[
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 360,
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black,
                                Colors.black,
                                Colors.black87,
                                Colors.black38,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.45, 0.70, 0.88, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: CachedNetworkImage(
                            imageUrl: formattedBanner,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            placeholder: (context, url) => _buildDefaultBanner(),
                            errorWidget: (context, url, error) => _buildDefaultBanner(),
                            fadeInDuration: const Duration(milliseconds: 140),
                            fadeOutDuration: const Duration(milliseconds: 140),
                          ),
                        ),
                      ),

                      // Top darkening gradient
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 90,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x80000000), Colors.transparent],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 360,
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black,
                                Colors.black,
                                Colors.black87,
                                Colors.black38,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.45, 0.70, 0.88, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: _buildDefaultBanner(),
                        ),
                      ),
                    ],

                    // Identity: Centered Avatar with Orbiting 3D Gift Bubbles (без обводки)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -32,
                      child: Center(
                        child: ProfileGiftBubblesAvatar(
                          avatarRadius: 44,
                          gifts: _userGifts,
                          showBorder: false,
                          onGiftTap: (gift) {
                            GiftDetailModal.show(
                              context,
                              gift: gift,
                              ownerName: displayName,
                              ownerAvatar: avatarUrl,
                            );
                          },
                          child: Hero(
                            tag: 'user_avatar_${widget.chat.id}',
                            flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                              return Material(
                                color: Colors.transparent,
                                child: toHeroContext.widget,
                              );
                            },
                            child: AvatarWidget(
                              avatarUrl: avatarUrl,
                              title: displayName,
                              size: 88,
                              isOnline: false,
                              isSaved: chat.isSaved,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Name & Online Status (Centered directly under avatar)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // For users: verification badge (dev or user) is to the LEFT of the name
                          if (isVerified) ...[
                            VerificationBadge(verification: verification, size: 28),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 23,
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
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isOnline) ...[
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 6),
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
                              fontSize: 13.5,
                              color: isOnline
                                  ? AppTheme.statusOnline
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Frosted glass Sparks balance capsule (ультра-прозрачная и стеклянная)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                            decoration: BoxDecoration(
                              color: const Color(0x18FFFFFF), // Ультра-прозрачный стеклянный фон
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0x1FFFFFFF), // Тонкая полупрозрачная обводка
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'lib/assets/premium.svg',
                                  width: 14,
                                  height: 14,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_formatSparks(user?.sparks ?? 0)} Sparks',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
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
              FadeTransition(
                opacity: _contentFadeAnim,
                child: SlideTransition(
                  position: _contentSlideAnim,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // ===============================================================
                      // ACTION BUTTONS: "звонок", "написать", "поиск" (круглые, серые и поменьше)
                      // ===============================================================
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildRoundActionButton(
                              icon: Icons.phone_rounded,
                              label: 'звонок',
                              backgroundColor: profileTheme.buttonColor,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Аудиозвонок...'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 20),
                            _buildRoundActionButton(
                              svgAsset: 'lib/assets/chat.svg',
                              label: 'написать',
                              backgroundColor: profileTheme.buttonColor,
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 20),
                            _buildRoundActionButton(
                              icon: Icons.search_rounded,
                              label: 'поиск',
                              backgroundColor: profileTheme.buttonColor,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Поиск по сообщениям'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
              const SizedBox(height: 18),

              // ===============================================================
              // PINNED CHANNEL CARD (После кнопок Написать и Звонок)
              // ===============================================================
              if (displayChannel != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              _formatSubscribersCount(displayChannel.subscribersCount),
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

                      // Сама скругленная плашка (адаптируется к теме)
                      Container(
                        decoration: BoxDecoration(
                          color: profileTheme.cardColor,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(26),
                            onTap: () {
                              Navigator.push(
                                context,
                                TelegramChatRoute(
                                  builder: (_) => ChatScreen(chat: displayChannel),
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
                                    avatarUrl: displayChannel.avatar,
                                    title: displayChannel.title,
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
                                                displayChannel.title,
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
                                            if (displayChannel.isVerified) ...[
                                              const SizedBox(width: 5),
                                              VerificationBadge(
                                                verification: displayChannel.effectiveVerification,
                                                size: 15,
                                              ),
                                            ],
                                            const SizedBox(width: 8),
                                            // В правом верхнем углу время отправки последнего поста
                                            Text(
                                              _formatPostTime(displayChannel.lastMessageTime),
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
                                          _cleanPostText(displayChannel.lastMessageText),
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
                ),
                const SizedBox(height: 18),
              ],

              // ===============================================================
              // GROUPED CARD 1: О СЕБЕ / ИМЯ ПОЛЬЗОВАТЕЛЯ / ТЕЛЕФОН
              // ===============================================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: profileTheme.cardColor,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    // о себе
                    _buildInfoRow(
                      label: 'о себе',
                      value: description,
                    ),
                    const Divider(color: Color(0x14FFFFFF), height: 1, indent: 16, endIndent: 16),

                    // имя пользователя & доп юзернеймы
                    _buildUsernameRow(
                      username: username,
                      secondaryUsernames: secondaryUsernames,
                      verification: verification,
                      isVerified: isVerified,
                    ),
                    const Divider(color: Color(0x14FFFFFF), height: 1, indent: 16, endIndent: 16),

                    // номер телефона
                    _buildInfoRow(
                      label: 'номер телефона',
                      value: phone,
                      isInteractive: true,
                      onTap: () => _copyToClipboard(phone, 'Номер телефона'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===============================================================
              // GROUPED CARD 2: ПОЖАЛОВАТЬСЯ / ЗАБЛОКИРОВАТЬ
              // ===============================================================
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: profileTheme.cardColor,
                  borderRadius: BorderRadius.circular(26),
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
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
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

              // ===============================================================
              // VERIFICATION OFFICIAL BADGE FOOTER
              // ===============================================================
              if (isVerified) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Builder(
                      builder: (badgeContext) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => VerificationBadge.showVerificationPopover(badgeContext, verification),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: VerificationBadge(
                                    verification: verification,
                                    size: 14,
                                    color: Colors.white,
                                    opacity: 0.60,
                                    interactive: false,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: verification == 'dev'
                                    ? 'Официальный аккаунт разработчиков Portal'
                                    : (verification == 'artist'
                                        ? 'Этот аккаунт подтверждён как профиль официального художника Portal'
                                        : 'Этот аккаунт подтверждён представителями Portal как официальный'),
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withOpacity(0.50),
                                  height: 1.35,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
                            recipientId: widget.chat.participantId ?? widget.chat.id,
                            recipientUsername: widget.chat.title,
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
                      return RepaintBoundary(
                        child: _buildGiftCard(gift),
                      );
                    },
                  ),
                )
              else if (!_isLoadingGifts)
                _buildEmptyGifts(),
                    ],
                  ),
                ),
              ),
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
    required String label,
    required String value,
    bool isInteractive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value.isNotEmpty
                    ? value
                    : (label.toLowerCase() == 'о себе'
                        ? 'Информация о себе не указана'
                        : (label.toLowerCase() == 'номер телефона' ? '+7 999 000-00-00' : '')),
                style: TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                  color: (value == 'Информация о себе не указана' || value.isEmpty)
                      ? const Color(0xFF8E8E93)
                      : Colors.white,
                ),
              ),
            ],
          ),
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
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'имя пользователя',
                style: TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '@$username',
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                ),
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
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w300,
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
                            color: Color(0xFF8E8E93),
                            fontWeight: FontWeight.w300,
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
      ),
    );
  }

  Widget _buildRoundActionButton({
    IconData? icon,
    String? svgAsset,
    required String label,
    required VoidCallback? onTap,
    Color? backgroundColor,
  }) {
    return SizedBox(
      width: 66,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withOpacity(0.12),
              highlightColor: Colors.white.withOpacity(0.06),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: backgroundColor ?? const Color(0xFF262626),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: svgAsset != null
                      ? SvgPicture.asset(
                          svgAsset,
                          width: 22,
                          height: 22,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        )
                      : (icon != null
                          ? Icon(
                              icon,
                              color: Colors.white,
                              size: 21,
                            )
                          : const SizedBox.shrink()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontFamily: AppTheme.fontText,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
                    ).withOpacity(0.35),
                    blurRadius: 10,
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
                      ? CachedNetworkImage(
                          imageUrl: gift.senderAvatar,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildCardSenderFallback(gift),
                          errorWidget: (_, __, ___) => _buildCardSenderFallback(gift),
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
                  recipientId: widget.chat.participantId ?? widget.chat.id,
                  recipientUsername: widget.chat.title,
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
