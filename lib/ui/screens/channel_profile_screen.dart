import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../theme.dart';
import '../../data/database_helper.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/media_cache_service.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';
import '../widgets/fullscreen_gallery_viewer.dart';
import 'edit_channel_screen.dart';

class ChannelProfileScreen extends StatefulWidget {
  final Chat chat;

  const ChannelProfileScreen({super.key, required this.chat});

  @override
  State<ChannelProfileScreen> createState() => _ChannelProfileScreenState();
}

class _ChannelProfileScreenState extends State<ChannelProfileScreen> {
  late Chat _currentChat;
  int _subscribersCount = 0;
  bool _isSubscribed = false;
  int? _ownerId;
  bool _isOwner = false;
  String _liveVerification = 'none';
  int _channelArtifacts = 0;
  bool _isMuted = false;

  List<String> _channelPhotos = [];
  bool _isLoadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _subscribersCount = widget.chat.subscribersCount;
    _isSubscribed = widget.chat.isSubscribed;
    _ownerId = widget.chat.ownerId;
    _liveVerification = widget.chat.effectiveVerification;
    _channelArtifacts = widget.chat.artifacts;

    _checkOwner();
    _loadMuteState();
    _loadChannelDetails();
    _loadChannelPhotos();
  }

  Future<void> _loadMuteState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _isMuted = prefs.getBool('channel_muted_${_currentChat.id}') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    HapticFeedback.lightImpact();
    final newVal = !_isMuted;
    setState(() => _isMuted = newVal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('channel_muted_${_currentChat.id}', newVal);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newVal ? 'Уведомления отключены' : 'Уведомления включены'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _checkOwner() {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    if (currentUserId != null && _ownerId != null && _ownerId == currentUserId) {
      _isOwner = true;
    } else if (currentUserId != null && widget.chat.ownerId != null && widget.chat.ownerId == currentUserId) {
      _isOwner = true;
    }
  }

  Future<void> _loadChannelDetails() async {
    try {
      final data = await ApiService.instance.getChannel(_currentChat.id);
      if (data != null && mounted) {
        final verif = data['verification']?.toString();
        final rawOwnerId = data['owner_id'];
        final ownerId = rawOwnerId is int ? rawOwnerId : int.tryParse(rawOwnerId?.toString() ?? '');
        final currentUserId = context.read<AuthProvider>().currentUser?.id;
        final isOwner = (ownerId != null && currentUserId != null && ownerId == currentUserId) ||
            (_currentChat.ownerId != null && currentUserId != null && _currentChat.ownerId == currentUserId);

        final title = data['title']?.toString();
        final avatar = (data['avatar_url'] ?? data['avatar'])?.toString();
        final uname = data['username']?.toString();
        final desc = data['description']?.toString() ?? data['about']?.toString();

        final cleanVerif = (verif != null && verif.isNotEmpty && verif != 'none')
            ? verif
            : ((uname?.toLowerCase() == 'portal' || _currentChat.username?.toLowerCase() == 'portal')
                ? 'verified'
                : 'none');

        setState(() {
          if (data['is_subscribed'] != null) {
            _isSubscribed = data['is_subscribed'] == 1 || data['is_subscribed'] == true;
          }
          if (data['subscribers_count'] != null) {
            _subscribersCount = int.tryParse(data['subscribers_count'].toString()) ?? _subscribersCount;
          }
          if (ownerId != null) {
            _ownerId = ownerId;
          }
          if (data['artifacts'] != null) {
            _channelArtifacts = data['artifacts'] is int
                ? data['artifacts'] as int
                : int.tryParse(data['artifacts'].toString()) ?? _channelArtifacts;
          }
          _isOwner = isOwner;
          _liveVerification = cleanVerif;

          _currentChat = _currentChat.copyWith(
            title: (title != null && title.isNotEmpty) ? title : _currentChat.title,
            avatar: (avatar != null && avatar.isNotEmpty) ? avatar : _currentChat.avatar,
            username: (uname != null && uname.isNotEmpty) ? uname : _currentChat.username,
            description: desc ?? _currentChat.description,
            subscribersCount: _subscribersCount,
            isSubscribed: _isSubscribed,
            verification: cleanVerif,
            artifacts: _channelArtifacts,
          );
        });

        final chatProv = context.read<ChatProvider>();
        chatProv.addOrUpdateChat(_currentChat);
      }
    } catch (_) {}
  }

  Future<void> _loadChannelPhotos() async {
    final List<String> photos = [];

    // 1. Загружаем из локальной БД SQLite
    try {
      final dbMsgs = await DatabaseHelper.instance.getMessages(_currentChat.id, isChannel: true, limit: 200);
      for (final m in dbMsgs) {
        _extractPhotosFromMessage(m, photos);
      }
    } catch (_) {}

    // 2. Если фото мало или нет, пробуем подтянуть посты через ApiService
    if (photos.isEmpty) {
      try {
        final remotePosts = await ApiService.instance.getChatHistory(_currentChat.id, isChannel: true, limit: 60);
        for (final p in remotePosts) {
          final text = p['text']?.toString() ?? '';
          if (text.startsWith('[PORTAL_PHOTO]:')) {
            try {
              final jsonStr = text.substring('[PORTAL_PHOTO]:'.length).trim();
              final map = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (map['urls'] is List) {
                for (final u in map['urls']) {
                  final str = u?.toString() ?? '';
                  if (str.isNotEmpty && !photos.contains(str)) photos.add(str);
                }
              } else if (map['url'] != null && map['url'].toString().isNotEmpty) {
                final str = map['url'].toString();
                if (!photos.contains(str)) photos.add(str);
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _channelPhotos = photos;
        _isLoadingPhotos = false;
      });
    }
  }

  void _extractPhotosFromMessage(Message m, List<String> list) {
    final t = m.text.trim();
    if (t.startsWith('[PORTAL_PHOTO]:')) {
      try {
        final jsonStr = t.substring('[PORTAL_PHOTO]:'.length).trim();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (map['urls'] is List) {
          for (final u in map['urls']) {
            final str = u?.toString() ?? '';
            if (str.isNotEmpty && !list.contains(str)) {
              list.add(str);
            }
          }
        } else if (map['url'] != null && map['url'].toString().isNotEmpty) {
          final str = map['url'].toString();
          if (!list.contains(str)) {
            list.add(str);
          }
        }
      } catch (_) {}
    }
  }

  String _formatSubscribers(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) {
      return '$count подписчиков';
    }
    if (mod10 == 1) {
      return '$count подписчик';
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return '$count подписчика';
    }
    return '$count подписчиков';
  }

  Future<void> _openEditScreen() async {
    final result = await Navigator.of(context).push<Chat>(
      MaterialPageRoute(
        builder: (_) => EditChannelScreen(chat: _currentChat),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _currentChat = result;
      });
      _loadChannelDetails();
    }
  }

  Future<void> _toggleSubscription() async {
    final willSubscribe = !_isSubscribed;
    if (!willSubscribe) {
      try {
        await ApiService.instance.toggleChannelSubscription(_currentChat.id, true);
        if (!mounted) return;
        await context.read<ChatProvider>().removeChatLocally(_currentChat.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы отписались от канала'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
      return;
    }

    setState(() {
      _isSubscribed = true;
      _subscribersCount += 1;
    });

    try {
      final res = await ApiService.instance.toggleChannelSubscription(_currentChat.id, false);
      if (res['is_subscribed'] != null && mounted) {
        final actual = res['is_subscribed'] == 1 || res['is_subscribed'] == true;
        setState(() => _isSubscribed = actual);
      }
      if (mounted) {
        final updatedChat = _currentChat.copyWith(
          isSubscribed: true,
          subscribersCount: _subscribersCount,
        );
        await context.read<ChatProvider>().addOrUpdateChat(updatedChat);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _subscribersCount = _subscribersCount <= 0 ? 0 : _subscribersCount - 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _copyLink() {
    final cleanUsername = (_currentChat.username ?? 'channel').replaceFirst(RegExp(r'^@+'), '');
    final url = 'https://portalmsg.ru/$cleanUsername';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ссылка скопирована в буфер обмена'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUsername = (_currentChat.username ?? 'channel').replaceFirst(RegExp(r'^@+'), '');
    final linkText = 'https://portalmsg.ru/$cleanUsername';
    final descText = (_currentChat.description ?? '').trim();
    final hasVerified = VerificationBadge.isVerified(_liveVerification);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_isOwner)
                    GestureDetector(
                      onTap: _openEditScreen,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Изм.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppTheme.fontDisplay,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Main Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // Center Channel Avatar
                    GestureDetector(
                      onTap: () {
                        if (_currentChat.avatar.isNotEmpty) {
                          FullscreenGalleryViewer.show(context, imageUrls: [_currentChat.avatar], initialIndex: 0);
                        }
                      },
                      child: Center(
                        child: AvatarWidget(
                          avatarUrl: _currentChat.avatar,
                          title: _currentChat.title,
                          size: 88,
                          isChannel: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Channel Title + Verification Badge (if verified)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _currentChat.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                fontFamily: AppTheme.fontDisplay,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasVerified) ...[
                            const SizedBox(width: 6),
                            VerificationBadge(
                              verification: _liveVerification,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Subscribers Count
                    Text(
                      _formatSubscribers(_subscribersCount),
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        fontFamily: AppTheme.fontText,
                        letterSpacing: -0.1,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Circular action buttons (matching reference screenshot)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildRoundActionButton(
                            icon: _isMuted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
                            label: 'звук',
                            onTap: _toggleMute,
                          ),
                          const SizedBox(width: 24),
                          _buildRoundActionButton(
                            icon: Icons.chat_bubble_rounded,
                            label: 'чат',
                            onTap: () {}, // Неактивна по требованию
                          ),
                          const SizedBox(width: 24),
                          _buildRoundActionButton(
                            icon: _isSubscribed ? Icons.logout_rounded : Icons.add_rounded,
                            label: _isSubscribed ? 'покинуть' : 'подписаться',
                            onTap: _toggleSubscription,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Card 1: Link & Description (1:1 with reference screenshot)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Link section
                          InkWell(
                            onTap: _copyLink,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Text(
                                        'ссылка',
                                        style: TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      Spacer(),
                                      Icon(
                                        Icons.qr_code_2_rounded,
                                        color: Color(0xFF2990FF),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    linkText,
                                    style: const TextStyle(
                                      color: Color(0xFF2990FF),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const Divider(height: 1, color: Color(0xFF2C2C2E), indent: 16, endIndent: 16),

                          // Description section
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'описание',
                                  style: TextStyle(
                                    color: Color(0xFF8E8E93),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  descText.isNotEmpty ? descText : 'Нет описания',
                                  style: TextStyle(
                                    color: descText.isNotEmpty ? Colors.white : const Color(0xFF636366),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_isOwner) ...[
                      const SizedBox(height: 14),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            _buildActionTile(
                              icon: Icons.tune_rounded,
                              iconBgColor: const Color(0xFFFF9500),
                              title: 'Настройки канала',
                              trailingText: '>',
                              onTap: _openEditScreen,
                              isFirst: true,
                              isLast: true,
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_isOwner) ...[
                      const SizedBox(height: 12),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0x1AFFFFFF),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Lottie.asset(
                                    'lib/assets/material/artefact.json',
                                    repeat: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              'Баланс артефактов',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppTheme.fontDisplay,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0x22FFFFFF),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '$_channelArtifacts',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: AppTheme.fontDisplay,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Photos Grid ("плитки с фотографиями которые отправил сам канал")
                    if (_channelPhotos.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            const Text(
                              'МЕДИА',
                              style: TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_channelPhotos.length}',
                              style: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 3,
                              mainAxisSpacing: 3,
                            ),
                            itemCount: _channelPhotos.length,
                            itemBuilder: (ctx, idx) {
                              final rawUrl = _channelPhotos[idx];
                              final isLocal = File(rawUrl).existsSync();
                              final fullUrl = isLocal ? rawUrl : AppConstants.formatMediaUrl(rawUrl);

                              return GestureDetector(
                                onTap: () => FullscreenGalleryViewer.show(
                                  context,
                                  imageUrls: _channelPhotos,
                                  initialIndex: idx,
                                ),
                                child: Container(
                                  color: const Color(0xFF1C1C1E),
                                  child: isLocal
                                      ? Image.file(
                                          File(fullUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: fullUrl,
                                          cacheManager: MediaCacheService.instance.cacheManager,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 800,
                                          placeholder: (c, u) => Container(
                                            color: const Color(0xFF2C2C2E),
                                            child: const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (c, u, s) => Container(
                                            color: const Color(0xFF2C2C2E),
                                            child: const Icon(
                                              Icons.broken_image_rounded,
                                              color: Colors.white38,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ] else if (_isLoadingPhotos) ...[
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A84FF)),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 72,
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
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1E),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
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

  Widget _buildActionTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String trailingText,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(18) : Radius.zero,
        bottom: isLast ? const Radius.circular(18) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: Colors.white, size: 19),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              trailingText,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
