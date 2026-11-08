import 'dart:async';
import 'dart:convert';
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
import '../chat_screen.dart';
import '../create_channel_screen.dart';

class ChatsTab extends StatefulWidget {
  final VoidCallback onOpenProfile;

  const ChatsTab({super.key, required this.onOpenProfile});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;
  bool _isSearching = false;
  List<Map<String, dynamic>> _remoteResults = [];

  @override
  void dispose() {
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
            (item['title'].toString().toLowerCase().contains('канал') ||
                item['title'].toString().toLowerCase().contains('portal')));

    if (isChannel) {
      final chatId = item['chat_id'] is int
          ? item['chat_id'] as int
          : (item['id'] is int ? item['id'] as int : int.tryParse(item['id']?.toString() ?? '') ?? 0);
      final title = (item['title'] ?? item['name'] ?? item['first_name'] ?? 'Канал').toString();
      final avatar = (item['avatar'] ?? '').toString();
      final username = item['username']?.toString();
      final subCount = item['subscribers_count'] is int
          ? item['subscribers_count'] as int
          : int.tryParse(item['subscribers_count']?.toString() ?? '') ?? 0;
      final isSubscribed = item['is_subscribed'] == 1 || item['is_subscribed'] == true;

      Chat? existingChat;
      for (final c in chatProvider.chats) {
        if (c.id == chatId) {
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
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().replaceFirst(RegExp(r'^@+'), '');
      return c.title.toLowerCase().contains(q) ||
          c.lastMessageText.toLowerCase().contains(q) ||
          c.displayLastMessage.toLowerCase().contains(q) ||
          (c.username != null && c.username!.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // =================================================================
            // HEADER (1:1 with Reference Screenshot)
            // =================================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 10),
              child: Row(
                children: [
                  // Title: "Чаты" in SF Pro Display Heavy/Bold
                  const Text(
                    'Чаты',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),

                  // Sun / Theme Toggle (Graphite #191919)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF191919),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.wb_sunny_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Plus (+) New Chat Button (Graphite #191919)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF191919),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => _handleCreateChannel(context),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // AI Assistant / Profile Avatar with online green dot (matching reference)
                  GestureDetector(
                    onTap: widget.onOpenProfile,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFF191919),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'ai',
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF090909),
                                width: 2,
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

            // =================================================================
            // SEARCH BAR (1:1 with Reference Screenshot)
            // =================================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF191919),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF929292),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
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
                            color: Color(0xFF929292),
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
                        child: const Icon(Icons.cancel_rounded, color: Color(0xFF929292), size: 18),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

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
                      child: filteredChats.isEmpty
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
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, Chat chat) {
    final isSaved = chat.isSaved;
    final isChannel = chat.isChannel;
    final isVerified = chat.isVerified;
    final isPremium = chat.isPremium;
    final chatProvider = context.watch<ChatProvider>();
    final isTyping = chatProvider.isUserTyping(chat.id);
    final isOnline = chatProvider.isUserOnline(chat.participantId ?? chat.id) || chat.isOnline;
    final timeStr = _formatMessageTime(chat.lastMessageTime);

    return Column(
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
          splashColor: const Color(0x0FFFFFFF),
          highlightColor: const Color(0x08FFFFFF),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
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
                const SizedBox(width: 14),

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
                              color: Color(0xFF929292),
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
                                fontWeight: FontWeight.w700,
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

                          // Time right next to name (matching reference)
                          if (timeStr.isNotEmpty && !isChannel && !isSaved) ...[
                            const SizedBox(width: 8),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Color(0xFF929292),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),

                      Row(
                        children: [
                          // Last Message preview or typing status
                          Expanded(
                            child: isTyping
                                ? const Text(
                                    'печатает...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w500,
                                      height: 1.25,
                                    ),
                                  )
                                : Text(
                                    chat.lastMessageText.isNotEmpty
                                        ? chat.displayLastMessage
                                        : (isSaved ? '😜' : 'Нет сообщений'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      color: Color(0xFF929292),
                                      fontSize: 14,
                                      height: 1.25,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),

                          // Chevron right for channels / saved, or unread / pin
                          if (chat.isPinned)
                            Transform.rotate(
                              angle: 0.785,
                              child: const Icon(
                                Icons.push_pin_rounded,
                                color: Color(0xFF929292),
                                size: 14,
                              ),
                            )
                          else if (chat.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Color(0xFF090909),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else if (isChannel || isSaved)
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF4B4B4B),
                              size: 20,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 0.6,
          color: Color(0x14FFFFFF),
          indent: 82,
          endIndent: 0,
        ),
      ],
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
}
