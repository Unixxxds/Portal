import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/user_activity_helper.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/user_gift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';
import '../widgets/formatted_message_text.dart';
import '../widgets/gift_detail_modal.dart';
import '../widgets/gift_visuals.dart';
import '../widgets/photo_picker_bottom_sheet.dart';
import '../widgets/send_gift_modal.dart';
import '../widgets/telegram_text_selection_toolbar.dart';
import '../widgets/voice_message_bubble.dart';
import 'user_profile_screen.dart';
import 'post_comments_screen.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTypingSent = false;
  Message? _replyingToMessage;
  Message? _editingMessage;
  late bool _isSubscribed;
  late int _subscribersCount;
  bool _isSubscribing = false;
  String? _liveVerification;
  bool? _liveIsPremium;
  int? _channelOwnerId;
  bool _canPostToChannel = false;
  bool _isSendingSticker = false;
  final Set<int> _viewedMessageIds = {};
  int _lastRenderedMessageCount = 0;
  bool _hasInitiallyScrolled = false;

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  int _recordElapsedMs = 0;
  Timer? _recordTimer;
  double _cancelDragOffset = 0.0;
  String? _currentRecordingPath;
  late final AnimationController _rippleController;
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _blinkAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_blinkController);
    _isSubscribed = widget.chat.isSubscribed;
    _subscribersCount = widget.chat.subscribersCount;
    _liveVerification = widget.chat.effectiveVerification;
    _liveIsPremium = widget.chat.isPremium;
    _channelOwnerId = widget.chat.ownerId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().loadPinnedMessage(widget.chat.id);
        final currentUserId = context.read<AuthProvider>().currentUser?.id;
        if (currentUserId != null && _channelOwnerId == currentUserId) {
          setState(() {
            _canPostToChannel = true;
          });
        }
      }
    });
    if (widget.chat.isChannel) {
      ApiService.instance.getChannel(widget.chat.id).then((data) {
        if (data != null && mounted) {
          final verif = data['verification']?.toString();
          final rawOwnerId = data['owner_id'];
          final ownerId = rawOwnerId is int ? rawOwnerId : int.tryParse(rawOwnerId?.toString() ?? '');
          final currentUserId = context.read<AuthProvider>().currentUser?.id;
          final isOwner = (ownerId != null && currentUserId != null && ownerId == currentUserId) ||
              (widget.chat.ownerId != null && currentUserId != null && widget.chat.ownerId == currentUserId);
          final canSend = data['can_send_messages'] == true || data['can_send_messages'] == 1 || isOwner;

          setState(() {
            if (data['is_subscribed'] != null) {
              _isSubscribed = data['is_subscribed'] == 1 || data['is_subscribed'] == true;
            }
            if (data['subscribers_count'] != null) {
              _subscribersCount = int.tryParse(data['subscribers_count'].toString()) ?? _subscribersCount;
            }
            if (ownerId != null) {
              _channelOwnerId = ownerId;
            }
            if (isOwner || canSend) {
              _canPostToChannel = true;
            }
            if (verif != null && verif.isNotEmpty && verif != 'none') {
              _liveVerification = verif;
            }
          });
          if (verif != null && verif.isNotEmpty && verif != 'none') {
            context.read<ChatProvider>().updateChatVerification(
              chatId: widget.chat.id,
              verification: verif,
            );
          }
        }
      }).catchError((_) {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkUserPresence();
      await context.read<ChatProvider>().openChat(widget.chat.id);
      _jumpToBottomFast();
      Future.delayed(const Duration(milliseconds: 60), _jumpToBottomFast);
      Future.delayed(const Duration(milliseconds: 180), _jumpToBottomFast);
      Future.delayed(const Duration(milliseconds: 350), _jumpToBottomFast);
    });
  }

  Future<void> _checkUserPresence() async {
    if (widget.chat.isSaved || widget.chat.isChannel) return;
    final targetId = widget.chat.participantId ?? widget.chat.id;
    try {
      final profile = await ApiService.instance.getUserProfile(targetId);
      if (profile != null && mounted) {
        final isOnline = profile['is_online'] == true || profile['is_online'] == 1;
        final lastSeen = profile['last_seen']?.toString();
        final pId = profile['id'] is int ? profile['id'] as int : targetId;
        final verif = profile['verification']?.toString();
        final isPrem = profile['is_premium'] == true || profile['is_premium'] == 1;

        setState(() {
          if (verif != null && verif.isNotEmpty && verif != 'none') {
            _liveVerification = verif;
          }
          if (profile['is_premium'] != null) {
            _liveIsPremium = isPrem;
          }
        });

        context.read<ChatProvider>().updatePresence(
          userId: pId,
          chatId: widget.chat.id,
          isOnline: isOnline,
          lastSeen: lastSeen,
          verification: verif,
          isPremium: isPrem,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isTypingSent) {
      WebSocketService.instance.sendTyping(widget.chat.id, isTyping: false);
    }
    _textController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _rippleController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  void _jumpToBottomFast() {
    if (!mounted || !_scrollController.hasClients) return;
    try {
      final max = _scrollController.position.maxScrollExtent;
      if (_scrollController.offset < max - 2) {
        _scrollController.jumpTo(max);
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleTextChange(String val) {
    setState(() {}); // Updates send button state
    if (val.trim().isNotEmpty) {
      if (!_isTypingSent) {
        _isTypingSent = true;
        WebSocketService.instance.sendTyping(widget.chat.id, isTyping: true);
        Future.delayed(const Duration(seconds: 3), () {
          _isTypingSent = false;
        });
      }
    } else {
      if (_isTypingSent) {
        _isTypingSent = false;
        WebSocketService.instance.sendTyping(widget.chat.id, isTyping: false);
      }
    }
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_isTypingSent) {
      _isTypingSent = false;
      WebSocketService.instance.sendTyping(widget.chat.id, isTyping: false);
    }
    _textController.clear();

    if (_editingMessage != null) {
      final editId = _editingMessage!.id;
      setState(() {
        _editingMessage = null;
      });
      final provider = context.read<ChatProvider>();
      await provider.editMessage(widget.chat.id, editId, text);
      return;
    }

    final replyId = _replyingToMessage?.id;
    setState(() {
      _replyingToMessage = null;
    });
    final provider = context.read<ChatProvider>();
    await provider.sendMessage(widget.chat.id, text, replyToMessageId: replyId);
    _scrollToBottom();
  }

  Future<void> _sendGreetingSticker() async {
    if (_isSendingSticker) return;
    _isSendingSticker = true;
    final provider = context.read<ChatProvider>();
    const payload = '[PORTAL_STICKER]:{"asset":"lib/assets/sticker/sticker.gif"}';
    try {
      await provider.sendMessage(widget.chat.id, payload);
      _scrollToBottom();
    } catch (_) {} finally {
      if (mounted) {
        _isSendingSticker = false;
      }
    }
  }

  Future<bool> _checkMicrophonePermission() async {
    if (Platform.isWindows || Platform.isLinux) {
      return true;
    }

    try {
      // 1. Native recorder permission check (directly invokes AVAudioSession on iOS)
      final hasRecPerm = await _audioRecorder.hasPermission();
      if (hasRecPerm) return true;
    } catch (_) {}

    try {
      // 2. Permission handler request & check
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      final result = await Permission.microphone.request();
      if (result.isGranted) return true;

      if (result.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Доступ к микрофону отключен в настройках устройства'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Настройки',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return false;
      }
    } catch (_) {}

    return false;
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;

    final hasPermission = await _checkMicrophonePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Для записи голосовых сообщений разрешите доступ к микрофону'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = filePath;

      const recordConfig = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );

      await _audioRecorder.start(recordConfig, path: filePath);

      HapticFeedback.mediumImpact();

      setState(() {
        _isRecordingVoice = true;
        _recordElapsedMs = 0;
        _cancelDragOffset = 0.0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
        if (!mounted || !_isRecordingVoice) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordElapsedMs += 25;
        });
      });
    } catch (e) {
      debugPrint('Error starting voice recording: $e');
    }
  }

  void _updateVoiceDrag(double dragDx) {
    if (!_isRecordingVoice) return;
    setState(() {
      _cancelDragOffset = dragDx.clamp(-120.0, 0.0);
    });
  }

  Future<void> _stopVoiceRecording({required bool send}) async {
    if (!_isRecordingVoice) return;

    final elapsed = _recordElapsedMs;
    final isCancelled = !send || _cancelDragOffset < -70;

    _recordTimer?.cancel();
    _recordTimer = null;

    setState(() {
      _isRecordingVoice = false;
      _cancelDragOffset = 0.0;
      _recordElapsedMs = 0;
    });

    HapticFeedback.lightImpact();

    try {
      final path = await _audioRecorder.stop();
      final targetPath = path ?? _currentRecordingPath;

      if (isCancelled || elapsed < 700 || targetPath == null) {
        if (targetPath != null) {
          try {
            final f = File(targetPath);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
        if (elapsed < 700 && !isCancelled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Слишком короткое голосовое сообщение'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(milliseconds: 1200),
            ),
          );
        }
        return;
      }

      final file = File(targetPath);
      final durationSec = (elapsed / 1000).round().clamp(1, 9999);
      final replyId = _replyingToMessage?.id;

      if (mounted) {
        setState(() {
          _replyingToMessage = null;
        });
        _scrollToBottom();
        final provider = context.read<ChatProvider>();
        provider.sendVoiceMessage(
          widget.chat.id,
          voiceFile: file,
          durationSec: durationSec,
          replyToMessageId: replyId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка отправки голосового сообщения: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.destructive,
          ),
        );
      }
    }
  }

  String _formatRecordingTime(int ms) {
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s:$cs';
  }

  void _scrollToMessage(int messageId) {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx != -1 && _scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      final target = (idx / (messages.length > 0 ? messages.length : 1)) * max;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _formatMessageTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '00:00';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '00:00';
    }
  }

  String _formatCommentsCount(int count) {
    if (count <= 0) return 'Прокомментировать';
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$count комментариев';
    if (mod10 == 1) return '$count комментарий';
    if (mod10 >= 2 && mod10 <= 4) return '$count комментария';
    return '$count комментариев';
  }

  String _formatViewsCount(int count) {
    final c = count > 0 ? count : 1;
    if (c >= 1000000) {
      return '${(c / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    }
    if (c >= 1000) {
      return '${(c / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    }
    return '$c';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final currentUserId = auth.currentUser?.id ?? 0;
    final messages = chatProvider.activeMessages;

    if (messages.isNotEmpty) {
      if (!_hasInitiallyScrolled || _lastRenderedMessageCount != messages.length) {
        final wasInitial = !_hasInitiallyScrolled;
        _hasInitiallyScrolled = true;
        _lastRenderedMessageCount = messages.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToBottomFast();
          if (wasInitial) {
            Future.delayed(const Duration(milliseconds: 60), _jumpToBottomFast);
            Future.delayed(const Duration(milliseconds: 180), _jumpToBottomFast);
            Future.delayed(const Duration(milliseconds: 350), _jumpToBottomFast);
          }
        });
      }
    }

    final isTyping = chatProvider.isUserTyping(widget.chat.id);
    final currentChat = chatProvider.chats.firstWhere(
      (c) => c.id == widget.chat.id,
      orElse: () => widget.chat,
    );
    final isChannelOwner = currentChat.isChannel &&
        (_canPostToChannel ||
         (currentUserId > 0 &&
          ((_channelOwnerId != null && _channelOwnerId == currentUserId) ||
           (currentChat.ownerId != null && currentChat.ownerId == currentUserId) ||
           (widget.chat.ownerId != null && widget.chat.ownerId == currentUserId))));
    final pId = currentChat.participantId ?? widget.chat.participantId;
    final isOnline = (pId != null && chatProvider.isUserOnline(pId)) ||
        chatProvider.isUserOnline(currentChat.id) ||
        chatProvider.isUserOnline(widget.chat.id) ||
        currentChat.isOnline ||
        widget.chat.isOnline;

    final pinnedMessage = chatProvider.getPinnedMessage(currentChat.id);
    final hasPinned = pinnedMessage != null;
    final contentTopPadding = MediaQuery.of(context).padding.top + 68 + (hasPinned ? 52.0 : 0.0);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          context.read<ChatProvider>().closeChat();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppTheme.appBg,
        appBar: _buildLiquidGlassHeader(isTyping, currentChat, isOnline),
        body: Stack(
          children: [
            Column(
              children: [
                // Messages List
                Expanded(
                  child: messages.isEmpty
                      ? Padding(
                          padding: EdgeInsets.only(top: contentTopPadding),
                          child: Center(
                            child: _buildEmptyChatPlaceholder(),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.only(
                            top: contentTopPadding,
                            bottom: 12,
                            left: 14,
                            right: 14,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final prevMsg = index > 0 ? messages[index - 1] : null;
                            final showDate = prevMsg == null || _getDayKey(msg.createdAt) != _getDayKey(prevMsg.createdAt);

                            Widget cardWidget;
                            if (currentChat.isChannel) {
                              cardWidget = _buildChannelPostCard(msg);
                            } else {
                              final isMe = msg.senderId == currentUserId;
                              cardWidget = _buildMessageBubble(msg, isMe);
                            }

                            if (showDate) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildDateBadge(_formatDateBadge(msg.createdAt)),
                                  cardWidget,
                                ],
                              );
                            }
                            return cardWidget;
                          },
                        ),
                ),

                // Floating Input Bar or Channel Subscribe Bar
                if (currentChat.isChannel && !isChannelOwner)
                  _buildChannelSubscribeBar()
                else
                  _buildFloatingInputBar(),
              ],
            ),

            // Pinned Message Floating Bar
            if (pinnedMessage != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 58,
                left: 14,
                right: 14,
                child: _buildPinnedMessageBar(pinnedMessage),
              ),
          ],
        ),
      ),
    );
  }

  bool _isGiftMessage(String text) {
    final t = text.trim();
    return t.startsWith('[PORTAL_GIFT]:') ||
        (t.startsWith('{') && t.contains('"type":"gift_card"'));
  }

  Widget _buildEmptyChatPlaceholder() {
    if (widget.chat.isChannel) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWidget(
            avatarUrl: widget.chat.avatar,
            title: widget.chat.title,
            size: 68,
            isChannel: true,
          ),
          const SizedBox(height: 14),
          Text(
            !widget.chat.title.startsWith('📢')
                ? '📢 ${widget.chat.title}'
                : widget.chat.title,
            style: const TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'В этом канале пока нет постов',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 13.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    if (widget.chat.isSaved) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWidget(
            avatarUrl: widget.chat.avatar,
            title: widget.chat.title,
            size: 68,
            isSaved: true,
          ),
          const SizedBox(height: 14),
          const Text(
            'Избранное',
            style: const TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ваше личное хранилище заметок и файлов',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 13.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    // Direct User Dialogue Greeting Card (1:1 with Screenshot)
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              constraints: const BoxConstraints(maxWidth: 320),
              decoration: BoxDecoration(
                color: const Color(0x3312151D),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: const Color(0x1AFFFFFF),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Здесь пока ничего нет...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Отправьте сообщение или\nнажмите на приветствие ниже.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFC0C0C0),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _sendGreetingSticker,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Image.asset(
                        'lib/assets/sticker/sticker.gif',
                        width: 140,
                        height: 140,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PINNED MESSAGE FLOATING BAR
  // ===========================================================================
  Widget _buildPinnedMessageBar(Message pinned) {
    String textPreview = pinned.text;
    if (_isGiftMessage(textPreview)) {
      textPreview = '🎁 Подарок';
    } else if (textPreview.startsWith('[PORTAL_STICKER]:') || textPreview.contains('[PORTAL_STICKER]:')) {
      textPreview = '✨ Стикер';
    } else if (textPreview.startsWith('[PORTAL_PHOTO]:')) {
      textPreview = '📷 Фотография';
    }
    textPreview = textPreview.replaceAll('\n', ' ');

    return GestureDetector(
      onTap: () => _scrollToMessage(pinned.id),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF191919),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.push_pin_rounded,
              color: Colors.white,
              size: 17,
            ),
            const SizedBox(width: 8),
            Container(
              width: 2.5,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Закрепленное сообщение',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    textPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 11.5,
                      color: Color(0xFF929292),
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                context.read<ChatProvider>().unpinMessage(widget.chat.id);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0x1AFFFFFF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF929292),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FLOATING CAPSULE HEADER (NO BLACK UNDERLAY)
  // ===========================================================================
  PreferredSizeWidget _buildLiquidGlassHeader(bool isTyping, Chat chat, bool isOnline) {
    final statusText = isTyping
        ? 'печатает...'
        : (chat.isChannel
            ? UserActivityHelper.formatSubscribers(_subscribersCount)
            : UserActivityHelper.formatActivity(
                isOnline: isOnline,
                lastSeen: chat.lastSeen,
                isChannel: chat.isChannel,
              ));
    final statusColor = isTyping
        ? Colors.white
        : (isOnline ? AppTheme.statusOnline : const Color(0xFF929292));

    final rawTitle = chat.title.startsWith('📢') ? chat.title.substring(1).trim() : chat.title;
    final displayTitle = rawTitle.isEmpty ? (chat.isChannel ? 'Канал' : 'Чат') : rawTitle;

    final effectiveVerif = (_liveVerification != null && _liveVerification != 'none' && _liveVerification!.isNotEmpty)
        ? _liveVerification
        : chat.effectiveVerification;
    final isVerif = VerificationBadge.isVerified(effectiveVerif);
    final isPrem = _liveIsPremium ?? chat.isPremium;

    return PreferredSize(
      preferredSize: const Size.fromHeight(62),
      child: Container(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 1. Circular Back Button (Left)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        context.read<ChatProvider>().closeChat();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0x1AFFFFFF),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Centered Maximally Rounded Floating Capsule Pill
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {
                        if (chat.isChannel) {
                          _showChannelInfoModal(context, chat);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(chat: chat),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 46,
                        constraints: BoxConstraints(
                          minWidth: 140,
                          maxWidth: MediaQuery.of(context).size.width - (chat.isChannel ? 180 : 124),
                        ),
                        padding: const EdgeInsets.fromLTRB(5, 4, 14, 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF191919),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0x1AFFFFFF),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AvatarWidget(
                              avatarUrl: chat.avatar,
                              title: displayTitle,
                              size: 36,
                              isOnline: isOnline,
                              isSaved: chat.isSaved,
                              isChannel: chat.isChannel,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // For users: verification badge (dev or user) is to the LEFT of nickname
                                      if (!chat.isChannel && isVerif) ...[
                                        VerificationBadge(verification: effectiveVerif, size: 18.0),
                                        const SizedBox(width: 5),
                                      ],

                                      Flexible(
                                        child: Text(
                                          displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontDisplay,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                            color: Colors.white,
                                            height: 1.15,
                                          ),
                                        ),
                                      ),

                                      // For channels: verification badge is to the RIGHT of title
                                      if (chat.isChannel && isVerif) ...[
                                        const SizedBox(width: 5),
                                        VerificationBadge(verification: effectiveVerif, size: 18.0),
                                      ],

                                      // For users: premium star is to the RIGHT of nickname
                                      if (!chat.isChannel && isPrem) ...[
                                        const SizedBox(width: 5),
                                        const PremiumBadge(size: 18.0),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: statusColor,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. Actions (Right)
                  Align(
                    alignment: Alignment.centerRight,
                    child: chat.isChannel
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _showChannelInfoModal(context, chat),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF191919),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0x1AFFFFFF),
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showChannelInfoModal(context, chat),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF191919),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0x1AFFFFFF),
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(chat: chat),
                                ),
                              );
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF191919),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0x1AFFFFFF),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DATE BADGE HELPERS
  // ===========================================================================
  String _getDayKey(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}-${dt.month}-${dt.day}';
    } catch (_) {
      return '';
    }
  }

  String _formatDateBadge(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Недавно';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = [
        'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
        'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
      ];
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildDateBadge(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF191919),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0x1AFFFFFF),
            width: 0.8,
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF929292),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // CHANNEL INFO MODAL (Sheet with avatar on the right, title, and @username)
  // ===========================================================================
  void _showChannelInfoModal(BuildContext context, Chat chat) {
    final rawTitle = chat.title.startsWith('📢') ? chat.title.substring(1).trim() : chat.title;
    final channelTitle = rawTitle.isEmpty ? 'Канал' : rawTitle;
    final channelUsername = (chat.username != null && chat.username!.isNotEmpty)
        ? (chat.username!.startsWith('@') ? chat.username! : '@${chat.username!}')
        : (channelTitle.toLowerCase().contains('portal') ? '@portal' : '@channel');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border.all(
                  color: const Color(0x1AFFFFFF),
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 25,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header Row: Channel Name on the left, Avatar on the right (1:1 with user prompt)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        channelTitle,
                                        style: const TextStyle(
                                          fontFamily: AppTheme.fontDisplay,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.4,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (chat.isVerified || VerificationBadge.isVerified(_liveVerification)) ...[
                                      const SizedBox(width: 6),
                                      VerificationBadge(
                                        verification: (_liveVerification != null && _liveVerification != 'none' && _liveVerification!.isNotEmpty)
                                            ? _liveVerification
                                            : chat.effectiveVerification,
                                        size: 22,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  UserActivityHelper.formatSubscribers(_subscribersCount),
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF929292),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          AvatarWidget(
                            avatarUrl: chat.avatar,
                            title: channelTitle,
                            size: 64,
                            isChannel: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Special Section: @username
                      const Text(
                        'ИМЯ КАНАЛА',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF929292),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0x1AFFFFFF),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (chat.isVerified || VerificationBadge.isVerified(_liveVerification)) ...[
                                  VerificationBadge(
                                    verification: (_liveVerification != null && _liveVerification != 'none' && _liveVerification!.isNotEmpty)
                                        ? _liveVerification
                                        : chat.effectiveVerification,
                                    size: 18.5,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  channelUsername,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: channelUsername));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Ссылка на канал скопирована'),
                                        duration: Duration(seconds: 1),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  child: const Icon(
                                    Icons.copy_rounded,
                                    color: Color(0xFF929292),
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                            if (chat.secondaryUsernames.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'а также @${chat.secondaryUsernames.join(', @')}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 13,
                                  color: Color(0xFF929292),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Description Section (if present)
                      if (chat.description != null && chat.description!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'ОПИСАНИЕ',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF929292),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0x1AFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            chat.description!,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 14.5,
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Owner banner OR Subscribe/Unsubscribe Button inside modal
                      Builder(
                        builder: (btnCtx) {
                          final currentUserId = btnCtx.read<AuthProvider>().currentUser?.id;
                          final isOwner = _canPostToChannel ||
                              (currentUserId != null &&
                               ((_channelOwnerId != null && _channelOwnerId == currentUserId) ||
                                (chat.ownerId != null && chat.ownerId == currentUserId) ||
                                (widget.chat.ownerId != null && widget.chat.ownerId == currentUserId)));

                          if (isOwner) {
                            return Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0x1A3B98FF),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0x333B98FF), width: 1.0),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shield_outlined, size: 19, color: Color(0xFF3B98FF)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Вы владелец этого канала',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontDisplay,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF3B98FF),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubscribing
                                  ? null
                                  : () async {
                                      await _toggleSubscribe();
                                      setModalState(() {});
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSubscribed ? const Color(0xFF242424) : Colors.white,
                                foregroundColor: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  side: _isSubscribed
                                      ? const BorderSide(color: Color(0x1AFFFFFF), width: 1.0)
                                      : BorderSide.none,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isSubscribed ? Icons.notifications_off_outlined : Icons.add_rounded,
                                    size: 19,
                                    color: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isSubscribed ? 'Отписаться от канала' : 'Подписаться на канал',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontDisplay,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // CHANNEL POST CARD (1:1 with Reference Screenshot)
  // ===========================================================================
  Widget _buildChannelPostCard(Message msg) {
    if (msg.id > 0 && !_viewedMessageIds.contains(msg.id)) {
      _viewedMessageIds.add(msg.id);
      ApiService.instance.viewMessage(msg.id).then((serverViews) {
        if (serverViews != null && mounted) {
          context.read<ChatProvider>().updateMessageViews(msg.id, serverViews);
        }
      }).catchError((_) {});
    }

    final channelTitle = widget.chat.title.startsWith('📢')
        ? widget.chat.title.substring(2).trim()
        : widget.chat.title;
    final channelUsername = widget.chat.username != null && widget.chat.username!.isNotEmpty
        ? '@${widget.chat.username!.replaceFirst('@', '')}'
        : '@channel';

    return GestureDetector(
      onLongPress: () => _showMessageContextMenu(msg),
      onSecondaryTap: () => _showMessageContextMenu(msg),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF191919),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0x1AFFFFFF),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Post Header: Avatar + Channel Title + @username
          Row(
            children: [
              AvatarWidget(
                avatarUrl: widget.chat.avatar,
                title: widget.chat.title,
                size: 36,
                isChannel: true,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        channelTitle,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.chat.isVerified || VerificationBadge.isVerified(_liveVerification)) ...[
                        const SizedBox(width: 5),
                        VerificationBadge(
                          verification: (_liveVerification != null && _liveVerification != 'none' && _liveVerification!.isNotEmpty)
                              ? _liveVerification
                              : widget.chat.effectiveVerification,
                          size: 18.0,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    channelUsername,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF929292),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2. Post Content (Text, Photo, or Gift)
          _buildPostContent(msg),

          const SizedBox(height: 10),

          // 3. Reactions Pill Row
          _buildPostReactions(msg),

          const SizedBox(height: 10),

          // 4. Bottom Divider and Unified Actions Row
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 10),

          Row(
            children: [
              // Comments action on the left
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostCommentsScreen(
                        channel: widget.chat,
                        post: msg,
                        onCommentsCountChanged: (newCount) {
                          context.read<ChatProvider>().updateMessageCommentsCount(msg.id, newCount);
                          setState(() {});
                        },
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCommentsCount(msg.commentsCount),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFF929292),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Views counter & Time in the lower-right corner of the post card
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    size: 13,
                    color: Color(0xFF929292),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatViewsCount(msg.viewsCount),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 12,
                      color: Color(0xFF929292),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatMessageTime(msg.createdAt),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 12,
                      color: Color(0xFF929292),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildPostContent(Message msg) {
    final text = msg.text.trim();

    // 1. Photo in Channel Post
    if (text.startsWith('[PORTAL_PHOTO]:') || text.contains('[PORTAL_PHOTO]:')) {
      List<String> rawUrls = [];
      String? caption;
      try {
        final startIdx = text.indexOf('{');
        final endIdx = text.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          final jsonStr = text.substring(startIdx, endIdx + 1);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (map['urls'] is List) {
            rawUrls = (map['urls'] as List)
                .map((e) => e.toString())
                .where((u) => u.isNotEmpty)
                .toList();
          } else if (map['url'] != null && map['url'].toString().isNotEmpty) {
            rawUrls = [map['url'].toString()];
          }
          caption = map['caption']?.toString();
        }
      } catch (_) {}

      if (rawUrls.isEmpty) {
        final urlMatch = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(text);
        if (urlMatch != null) rawUrls.add(urlMatch.group(1)!);
      }
      if (caption == null) {
        final capMatch = RegExp(r'"caption"\s*:\s*"([^"]*)"').firstMatch(text);
        caption = capMatch?.group(1);
      }

      final List<String> fullUrls =
          rawUrls.map((u) => AppConstants.formatMediaUrl(u)).toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fullUrls.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: fullUrls.length > 1
                  ? _buildCollage(
                      fullUrls,
                      MediaQuery.of(context).size.width - 32,
                      null,
                    )
                  : GestureDetector(
                      onTap: () => _showFullscreenGallery(fullUrls, 0),
                      child: Image.network(
                        fullUrls.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: const Color(0xFF222222),
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 160,
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, color: Color(0xFF929292), size: 36),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            if (caption != null && caption.isNotEmpty) const SizedBox(height: 10),
          ],
          if (caption != null && caption.isNotEmpty)
            Text(
              caption,
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                color: Colors.white,
                fontSize: 14.5,
                height: 1.38,
              ),
            ),
        ],
      );
    }

    // 2. Gift in Channel Post
    if (_isGiftMessage(text) || text.contains('[PORTAL_GIFT]:')) {
      return _buildPortalGiftBubble(msg, false);
    }

    return Text(
      msg.text,
      style: const TextStyle(
        fontFamily: AppTheme.fontText,
        color: Colors.white,
        fontSize: 14.5,
        height: 1.38,
      ),
    );
  }

  Widget _buildPostReactions(Message msg) {
    final textLower = msg.text.toLowerCase();
    final hasReactions = msg.text.contains('🔥') ||
        msg.text.contains('🚀') ||
        textLower.contains('реакци') ||
        textLower.contains('devil') ||
        textLower.contains('обновлен');

    if (!hasReactions) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _buildReactionPill('🔥', 7),
          _buildReactionPill('🚀', 5),
        ],
      ),
    );
  }

  Widget _buildReactionPill(String emoji, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CHANNEL SUBSCRIBE BOTTOM BAR (Ultra-rounded button)
  // ===========================================================================
  Widget _buildChannelSubscribeBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _isSubscribing ? null : _toggleSubscribe,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isSubscribed ? const Color(0xFF191919) : Colors.white,
            foregroundColor: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: _isSubscribed ? const BorderSide(color: Color(0x1AFFFFFF), width: 1.0) : BorderSide.none,
            ),
          ),
          child: _isSubscribing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isSubscribed ? Icons.notifications_off_outlined : Icons.add_rounded,
                      size: 19,
                      color: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSubscribed ? 'Отписаться' : 'Подписаться',
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _isSubscribed ? const Color(0xFF929292) : const Color(0xFF090909),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _toggleSubscribe() async {
    if (_isSubscribing) return;
    setState(() => _isSubscribing = true);

    final nextSub = !_isSubscribed;
    final delta = nextSub ? 1 : -1;
    final nextCount = (_subscribersCount + delta) < 0 ? 0 : (_subscribersCount + delta);

    setState(() {
      _isSubscribed = nextSub;
      _subscribersCount = nextCount;
    });

    try {
      await ApiService.instance.toggleChannelSubscription(widget.chat.id, !nextSub);
      final updatedChat = widget.chat.copyWith(
        isSubscribed: nextSub,
        subscribersCount: nextCount,
      );
      await context.read<ChatProvider>().addOrUpdateChat(updatedChat);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextSub ? 'Вы подписались на канал' : 'Вы отписались от канала'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Subscription toggle error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubscribing = false);
      }
    }
  }

  // ===========================================================================
  // MESSAGE BUBBLE
  // ===========================================================================
  Widget _buildMessageBubble(Message msg, bool isMe) {
    if (_isGiftMessage(msg.text)) {
      return _buildPortalGiftBubble(msg, isMe);
    }
    if (msg.text.trim().startsWith('[PORTAL_STICKER]:') || msg.text.contains('[PORTAL_STICKER]:')) {
      return _buildPortalStickerBubble(msg, isMe);
    }
    if (msg.text.trim().startsWith('[PORTAL_PHOTO]:')) {
      return _buildPortalPhotoBubble(msg, isMe);
    }
    if (msg.text.trim().startsWith('[PORTAL_VOICE]:')) {
      return VoiceMessageBubble(
        message: msg,
        isMe: isMe,
        onLongPress: () => _showMessageContextMenu(msg),
        onCancel: msg.isPending
            ? () => context.read<ChatProvider>().cancelPendingMessage(widget.chat.id, msg.id)
            : null,
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageContextMenu(msg),
        onSecondaryTap: () => _showMessageContextMenu(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
            minWidth: 70,
          ),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF2A2A2A) : const Color(0xFF191919),
            borderRadius: BorderRadius.circular(18),
            border: isMe ? null : Border.all(color: const Color(0x14FFFFFF), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Replied Message Quote (if any)
              if (msg.replyToMessageId != null) ...[
                _buildReplyPreviewInBubble(msg.replyToMessageId!),
                const SizedBox(height: 6),
              ],

              // Sender name if in group
              if (!isMe && msg.senderName.isNotEmpty && !widget.chat.isDirect) ...[
                Text(
                  msg.senderName,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
              ],

              // Message text
              FormattedMessageText(
                text: msg.text,
                messageId: msg.id,
              ),
              const SizedBox(height: 4),

              // Time and Checkmark inside bubble at bottom right
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (msg.isEdited) ...[
                    const Text(
                      'изменено ',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 11,
                        color: Color(0xFF929292),
                      ),
                    ),
                  ],
                  Text(
                    _formatMessageTime(msg.createdAt),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 11.5,
                      color: Color(0xFF929292),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    if (msg.isPending)
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: Color(0xFF929292),
                        ),
                      )
                    else
                      Icon(
                        msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
                        size: 14,
                        color: const Color(0xFF929292),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reply preview banner inside the message bubble
  Widget _buildReplyPreviewInBubble(int replyToId) {
    final messages = context.read<ChatProvider>().activeMessages;
    Message? targetMsg;
    for (final m in messages) {
      if (m.id == replyToId) {
        targetMsg = m;
        break;
      }
    }

    final currentUserId = context.read<AuthProvider>().currentUser?.id ?? 0;
    final authorName = targetMsg != null
        ? (targetMsg.senderName.isNotEmpty
            ? targetMsg.senderName
            : (targetMsg.senderId == currentUserId
                ? 'Вы'
                : widget.chat.title))
        : 'Ответ';

    String previewText = targetMsg?.text ?? 'Сообщение #$replyToId';
    if (_isGiftMessage(previewText)) {
      previewText = '🎁 Подарок';
    } else if (previewText.startsWith('[PORTAL_STICKER]:') || previewText.contains('[PORTAL_STICKER]:')) {
      previewText = '✨ Стикер';
    } else if (previewText.startsWith('[PORTAL_PHOTO]:')) {
      previewText = '📷 Фотография';
    }
    previewText = previewText.replaceAll('\n', ' ');

    return GestureDetector(
      onTap: () {
        if (targetMsg != null) {
          _scrollToMessage(targetMsg.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: Colors.white.withOpacity(0.85),
              width: 2.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 11.5,
                color: Color(0xFFB0B0B0),
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MESSAGE CONTEXT MENU POPUP (1:1 with Reference Screenshot)
  // ===========================================================================
  void _showMessageContextMenu(Message msg) {
    final chatProvider = context.read<ChatProvider>();
    final currentPinned = chatProvider.getPinnedMessage(widget.chat.id);
    final isCurrentlyPinned = currentPinned?.id == msg.id;

    String cleanText = msg.text;
    if (_isGiftMessage(cleanText)) {
      cleanText = 'Подарок';
    } else if (cleanText.startsWith('[PORTAL_PHOTO]:')) {
      cleanText = 'Фотография';
    }

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
                  // 1. Ответить
                  _buildContextMenuItem(
                    icon: Icons.reply_rounded,
                    title: 'Ответить',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      setState(() {
                        _replyingToMessage = msg;
                        _editingMessage = null;
                      });
                    },
                  ),

                  // 2. Редактировать
                  _buildContextMenuItem(
                    icon: Icons.edit_outlined,
                    title: 'Редактировать',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      setState(() {
                        _editingMessage = msg;
                        _replyingToMessage = null;
                        _textController.text = cleanText;
                        _textController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _textController.text.length),
                        );
                      });
                    },
                  ),

                  // 3. Закрепить / Открепить
                  _buildContextMenuItem(
                    icon: Icons.push_pin_outlined,
                    title: isCurrentlyPinned ? 'Открепить' : 'Закрепить',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      chatProvider.togglePinMessage(widget.chat.id, msg.id);
                    },
                  ),

                  // 3. Копировать текст
                  _buildContextMenuItem(
                    icon: Icons.copy_rounded,
                    title: 'Копировать текст',
                    onTap: () {
                      Navigator.pop(dialogContext);
                      Clipboard.setData(ClipboardData(text: cleanText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Текст скопирован'),
                          duration: Duration(milliseconds: 1400),
                          backgroundColor: Color(0xFF191919),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),

                  // Divider
                  Container(
                    height: 1,
                    color: const Color(0x14FFFFFF),
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  ),

                  // 4. Удалить
                  _buildContextMenuItem(
                    icon: Icons.delete_outline_rounded,
                    title: 'Удалить',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(dialogContext);
                      chatProvider.deleteMessage(widget.chat.id, msg.id);
                    },
                  ),

                  // Bottom Message Date Status
                  Container(
                    height: 1,
                    color: const Color(0x14FFFFFF),
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Row(
                      children: [
                        Icon(
                          msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
                          size: 15,
                          color: const Color(0xFF3B98FF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatContextMenuDate(msg.createdAt),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12,
                            color: Color(0xFF929292),
                          ),
                        ),
                      ],
                    ),
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

  String _formatContextMenuDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Сегодня';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final timeStr = DateFormat('HH:mm').format(dt);
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Сегодня в $timeStr';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
        return 'Вчера в $timeStr';
      }
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')} в $timeStr';
    } catch (_) {
      return 'Сегодня';
    }
  }

  // ===========================================================================
  // PORTAL STICKER BUBBLE (Transparent Animated Sticker)
  // ===========================================================================
  Widget _buildPortalStickerBubble(Message msg, bool isMe) {
    String assetPath = 'lib/assets/sticker/sticker.gif';
    try {
      final raw = msg.text.trim();
      final startIdx = raw.indexOf('{');
      final endIdx = raw.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonStr = raw.substring(startIdx, endIdx + 1);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (map['asset'] != null && map['asset'].toString().isNotEmpty) {
          assetPath = map['asset'].toString();
        }
      }
    } catch (_) {}

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageContextMenu(msg),
        onSecondaryTap: () => _showMessageContextMenu(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Stack(
            alignment: isMe ? Alignment.bottomRight : Alignment.bottomLeft,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  assetPath,
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                bottom: 6,
                right: isMe ? 6 : null,
                left: isMe ? null : 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatMessageTime(msg.createdAt),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 13,
                          color: msg.isRead ? const Color(0xFF3B98FF) : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PORTAL PHOTO BUBBLE (Direct Chat Smart Collage & Caption)
  // ===========================================================================
  Widget _buildPortalPhotoBubble(Message msg, bool isMe) {
    List<String> rawUrls = [];
    String caption = '';
    try {
      final jsonStr = msg.text.substring('[PORTAL_PHOTO]:'.length).trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['urls'] is List) {
        rawUrls = (map['urls'] as List)
            .map((e) => e.toString())
            .where((u) => u.isNotEmpty)
            .toList();
      } else if (map['url'] != null && map['url'].toString().isNotEmpty) {
        rawUrls = [map['url'].toString()];
      }
      caption = map['caption']?.toString() ?? '';
    } catch (_) {}

    final List<String> fullUrls = rawUrls.map((u) {
      if (File(u).existsSync()) return u;
      return AppConstants.formatMediaUrl(u);
    }).toList();
    final double bubbleWidth =
        (MediaQuery.of(context).size.width * 0.78).clamp(240.0, 310.0);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageContextMenu(msg),
        onSecondaryTap: () => _showMessageContextMenu(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: bubbleWidth,
          ),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF2A2A2A) : const Color(0xFF191919),
            borderRadius: BorderRadius.circular(18),
            border: isMe ? null : Border.all(color: const Color(0x14FFFFFF), width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.replyToMessageId != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: _buildReplyPreviewInBubble(msg.replyToMessageId!),
                ),
              ],
              if (fullUrls.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(msg.replyToMessageId != null ? 8 : 18),
                    topRight: Radius.circular(msg.replyToMessageId != null ? 8 : 18),
                    bottomLeft: Radius.circular(caption.isNotEmpty ? 4 : 18),
                    bottomRight: Radius.circular(caption.isNotEmpty ? 4 : 18),
                  ),
                  child: _buildCollage(
                    fullUrls,
                    bubbleWidth,
                    caption.isEmpty ? _buildFloatingTimestamp(msg, isMe) : null,
                    isPending: msg.isPending,
                    onCancel: msg.isPending
                        ? () => context.read<ChatProvider>().cancelPendingMessage(widget.chat.id, msg.id)
                        : null,
                  ),
                ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caption,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 14.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Spacer(),
                          if (msg.isEdited) ...[
                            const Text(
                              'изменено ',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 10.5,
                                color: Color(0xFF929292),
                              ),
                            ),
                          ],
                          Text(
                            _formatMessageTime(msg.createdAt),
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 11,
                              color: Color(0xFF929292),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
                              size: 13,
                              color: const Color(0xFF929292),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Floating Timestamp Capsule (Used when photo has no caption, like Telegram)
  Widget _buildFloatingTimestamp(Message msg, bool isMe) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (msg.isEdited) ...[
            const Text(
              'изм. ',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 10,
                color: Colors.white70,
              ),
            ),
          ],
          Text(
            _formatMessageTime(msg.createdAt),
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 10.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 3.5),
            Icon(
              msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
              size: 12,
              color: Colors.white,
            ),
          ],
        ],
      ),
    );
  }

  // Smart Collage Builder (1, 2, 3, 4, 5+ photos)
  Widget _buildCollage(
    List<String> urls,
    double width,
    Widget? timestampOverlay, {
    bool isPending = false,
    VoidCallback? onCancel,
  }) {
    const double gap = 2.5;
    final int count = urls.length;

    if (count == 1) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 260),
        child: _buildCollageTile(
          urls,
          0,
          240,
          isBottomRight: true,
          timestampOverlay: timestampOverlay,
          isPending: isPending,
          onCancel: onCancel,
        ),
      );
    }

    if (count == 2) {
      final h = width * 0.56;
      return SizedBox(
        width: width,
        height: h,
        child: Row(
          children: [
            Expanded(
              child: _buildCollageTile(
                urls,
                0,
                h,
                isPending: isPending,
                onCancel: onCancel,
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: _buildCollageTile(
                urls,
                1,
                h,
                isBottomRight: true,
                timestampOverlay: timestampOverlay,
                isPending: isPending,
                onCancel: onCancel,
              ),
            ),
          ],
        ),
      );
    }

    if (count == 3) {
      final topH = width * 0.46;
      final botH = width * 0.44;
      return SizedBox(
        width: width,
        child: Column(
          children: [
            SizedBox(
              height: topH,
              child: Row(
                children: [
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      0,
                      topH,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      1,
                      topH,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: botH,
              child: Row(
                children: [
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      2,
                      botH,
                      isBottomRight: true,
                      timestampOverlay: timestampOverlay,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (count == 4) {
      final rowH = width * 0.44;
      return SizedBox(
        width: width,
        child: Column(
          children: [
            SizedBox(
              height: rowH,
              child: Row(
                children: [
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      0,
                      rowH,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      1,
                      rowH,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: gap),
            SizedBox(
              height: rowH,
              child: Row(
                children: [
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      2,
                      rowH,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      3,
                      rowH,
                      isBottomRight: true,
                      timestampOverlay: timestampOverlay,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 5 photos (Matches user screenshot: 2 on top, 3 on bottom)
    final topH = width * 0.52;
    final botH = width * 0.35;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Верхний ряд: 2 фото
          SizedBox(
            height: topH,
            child: Row(
              children: [
                Expanded(
                  child: _buildCollageTile(
                    urls,
                    0,
                    topH,
                    isPending: isPending,
                    onCancel: onCancel,
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _buildCollageTile(
                    urls,
                    1,
                    topH,
                    isPending: isPending,
                    onCancel: onCancel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          // Нижний ряд: 3 фото (или больше если count > 5)
          SizedBox(
            height: botH,
            child: Row(
              children: [
                for (int i = 2; i < count; i++) ...[
                  if (i > 2) const SizedBox(width: gap),
                  Expanded(
                    child: _buildCollageTile(
                      urls,
                      i,
                      botH,
                      isBottomRight: i == count - 1,
                      timestampOverlay: timestampOverlay,
                      isPending: isPending,
                      onCancel: onCancel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Individual Tile in Collage
  Widget _buildCollageTile(
    List<String> urls,
    int index,
    double height, {
    bool isBottomRight = false,
    Widget? timestampOverlay,
    bool isPending = false,
    VoidCallback? onCancel,
  }) {
    final url = urls[index];
    final isLocalFile = File(url).existsSync();

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            if (!isPending) {
              _showFullscreenGallery(urls, index);
            }
          },
          child: isLocalFile
              ? Image.file(
                  File(url),
                  fit: BoxFit.cover,
                  height: height,
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  height: height,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: const Color(0xFF222222),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF222222),
                    child: const Center(
                      child: Icon(Icons.broken_image_rounded, color: Color(0xFF929292), size: 24),
                    ),
                  ),
                ),
        ),

        // Telegram-style upload indicator in the center of the photo
        if (isPending)
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: onCancel,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (isBottomRight && timestampOverlay != null)
          Positioned(
            bottom: 5,
            right: 5,
            child: timestampOverlay,
          ),
      ],
    );
  }

  // ===========================================================================
  // PORTAL GIFT BUBBLE (Centered Frosted Glass Card & Top Pill)
  // ===========================================================================
  Widget _buildPortalGiftBubble(Message msg, bool isMe) {
    Map<String, dynamic> giftData = {};
    try {
      final raw = msg.text.trim();
      final jsonStr = raw.startsWith('[PORTAL_GIFT]:')
          ? raw.substring('[PORTAL_GIFT]:'.length).trim()
          : raw;
      giftData = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {}

    final giftDbId = giftData['giftDbId'] is int
        ? giftData['giftDbId'] as int
        : (int.tryParse(giftData['giftDbId']?.toString() ?? '') ?? 0);
    final giftName = giftData['giftName']?.toString() ?? 'Подарок';
    final modelFile = giftData['modelFile']?.toString() ??
        giftData['assetPath']?.toString() ??
        giftData['giftFile']?.toString() ??
        '';
    final comment = giftData['comment']?.toString() ?? '';
    final price = giftData['price'] is int
        ? giftData['price'] as int
        : (int.tryParse(giftData['price']?.toString() ?? '') ?? 50);
    final currentAuthUser = context.read<AuthProvider>().currentUser;
    final senderName = giftData['senderName']?.toString() ??
        (isMe ? 'Вы' : (msg.senderName.isNotEmpty ? msg.senderName : widget.chat.title));
    final recipientName = giftData['recipientName']?.toString() ??
        (isMe ? widget.chat.title : (currentAuthUser?.displayName.isNotEmpty == true ? currentAuthUser!.displayName : 'Вы'));
    final recipientAvatar = giftData['recipientAvatar']?.toString() ??
        (isMe ? widget.chat.avatar : (currentAuthUser?.avatar ?? ''));
    final recipientUsername = giftData['recipientUsername']?.toString() ?? '';
    final recipientId = giftData['recipientId'] is int
        ? giftData['recipientId'] as int
        : (int.tryParse(giftData['recipientId']?.toString() ?? '') ??
            (!isMe ? (currentAuthUser?.id ?? 0) : 0));

    final recipientParts = recipientName.trim().split(' ');
    final recipientFirst = recipientParts.isNotEmpty ? recipientParts.first : '';
    final recipientLast = recipientParts.length > 1 ? recipientParts.skip(1).join(' ') : '';

    final topPillText1 = isMe
        ? 'Вы отправили $recipientName подарок стоимостью'
        : '$senderName отправил(а) вам подарок стоимостью';
    final topPillText2 = '$price Sparks';

    final userGift = UserGift(
      id: giftDbId > 0 ? giftDbId : msg.id,
      userId: recipientId > 0 ? recipientId : (giftData['recipientId'] is int ? giftData['recipientId'] as int : 0),
      recipientId: recipientId,
      recipientFirstName: recipientFirst,
      recipientLastName: recipientLast,
      recipientUsername: recipientUsername,
      recipientAvatar: recipientAvatar,
      giftId: giftData['giftId']?.toString() ?? '',
      giftName: giftName,
      modelName: giftData['modelName']?.toString() ?? giftName,
      modelFile: modelFile,
      backdropName: giftData['backdropName']?.toString() ?? 'Fire Engine',
      backdropGradient: giftData['backdropGradient']?.toString() ??
          'radial-gradient(circle, #FF334B 0%, #C00C2C 60%, #4A000E 100%)',
      patternName: giftData['patternName']?.toString() ?? '',
      patternSvg: giftData['patternSvg']?.toString() ?? '',
      nftNumber: giftData['nftNumber'] is int
          ? giftData['nftNumber'] as int
          : (int.tryParse(giftData['nftNumber']?.toString() ?? '') ?? 1),
      senderId: giftData['senderId'] is int
          ? giftData['senderId'] as int
          : (isMe ? (currentAuthUser?.id ?? 0) : 0),
      senderFirstName: senderName.split(' ').first,
      senderLastName: senderName.split(' ').skip(1).join(' '),
      senderUsername: giftData['senderUsername']?.toString() ?? '',
      senderAvatar: giftData['senderAvatar']?.toString() ?? '',
      createdAt: giftData['createdAt']?.toString() ?? msg.createdAt,
      isUpgraded: giftData['isUpgraded'] == true,
      comment: comment.isNotEmpty ? comment : null,
    );

    final isImage = userGift.isImage ||
        userGift.assetPath.toLowerCase().endsWith('.png') ||
        userGift.assetPath.toLowerCase().endsWith('.jpg') ||
        userGift.assetPath.toLowerCase().endsWith('.webp');

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onLongPress: () => _showMessageContextMenu(msg),
        onSecondaryTap: () => _showMessageContextMenu(msg),
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Top Pill: "Вы отправили ... подарок стоимостью / 50 Sparks"
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xB81A1B24),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0x33FFFFFF),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        topPillText1,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFE5E5EA),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topPillText2,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 2. Ultra-rounded Frosted Glass Card
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  decoration: userGift.isUpgraded
                      ? GiftVisuals.getBackdropDecoration(
                          backdropName: userGift.backdropName,
                          backdropGradient: userGift.backdropGradient,
                          giftName: userGift.giftName,
                          giftId: userGift.giftId,
                          borderRadius: BorderRadius.circular(30),
                        )
                      : BoxDecoration(
                          color: const Color(0x1AFFFFFF), // Transparent glass
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: const Color(0x38FFFFFF),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Centered Gift Preview with Soft Ambient Bloom
                      SizedBox(
                        height: 105,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: GiftVisuals.getAmbientGlowColor(
                                      userGift.backdropName,
                                      userGift.giftName,
                                      userGift.backdropGradient,
                                    ),
                                    blurRadius: 40,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            if (isImage)
                              Image.asset(
                                userGift.assetPath,
                                height: 95,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.card_giftcard_rounded,
                                  size: 60,
                                  color: Colors.white70,
                                ),
                              )
                            else
                              Lottie.asset(
                                userGift.assetPath,
                                height: 95,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.card_giftcard_rounded,
                                  size: 60,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // "Подарок" / Name text
                      Text(
                        userGift.isUpgraded
                            ? (userGift.modelName.isNotEmpty ? userGift.modelName : userGift.giftName)
                            : 'Подарок',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),

                      // Optional caption underneath "Подарок"
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          comment,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.85),
                            height: 1.3,
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Button "Посмотреть" (Transparent, blurred, darker than card)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Material(
                            color: const Color(0x52000000), // Darker transparent
                            child: InkWell(
                              onTap: () {
                                GiftDetailModal.show(
                                  context,
                                  gift: userGift,
                                  ownerName: recipientName,
                                  ownerAvatar: recipientAvatar,
                                  onGiftUpgraded: (upgradedGift) {
                                    try {
                                      final updatedData = Map<String, dynamic>.from(giftData);
                                      updatedData['isUpgraded'] = true;
                                      updatedData['modelName'] = upgradedGift.modelName;
                                      updatedData['modelFile'] = upgradedGift.modelFile;
                                      updatedData['giftFile'] = upgradedGift.modelFile;
                                      updatedData['assetPath'] = upgradedGift.assetPath;
                                      updatedData['giftName'] = upgradedGift.giftName;
                                      updatedData['backdropName'] = upgradedGift.backdropName;
                                      updatedData['backdropGradient'] = upgradedGift.backdropGradient;
                                      updatedData['patternName'] = '';
                                      final newContent = '[PORTAL_GIFT]:${jsonEncode(updatedData)}';
                                      context.read<ChatProvider>().editMessage(widget.chat.id, msg.id, newContent);
                                    } catch (_) {}
                                  },
                                );
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0x30FFFFFF),
                                    width: 1.0,
                                  ),
                                ),
                                child: const Text(
                                  'Посмотреть',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
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
    ),
  );
}

  // ===========================================================================
  // EDIT BANNER OVER INPUT
  // ===========================================================================
  Widget _buildEditBar() {
    if (_editingMessage == null) return const SizedBox.shrink();

    String previewText = _editingMessage!.text;
    if (_isGiftMessage(previewText)) {
      previewText = '🎁 Подарок';
    } else if (previewText.startsWith('[PORTAL_STICKER]:') || previewText.contains('[PORTAL_STICKER]:')) {
      previewText = '✨ Стикер';
    } else if (previewText.startsWith('[PORTAL_PHOTO]:')) {
      previewText = '📷 Фотография';
    }
    previewText = previewText.replaceAll('\n', ' ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.edit_outlined,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Container(
            width: 2.5,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Редактирование',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 12,
                    color: Color(0xFF929292),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _editingMessage = null;
                _textController.clear();
              });
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0x1AFFFFFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFF929292),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // REPLY BANNER OVER INPUT
  // ===========================================================================
  Widget _buildReplyBar() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    final replySender = _replyingToMessage!.senderName.isNotEmpty
        ? _replyingToMessage!.senderName
        : (widget.chat.isChannel ? widget.chat.title : 'Ответить');

    String previewText = _replyingToMessage!.text;
    if (_isGiftMessage(previewText)) {
      previewText = '🎁 Подарок';
    } else if (previewText.startsWith('[PORTAL_STICKER]:') || previewText.contains('[PORTAL_STICKER]:')) {
      previewText = '✨ Стикер';
    } else if (previewText.startsWith('[PORTAL_PHOTO]:')) {
      previewText = '📷 Фотография';
    }
    previewText = previewText.replaceAll('\n', ' ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.reply_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Container(
            width: 2.5,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ для $replySender',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 12,
                    color: Color(0xFF929292),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _replyingToMessage = null);
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0x1AFFFFFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFF929292),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FLOATING INPUT BAR (1:1 with Screenshot 2)
  // ===========================================================================
  Widget _buildFloatingInputBar() {
    final hasText = _textController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_editingMessage != null)
          _buildEditBar()
        else if (_replyingToMessage != null)
          _buildReplyBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!_isRecordingVoice) ...[
                // Left Circle Button: Plus (+)
                GestureDetector(
                  onTap: _openPhotoGallerySheet,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Center Input Pill
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 18, right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                    ),
                    child: Row(
                      children: [
                        // Text input field
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            onChanged: _handleTextChange,
                            contextMenuBuilder: TelegramTextSelectionToolbar.buildToolbar,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.chat.isChannel
                                  ? 'Опубликовать пост...'
                                  : (widget.chat.isSaved ? 'Сохранить заметку...' : 'Написать сообщение...'),
                              hintStyle: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Color(0xFF929292),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _handleSend(),
                          ),
                        ),

                        // Smiley emoji icon
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.sentiment_satisfied_rounded,
                            color: Color(0xFF929292),
                            size: 22,
                          ),
                          onPressed: () {},
                        ),
                        const SizedBox(width: 6),

                        // Circular Arrow Send Button inside pill (White active, black arrow)
                        GestureDetector(
                          onTap: hasText ? _handleSend : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: hasText ? Colors.white : const Color(0xFF262626),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                color: hasText ? const Color(0xFF090909) : const Color(0xFF929292),
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Recording Indicator Bar (Pulsing Red Dot, Timer, Swipe to cancel)
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
                    ),
                    child: Row(
                      children: [
                        FadeTransition(
                          opacity: _blinkAnimation,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatRecordingTime(_recordElapsedMs),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        Transform.translate(
                          offset: Offset((_cancelDragOffset * 0.4).clamp(-50.0, 0.0), 0),
                          child: Opacity(
                            opacity: (1.0 + _cancelDragOffset / 120.0).clamp(0.2, 1.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chevron_left_rounded,
                                  color: _cancelDragOffset < -70
                                      ? const Color(0xFFFF453A)
                                      : const Color(0xFF929292),
                                  size: 18,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  _cancelDragOffset < -70 ? 'Отпустите для отмены' : 'Смахните для отмены',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 12.5,
                                    fontWeight: _cancelDragOffset < -70 ? FontWeight.w600 : FontWeight.normal,
                                    color: _cancelDragOffset < -70
                                        ? const Color(0xFFFF453A)
                                        : const Color(0xFF929292),
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
              ],
              const SizedBox(width: 10),

              // Right Circle Button: Microphone with Telegram ripple & scale
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (_) => _startVoiceRecording(),
                onLongPressMoveUpdate: (details) {
                  _updateVoiceDrag(details.offsetFromOrigin.dx);
                },
                onLongPressEnd: (_) => _stopVoiceRecording(send: true),
                onLongPressCancel: () => _stopVoiceRecording(send: false),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Удерживайте для записи голосового сообщения'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(milliseconds: 1500),
                    ),
                  );
                },
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Telegram-style ripple waves when recording
                      if (_isRecordingVoice)
                        AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            final v1 = _rippleController.value;
                            final v2 = (v1 + 0.5) % 1.0;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 54 + (34 * v1),
                                  height: 54 + (34 * v1),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity((1.0 - v1) * 0.22),
                                  ),
                                ),
                                Container(
                                  width: 54 + (34 * v2),
                                  height: 54 + (34 * v2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity((1.0 - v2) * 0.22),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                      // Main Mic Circle
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: _isRecordingVoice ? 56 : 48,
                        height: _isRecordingVoice ? 56 : 48,
                        decoration: BoxDecoration(
                          color: _isRecordingVoice ? Colors.white : const Color(0xFF191919),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecordingVoice ? Colors.transparent : const Color(0x1AFFFFFF),
                            width: 1,
                          ),
                          boxShadow: _isRecordingVoice
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.35),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.mic_rounded,
                            color: _isRecordingVoice ? Colors.black : Colors.white,
                            size: _isRecordingVoice ? 28 : 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // iOS Home Indicator
        Container(
          width: 134,
          height: 5,
          margin: const EdgeInsets.only(top: 2, bottom: 6),
          decoration: BoxDecoration(
            color: const Color(0x4DFFFFFF),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
      ],
    );
  }

  void _openPhotoGallerySheet() {
    PhotoPickerBottomSheet.show(
      context,
      onSend: (files, caption) async {
        Navigator.of(context).pop();
        await _sendSelectedPhotos(files, caption);
      },
      onOpenGifts: () {
        Navigator.of(context).pop();
        SendGiftModal.show(context, chat: widget.chat);
      },
    );
  }

  Future<void> _sendSelectedPhotos(List<File> files, String caption) async {
    if (files.isEmpty) return;
    final chatProvider = context.read<ChatProvider>();
    final replyId = _replyingToMessage?.id;

    if (mounted) {
      setState(() {
        _replyingToMessage = null;
      });
      _scrollToBottom();
    }

    // Sends optimistically right away and uploads in the background!
    await chatProvider.sendPhotoMessage(
      widget.chat.id,
      files: files,
      caption: caption,
      replyToMessageId: replyId,
    );
  }

  void _showFullscreenImage(String imageUrl) {
    _showFullscreenGallery([imageUrl], 0);
  }

  void _showFullscreenGallery(List<String> imageUrls, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (ctx, anim1, anim2) {
          final pageController = PageController(initialPage: initialIndex);
          int currentIndex = initialIndex;

          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return Scaffold(
                backgroundColor: Colors.black.withOpacity(0.95),
                body: Stack(
                  children: [
                    PageView.builder(
                      controller: pageController,
                      itemCount: imageUrls.length,
                      onPageChanged: (idx) =>
                          setModalState(() => currentIndex = idx),
                      itemBuilder: (ctx, idx) {
                        return Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 3.5,
                            child: Image.network(
                              AppConstants.formatMediaUrl(imageUrls[idx]),
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, s) => const Center(
                                child: Icon(Icons.broken_image_rounded,
                                    color: Colors.white54, size: 48),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Top Bar: Close Button & Album Counter
                    Positioned(
                      top: MediaQuery.of(ctx).padding.top + 12,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0x33FFFFFF), width: 1),
                              ),
                              child: const Center(
                                child: Icon(Icons.close_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (imageUrls.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0x22FFFFFF), width: 1),
                              ),
                              child: Text(
                                '${currentIndex + 1} из ${imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
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
      ),
    );
  }
}
