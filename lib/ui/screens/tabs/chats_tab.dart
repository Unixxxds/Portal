import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/chat.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../services/api_service.dart';
import '../../../core/user_activity_helper.dart';
import '../../theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/badges.dart';
import '../../widgets/telegram_typing_indicator.dart';
import '../chat_screen.dart';
import '../create_channel_screen.dart';

class ChatsTab extends StatefulWidget {
  final VoidCallback onOpenProfile;

  const ChatsTab({super.key, required this.onOpenProfile});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;
  bool _isSearching = false;
  List<Map<String, dynamic>> _remoteResults = [];

  int _selectedFolderIndex = 0;
  final List<String> _folders = const ['Все', 'Личные', 'Каналы', 'Группы'];

  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmerAnimation = Tween<double>(begin: 0.25, end: 0.85).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    final query = val.trim();
    setState(() {
      _searchQuery = query;
    });

    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _remoteResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await ApiService.instance.searchUsers(query);
        if (mounted && _searchQuery == query) {
          setState(() {
            _remoteResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted && _searchQuery == query) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _handleSelectSearchResult(
    BuildContext context,
    Map<String, dynamic> item,
    ChatProvider chatProvider,
    int currentUserId,
  ) async {
    final isChannel = item['is_channel'] == 1 ||
        item['is_channel'] == true ||
        item['type'] == 'channel' ||
        (item['title'] != null &&
            (item['title'].toString().toLowerCase().contains('канал')));

    if (isChannel) {
      final chatId = item['chat_id'] is int
          ? item['chat_id'] as int
          : (item['id'] is int ? item['id'] as int : int.tryParse(item['id']?.toString() ?? '') ?? 0);
      final title = (item['title'] ?? item['name'] ?? item['first_name'] ?? 'Канал').toString();
      final avatar = (item['avatar'] ?? item['avatar_url'] ?? '').toString();
      final username = item['username']?.toString();
      final subCount = item['subscribers_count'] is int
          ? item['subscribers_count'] as int
          : int.tryParse(item['subscribers_count']?.toString() ?? '') ?? 0;
      final isSubscribed = item['is_subscribed'] == 1 || item['is_subscribed'] == true;

      Chat? existingChat;
      for (final c in chatProvider.chats) {
        if (c.isChannel && c.id == chatId) {
          existingChat = c;
          break;
        }
        if (c.isChannel && username != null && c.username != null && c.username!.toLowerCase() == username.toLowerCase()) {
          existingChat = c;
          break;
        }
      }

      Chat channelChat;
      if (existingChat != null) {
        channelChat = existingChat.copyWith(
          title: (title.isNotEmpty && title != 'Канал') ? title : existingChat.title,
          avatar: avatar.isNotEmpty ? avatar : existingChat.avatar,
          username: (username != null && username.isNotEmpty) ? username : existingChat.username,
          isChannel: true,
          subscribersCount: subCount > 0 ? subCount : existingChat.subscribersCount,
          isSubscribed: isSubscribed || existingChat.isSubscribed,
        );
      } else {
        channelChat = Chat(
          id: chatId,
          title: title,
          type: 'channel',
          avatar: avatar,
          isChannel: true,
          username: username,
          subscribersCount: subCount,
          isSubscribed: isSubscribed,
        );
      }

      await chatProvider.addOrUpdateChat(channelChat);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chat: channelChat)),
        );
      }
      return;
    }

    // Личный аккаунт (пользователь)
    final targetUserId = item['id'] is int
        ? item['id'] as int
        : int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final username = item['username']?.toString();
    final fName = item['first_name']?.toString() ?? '';
    final lName = item['last_name']?.toString() ?? '';
    final fullName = '$fName $lName'.trim();
    final displayName = fullName.isNotEmpty ? fullName : (username != null && username.isNotEmpty ? username : 'Пользователь');
    final avatar = (item['avatar'] ?? '').toString();
    final isOnline = item['is_online'] == 1 || item['is_online'] == true;
    final lastSeen = item['last_seen']?.toString();

    // 1. Ищем существующий диалог
    Chat? existing;
    for (final c in chatProvider.chats) {
      if (c.isChannel) continue;
      if (c.participantId == targetUserId) {
        existing = c;
        break;
      }
      if (c.isDirect && c.id == targetUserId) {
        existing = c;
        break;
      }
      if (username != null && username.isNotEmpty && c.username != null && c.username!.toLowerCase() == username.toLowerCase()) {
        existing = c;
        break;
      }
    }

    if (existing != null) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chat: existing!)),
        );
      }
      return;
    }

    // 2. Создаем или получаем прямой диалог через API
    try {
      final res = await ApiService.instance.createDirectChat(targetUserId);
      Chat directChat;
      if (res['chat'] is Map<String, dynamic>) {
        directChat = Chat.fromJson(res['chat'] as Map<String, dynamic>);
      } else {
        final newId = res['chatId'] is int
            ? res['chatId'] as int
            : int.tryParse(res['chatId']?.toString() ?? '') ?? targetUserId;
        directChat = Chat(
          id: newId,
          title: displayName,
          type: 'direct',
          avatar: avatar,
          participantId: targetUserId,
          username: username,
          isOnline: isOnline,
          lastSeen: lastSeen,
        );
      }
      await chatProvider.addOrUpdateChat(directChat);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chat: directChat)),
        );
      }
    } catch (_) {
      // Fallback: локальный чат
      final directChat = Chat(
        id: targetUserId,
        title: displayName,
        type: 'direct',
        avatar: avatar,
        participantId: targetUserId,
        username: username,
        isOnline: isOnline,
        lastSeen: lastSeen,
      );
      await chatProvider.addOrUpdateChat(directChat);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chat: directChat)),
        );
      }
    }
  }

  Widget _buildSearchResultTile(
    BuildContext context,
    Map<String, dynamic> item,
    ChatProvider chatProvider,
    int currentUserId,
  ) {
    final isChannel = item['is_channel'] == 1 ||
        item['is_channel'] == true ||
        item['type'] == 'channel';
    final rawVerif = item['verification']?.toString() ??
        item['channel_verification']?.toString() ??
        item['sender_verification']?.toString();
    final uname = (item['username']?.toString() ?? '').toLowerCase();
    final fName = item['first_name']?.toString() ?? '';
    final lName = item['last_name']?.toString() ?? '';
    final rawName = '$fName $lName'.trim();
    final displayName = isChannel
        ? (item['title'] ?? item['name'] ?? item['first_name'] ?? 'Канал').toString()
        : (rawName.isNotEmpty ? rawName : (item['username']?.toString() ?? 'Пользователь'));

    final verification = (rawVerif != null && rawVerif.isNotEmpty && rawVerif != 'none')
        ? rawVerif
        : (uname == 'revs' ? 'dev' :
           ((uname == 'portal' || (isChannel && displayName.toLowerCase().contains('portal'))) ? 'verified' :
            (uname == 'botfather' ? 'verified' : null)));

    final isVerified = VerificationBadge.isVerified(verification);
    final isPremium = item['is_premium'] == true ||
        item['is_premium'] == 1 ||
        item['isPremium'] == true;

    final username = item['username']?.toString() ?? '';
    final avatar = (item['avatar'] ?? '').toString();
    final isOnline = item['is_online'] == 1 || item['is_online'] == true;
    final subCount = item['subscribers_count'] is int
        ? item['subscribers_count'] as int
        : int.tryParse(item['subscribers_count']?.toString() ?? '') ?? 0;

    // Secondary usernames if present
    List<String> secUsernames = [];
    if (item['secondary_usernames'] is List) {
      secUsernames = (item['secondary_usernames'] as List)
          .map((e) => e.toString().trim().replaceFirst(RegExp(r'^@+'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return InkWell(
      onTap: () => _handleSelectSearchResult(context, item, chatProvider, currentUserId),
      splashColor: const Color(0x1AFFFFFF),
      highlightColor: const Color(0x0FFFFFFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Circular Avatar (Left)
            AvatarWidget(
              avatarUrl: avatar,
              title: displayName,
              size: 48,
              isOnline: isOnline,
              isChannel: isChannel,
            ),
            const SizedBox(width: 14),

            // User / Channel details (Right)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Megaphone icon for channels
                      if (isChannel) ...[
                        const Icon(
                          Icons.campaign_outlined,
                          color: Color(0xFF9CA3AF),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                      ],

                      // For users: verification badge (dev or user) is to the LEFT of the nickname
                      if (!isChannel && isVerified) ...[
                        VerificationBadge(verification: verification, size: 18.5),
                        const SizedBox(width: 5),
                      ],

                      // Name / Title
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      // For channels: verification badge is to the RIGHT of the title
                      if (isChannel && isVerified) ...[
                        const SizedBox(width: 5),
                        VerificationBadge(verification: verification, size: 18.5),
                      ],

                      // For users: premium star is to the RIGHT of the nickname
                      if (!isChannel && isPremium) ...[
                        const SizedBox(width: 5),
                        const PremiumBadge(size: 18.5),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),

                  // @username subtitle
                  Row(
                    children: [
                      if (username.isNotEmpty)
                        Text(
                          username.startsWith('@') ? username : '@$username',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF3B98FF),
                          ),
                        ),
                      if (isChannel && subCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• ${UserActivityHelper.formatSubscribers(subCount)}',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12.5,
                            color: Color(0xFF929292),
                          ),
                        ),
                      ] else if (!isChannel && isOnline) ...[
                        const SizedBox(width: 6),
                        const Text(
                          '• в сети',
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12.5,
                            color: AppTheme.statusOnline,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Additional secondary usernames line
                  if (secUsernames.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'а также @${secUsernames.join(', @')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12,
                        color: Color(0xFF929292),
                      ),
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

  String _formatMessageTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);

      if (msgDay == today) {
        return DateFormat('HH:mm').format(dt);
      } else if (today.difference(msgDay).inDays == 1) {
        return 'Вчера';
      } else if (today.difference(msgDay).inDays < 7 && today.difference(msgDay).inDays > 1) {
        const days = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
        return days[dt.weekday - 1];
      } else if (now.year == dt.year) {
        return DateFormat('d MMM', 'ru').format(dt);
      } else {
        return DateFormat('dd.MM.yy').format(dt);
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final user = auth.currentUser;

    final filteredChats = chatProvider.chats.where((c) {
      if (_selectedFolderIndex == 1 && !c.isDirect) return false;
      if (_selectedFolderIndex == 2 && !c.isChannel) return false;
      if (_selectedFolderIndex == 3 && (c.isDirect || c.isChannel)) return false;

      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().replaceFirst(RegExp(r'^@+'), '');
      return c.title.toLowerCase().contains(q) ||
          c.lastMessageText.toLowerCase().contains(q) ||
          c.displayLastMessage.toLowerCase().contains(q) ||
          (c.username != null && c.username!.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // =================================================================
            // HEADER (Centered "Чаты", "Изм." on left, (+) and blue edit on right)
            // =================================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: SizedBox(
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Left: "Изм." edit button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Управление чатами'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Изм.',
                            style: TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Center: "Чаты" title (smaller, centered)
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Чаты',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Right: (+) New Channel / Chat and Blue Pencil Compose button
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => _handleCreateChannel(context),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1C1C1E),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _handleCreateChannel(context),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2A85FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.edit_square,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // =================================================================
            // SEARCH BAR (Telegram iOS rounded search)
            // =================================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF8E8E93),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Поиск',
                          hintStyle: TextStyle(
                            fontFamily: AppTheme.fontText,
                            color: Color(0xFF8E8E93),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        child: const Icon(Icons.cancel_rounded, color: Color(0xFF8E8E93), size: 18),
                      ),
                  ],
                ),
              ),
            ),

            // =================================================================
            // FOLDER TABS (Все, Личные, Каналы, Группы)
            // =================================================================
            if (_searchQuery.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: SizedBox(
                  height: 32,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _folders.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedFolderIndex == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedFolderIndex = index;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1C1C1E) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              _folders[index],
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                color: isSelected ? Colors.white : const Color(0xFF8E8E93),
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 2),

            // =================================================================
            // CHATS LIST OR SEARCH RESULTS
            // =================================================================
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? (_isSearching && _remoteResults.isEmpty && filteredChats.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.accentBlue,
                          ),
                        )
                      : (_remoteResults.isEmpty && filteredChats.isEmpty && !_isSearching)
                          ? Center(
                              child: Text(
                                'Ничего не найдено по запросу «$_searchQuery»',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 95, top: 4),
                              children: [
                                if (_isSearching)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 4),
                                    child: LinearProgressIndicator(
                                      backgroundColor: Colors.transparent,
                                      color: AppTheme.accentBlue,
                                      minHeight: 2,
                                    ),
                                  ),
                                if (_remoteResults.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                                    child: Text(
                                      'ГЛОБАЛЬНЫЙ ПОИСК',
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontDisplay,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  ..._remoteResults.map((item) => _buildSearchResultTile(
                                        context,
                                        item,
                                        chatProvider,
                                        user?.id ?? 0,
                                      )),
                                  const SizedBox(height: 12),
                                ],
                                if (filteredChats.isNotEmpty) ...[
                                  if (_remoteResults.isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                                      child: Text(
                                        'ЧАТЫ',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontDisplay,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6B7280),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ...filteredChats.map((chat) => _buildChatItem(context, chat)),
                                ],
                              ],
                            ))
                  : RefreshIndicator(
                      color: AppTheme.accentBlue,
                      backgroundColor: AppTheme.bgSurface2,
                      onRefresh: () async {
                        await chatProvider.syncBootstrap(onUserLoaded: (u) {
                          auth.setCurrentUser(u);
                        });
                      },
                      child: (chatProvider.isLoading || (chatProvider.chats.isEmpty && chatProvider.isSyncing))
                          ? _buildChatsSkeleton()
                          : (filteredChats.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Нет активных чатов',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      color: AppTheme.textSecondary,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 95, top: 2),
                                  itemCount: filteredChats.length,
                                  itemBuilder: (context, index) {
                                    final chat = filteredChats[index];
                                    return _buildChatItem(context, chat);
                                  },
                                )),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatsSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        final shimmerColor = Colors.white.withOpacity(_shimmerAnimation.value * 0.12);
        final baseShimmer = Colors.white.withOpacity(_shimmerAnimation.value * 0.08);

        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 95, top: 2),
          itemCount: 8,
          itemBuilder: (context, index) {
            final titleWidths = [140.0, 110.0, 160.0, 130.0, 175.0, 120.0, 150.0, 135.0];
            final previewWidths = [210.0, 170.0, 240.0, 185.0, 220.0, 160.0, 230.0, 190.0];
            final tw = titleWidths[index % titleWidths.length];
            final pw = previewWidths[index % previewWidths.length];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Circular Avatar Skeleton
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: shimmerColor,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Texts Skeleton
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          children: [
                            Container(
                              width: tw,
                              height: 14,
                              decoration: BoxDecoration(
                                color: shimmerColor,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 36,
                              height: 11,
                              decoration: BoxDecoration(
                                color: baseShimmer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Subtitle / last message preview
                        Container(
                          width: pw,
                          height: 12,
                          decoration: BoxDecoration(
                            color: baseShimmer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
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

  Widget _buildChatItem(BuildContext context, Chat chat) {
    final isSaved = chat.isSaved;
    final isChannel = chat.isChannel;
    final isVerified = chat.isVerified;
    final isPremium = chat.isPremium;
    final isPinned = chat.isPinned;
    final chatProvider = context.watch<ChatProvider>();
    final isTyping = chatProvider.isUserTyping(chat.id);
    final isOnline = chatProvider.isUserOnline(chat.participantId ?? chat.id) || chat.isOnline;
    final timeStr = _formatMessageTime(chat.lastMessageTime);

    // Pinned chats have darker graphite background (#1C1C1C) matching reference screenshot
    // Unpinned chats have pitch-black background (Colors.black)
    final tileBg = isPinned ? const Color(0xFF1C1C1C) : Colors.black;

    return Container(
      color: tileBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(chat: chat),
                ),
              );
            },
            onLongPress: () => _showChatContextMenu(context, chat),
            splashColor: const Color(0x0FFFFFFF),
            highlightColor: const Color(0x08FFFFFF),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Circular Avatar
                  AvatarWidget(
                    avatarUrl: chat.avatar,
                    title: chat.title,
                    size: 52,
                    isOnline: isOnline,
                    isSaved: isSaved,
                    isChannel: isChannel,
                  ),
                  const SizedBox(width: 13),

                  // Middle info: Title + Last message preview
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Megaphone icon for channels
                            if (isChannel && !isSaved) ...[
                              const Icon(
                                Icons.campaign_outlined,
                                color: Color(0xFF8E8E93),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                            ],

                            // For users: verification badge (dev or user) is to the LEFT of nickname
                            if (!isChannel && isVerified) ...[
                              VerificationBadge(verification: chat.effectiveVerification, size: 18.5),
                              const SizedBox(width: 5),
                            ],

                            // Title
                            Flexible(
                              child: Text(
                                chat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),

                            // For channels: verification badge is to the RIGHT of title
                            if (isChannel && isVerified) ...[
                              const SizedBox(width: 5),
                              VerificationBadge(verification: chat.effectiveVerification, size: 18.5),
                            ],

                            // For users: premium star is to the RIGHT of nickname
                            if (!isChannel && isPremium) ...[
                              const SizedBox(width: 5),
                              const PremiumBadge(size: 18.5),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Last Message preview or typing status
                        isTyping
                            ? const TelegramTypingIndicator(
                                fontSize: 13.5,
                                dotSize: 4.5,
                                color: Color(0xFF2A85FF),
                              )
                            : Text(
                                chat.lastMessageText.isNotEmpty
                                    ? chat.displayLastMessage
                                    : (isSaved ? '😜' : 'Нет сообщений'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14,
                                  height: 1.25,
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Right side: Time strictly at top-right corner, Pin or Unread counter at bottom-right
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Time in the top-right corner
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            color: Color(0xFF8E8E93),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      const SizedBox(height: 6),

                      // Pin icon or Unread counter or chevron
                      if (isPinned)
                        Transform.rotate(
                          angle: 0.785,
                          child: const Icon(
                            Icons.push_pin_rounded,
                            color: Color(0xFF8E8E93),
                            size: 16,
                          ),
                        )
                      else if (chat.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A85FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (isChannel || isSaved)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF4B4B4B),
                          size: 20,
                        )
                      else
                        const SizedBox(height: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 0.6,
            thickness: 0.6,
            color: isPinned ? const Color(0xFF2C2C2E) : const Color(0x14FFFFFF),
            indent: 81,
            endIndent: 0,
          ),
        ],
      ),
    );
  }

  void _handleCreateChannel(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final user = auth.currentUser;
    final isPremium = user?.isPremium == true;
    final maxChannels = isPremium ? 8 : 3;
    final currentUserId = user?.id;

    final ownedCount = chatProvider.chats
        .where((c) => c.isChannel && c.ownerId == currentUserId)
        .length;

    if (ownedCount >= maxChannels) {
      _showChannelLimitDialog(
        context,
        isPremium: isPremium,
        ownedCount: ownedCount,
        maxChannels: maxChannels,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateChannelScreen(
          ownedCount: ownedCount,
          maxChannels: maxChannels,
        ),
      ),
    );
  }

  void _showChannelLimitDialog(
    BuildContext context, {
    required bool isPremium,
    required int ownedCount,
    required int maxChannels,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191919),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1.0),
        ),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isPremium ? const Color(0x263B98FF) : const Color(0x26F59E0B),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPremium ? Icons.campaign_rounded : Icons.star_rounded,
            color: isPremium ? const Color(0xFF3B98FF) : const Color(0xFFF59E0B),
            size: 32,
          ),
        ),
        title: const Text(
          'Лимит каналов',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 19,
          ),
        ),
        content: Text(
          isPremium
              ? 'Вы создали $ownedCount из $maxChannels каналов. Это максимальный лимит для подписки Premium.'
              : 'Вы создали $ownedCount из $maxChannels каналов.\n\nБез подписки Premium доступно создание до 3 каналов. С подпиской Premium вы сможете создать до 8 каналов.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontText,
            color: Color(0xFF929292),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPremium ? const Color(0xFF262933) : const Color(0xFF3B98FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              isPremium ? 'Понятно' : 'Хорошо',
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatContextMenu(BuildContext context, Chat chat) {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final isPremium = authProvider.currentUser?.isPremium == true;
    final isPinned = chat.isPinned;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (dialogContext) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Закрепить / Открепить
                  _buildContextMenuItem(
                    icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    title: isPinned ? 'Открепить' : 'Закрепить',
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      final success = await chatProvider.togglePinChat(chat.id, isPremium);
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isPremium
                                  ? 'Можно закрепить не более 10 чатов'
                                  : 'Бесплатно можно закрепить до 3 чатов. С Portal Premium — до 10 чатов',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Colors.white,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF191919),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),

                  // Divider
                  Container(
                    height: 1,
                    color: const Color(0x14FFFFFF),
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  ),

                  // 2. Удалить
                  _buildContextMenuItem(
                    icon: Icons.delete_outline_rounded,
                    title: 'Удалить',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showDeleteConfirmationDialog(context, chat);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, Chat chat) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (dialogContext) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 290,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Удалить чат?',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Чат с «${chat.title}» будет удален для всех участников без возможности восстановления.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 13.5,
                      color: Color(0xFF929292),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Отмена',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            context.read<ChatProvider>().deleteChat(chat.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Чат удален'),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(milliseconds: 1400),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF453A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Удалить',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContextMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFFF453A) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                color: color,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
