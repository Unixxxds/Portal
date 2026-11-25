import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/user_activity_helper.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/message_reaction.dart';
import '../../models/user_gift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/media_cache_service.dart';
import '../../services/api_service.dart';
import '../../services/gallery_service.dart';
import '../../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';
import '../widgets/formatted_message_text.dart';
import '../widgets/gift_detail_modal.dart';
import '../widgets/gift_visuals.dart';
import '../widgets/group_join_dialog.dart';
import '../widgets/photo_picker_bottom_sheet.dart';
import '../widgets/portal_emoji_picker.dart';
import '../widgets/send_gift_modal.dart';
import '../widgets/telegram_bubble.dart';
import '../widgets/telegram_chat_route.dart';
import '../widgets/telegram_message_context_menu.dart';
import '../widgets/telegram_message_entrance.dart';
import '../widgets/telegram_profile_route.dart';
import '../widgets/telegram_swipe_to_reply.dart';
import '../widgets/telegram_text_selection_toolbar.dart';
import '../widgets/telegram_typing_indicator.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/fullscreen_gallery_viewer.dart';
import 'user_profile_screen.dart';
import 'channel_profile_screen.dart';
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
  final _textFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _isTypingSent = false;
  Message? _replyingToMessage;
  Message? _editingMessage;
  late bool _isSubscribed;
  late int _subscribersCount;
  int _membersCount = 0;
  int _onlineMembersCount = 0;
  bool _isSubscribing = false;
  String? _liveVerification;
  bool? _liveIsPremium;
  int? _channelOwnerId;
  bool _canPostToChannel = false;
  bool _isSending = false;
  bool _isSendingSticker = false;
  String? _liveTitle;
  String? _liveAvatar;
  String? _liveUsername;
  final Set<int> _viewedMessageIds = {};
  int _lastRenderedMessageCount = 0;
  bool _hasInitiallyScrolled = false;
  bool _showEmojiPicker = false;

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

  // Send button and message entrance animations
  late final AnimationController _sendBtnAnimController;
  late final Animation<double> _sendBtnScaleAnim;
  late final Animation<Offset> _sendBtnArrowSlideAnim;

  // Header capsule bounce animation on artifact impact
  late final AnimationController _headerBounceController;
  late final Animation<double> _headerBounceAnimation;

  // Attachment paperclip button progress notifier (0.0 = закрыто, 1.0 = half, 2.0 = full)
  final ValueNotifier<double> _pickerProgress = ValueNotifier<double>(0.0);

  final Set<int> _seenMessageIds = {};
  bool _isInitialMessagesRecorded = false;
  ChatProvider? _chatProvider;

  // Pinned message jump & highlight state
  int? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<int, GlobalKey> _messageKeys = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();
  }

  @override
  void initState() {
    super.initState();
    _textFocusNode.addListener(() {
      if (_textFocusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
    _sendBtnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _sendBtnScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.80), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.80, end: 1.08), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _sendBtnAnimController, curve: Curves.easeInOut));

    _sendBtnArrowSlideAnim = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: Offset.zero, end: const Offset(0.0, -0.35)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.0, 0.25), end: Offset.zero), weight: 50),
    ]).animate(CurvedAnimation(parent: _sendBtnAnimController, curve: Curves.easeInOut));

    _headerBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _headerBounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.16, end: 0.92)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.92, end: 1.05)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 20,
      ),
    ]).animate(_headerBounceController);

    // Предзагрузка фото только после завершения анимации перехода в чат (устраняет фризы)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        GalleryService.instance.preload();
      }
    });

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _blinkAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_blinkController);
    _isSubscribed = widget.chat.isSubscribed;
    _subscribersCount = widget.chat.subscribersCount;
    _membersCount = widget.chat.membersCount > 0 ? widget.chat.membersCount : widget.chat.subscribersCount;
    _liveVerification = widget.chat.isGroup ? 'none' : widget.chat.effectiveVerification;
    _liveIsPremium = widget.chat.isGroup ? false : widget.chat.isPremium;
    _channelOwnerId = widget.chat.ownerId;
    _liveTitle = widget.chat.title;
    _liveAvatar = widget.chat.avatar;
    _liveUsername = widget.chat.username;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final chatProv = context.read<ChatProvider>();
      chatProv.loadPinnedMessage(widget.chat.id);
      final currentUserId = context.read<AuthProvider>().currentUser?.id;
      if (currentUserId != null && _channelOwnerId == currentUserId) {
        setState(() {
          _canPostToChannel = true;
        });
      }
      _checkUserPresence();
      await chatProv.openChat(
        widget.chat.id,
        participantId: widget.chat.isChannel || widget.chat.isGroup ? null : widget.chat.participantId,
        isChannel: widget.chat.isChannel,
      );
      if (mounted) {
        _jumpToBottomFast();
        Future.delayed(const Duration(milliseconds: 150), _jumpToBottomFast);
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
          final title = data['title']?.toString();
          final avatar = (data['avatar_url'] ?? data['avatar'])?.toString();
          final uname = data['username']?.toString();

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
            final cleanVerif = (verif != null && verif.isNotEmpty && verif != 'none')
                ? verif
                : ((uname?.toLowerCase() == 'portal' || widget.chat.username?.toLowerCase() == 'portal') ? 'verified' : 'none');
            _liveVerification = cleanVerif;
            if (title != null && title.isNotEmpty) {
              _liveTitle = title;
            }
            if (avatar != null && avatar.isNotEmpty) {
              _liveAvatar = avatar;
            }
            if (uname != null && uname.isNotEmpty) {
              _liveUsername = uname;
            }
          });

          final chatProv = context.read<ChatProvider>();
          final cleanVerif = (verif != null && verif.isNotEmpty && verif != 'none')
              ? verif
              : ((uname?.toLowerCase() == 'portal' || widget.chat.username?.toLowerCase() == 'portal') ? 'verified' : 'none');
          final existing = chatProv.chats.where((c) => c.isChannel && c.id == widget.chat.id).firstOrNull;
          if (existing != null) {
            final updated = existing.copyWith(
              title: (title != null && title.isNotEmpty) ? title : existing.title,
              avatar: (avatar != null && avatar.isNotEmpty) ? avatar : existing.avatar,
              username: (uname != null && uname.isNotEmpty) ? uname : existing.username,
              subscribersCount: _subscribersCount,
              isSubscribed: _isSubscribed,
              verification: cleanVerif,
            );
            chatProv.addOrUpdateChat(updated);
          } else {
            chatProv.updateChatVerification(
              chatId: widget.chat.id,
              verification: cleanVerif,
            );
          }
        }
      }).catchError((_) {});
    }

    if (widget.chat.isGroup) {
      _loadGroupData();
    }
  }

  void _loadGroupData() async {
    try {
      final members = await ApiService.instance.getGroupMembers(widget.chat.id);
      if (!mounted) return;
      int online = 0;
      for (final m in members) {
        if (m['is_online'] == 1 || m['is_online'] == true) {
          online++;
        }
      }
      setState(() {
        if (members.isNotEmpty) {
          _membersCount = members.length;
        }
        _onlineMembersCount = online;
      });
    } catch (_) {}
  }

  Future<void> _checkUserPresence() async {
    if (widget.chat.isSaved || widget.chat.isChannel || widget.chat.isGroup) return;
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
    _chatProvider?.closeChat();
    if (_isTypingSent) {
      WebSocketService.instance.sendTyping(widget.chat.id, isTyping: false);
    }
    _textController.dispose();
    _textFocusNode.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _highlightTimer?.cancel();
    _audioRecorder.dispose();
    _rippleController.dispose();
    _blinkController.dispose();
    _sendBtnAnimController.dispose();
    _headerBounceController.dispose();
    _pickerProgress.dispose();
    super.dispose();
  }

  void _handleReplyToMessage(Message msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyingToMessage = msg;
      _editingMessage = null;
    });
    _textFocusNode.requestFocus();
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
    if (_isSending) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _isSending = true;

    // Trigger Telegram-style punch animation on send button
    _sendBtnAnimController.forward(from: 0.0);
    HapticFeedback.lightImpact();

    if (_isTypingSent) {
      _isTypingSent = false;
      WebSocketService.instance.sendTyping(widget.chat.id, isTyping: false);
    }
    _textController.clear();

    try {
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
    } finally {
      _isSending = false;
    }
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

      _rippleController.repeat();
      _blinkController.repeat(reverse: true);

      setState(() {
        _isRecordingVoice = true;
        _recordElapsedMs = 0;
        _cancelDragOffset = 0.0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!mounted || !_isRecordingVoice) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordElapsedMs += 100;
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

    _rippleController.stop();
    _rippleController.reset();
    _blinkController.stop();
    _blinkController.reset();

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

  void _highlightMessage(int messageId) {
    _highlightTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() {
          if (_highlightedMessageId == messageId) {
            _highlightedMessageId = null;
          }
        });
      }
    });
  }

  void _scrollToMessage(int messageId) {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    // 1. Immediately trigger luminous highlight on target message
    _highlightMessage(messageId);

    // 2. If already built and mounted, smoothly center it in view
    final existingContext = _messageKeys[messageId]?.currentContext;
    if (existingContext != null && existingContext.mounted) {
      Scrollable.ensureVisible(
        existingContext,
        duration: const Duration(milliseconds: 350),
        alignment: 0.5,
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // 3. Otherwise approximate scroll with controller, then fine-tune center
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      final target = (idx / (messages.isNotEmpty ? messages.length : 1)) * max;
      _scrollController
          .animateTo(
        target.clamp(0.0, max),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final postContext = _messageKeys[messageId]?.currentContext;
          if (postContext != null && postContext.mounted) {
            Scrollable.ensureVisible(
              postContext,
              duration: const Duration(milliseconds: 200),
              alignment: 0.5,
              curve: Curves.easeOutCubic,
            );
          }
        });
      });
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
    if (!_isInitialMessagesRecorded) {
      if (!chatProvider.isLoading || messages.isNotEmpty) {
        for (final m in messages) {
          _seenMessageIds.add(m.id);
        }
        _isInitialMessagesRecorded = true;
      }
    }

    if (messages.isNotEmpty) {
      if (!_hasInitiallyScrolled || _lastRenderedMessageCount != messages.length) {
        final wasInitial = !_hasInitiallyScrolled;
        _hasInitiallyScrolled = true;
        _lastRenderedMessageCount = messages.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToBottomFast();
          if (wasInitial) {
            Future.delayed(const Duration(milliseconds: 120), _jumpToBottomFast);
          }
        });
      }
    }

    final isTyping = chatProvider.isUserTyping(widget.chat.id);
    final currentChat = chatProvider.chats.firstWhere(
      (c) => c.isChannel == widget.chat.isChannel && c.id == widget.chat.id,
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
      canPop: !_showEmojiPicker,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showEmojiPicker) {
          setState(() {
            _showEmojiPicker = false;
          });
          return;
        }
        if (didPop) {
          context.read<ChatProvider>().closeChat();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppTheme.appBg,
        appBar: _buildLiquidGlassHeader(isTyping, currentChat, isOnline, isChannelOwner),
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
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null &&
                                !_isSendingSticker &&
                                _showEmojiPicker) {
                              setState(() {
                                _showEmojiPicker = false;
                              });
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

                              final isMe = msg.senderId == currentUserId;
                              Widget cardWidget;
                              if (currentChat.isChannel) {
                                cardWidget = _buildChannelPostCard(msg);
                              } else {
                                cardWidget = _buildMessageBubble(msg, isMe);
                              }

                              final shouldAnimate = _isInitialMessagesRecorded && !_seenMessageIds.contains(msg.id);
                              if (shouldAnimate) {
                                _seenMessageIds.add(msg.id);
                                cardWidget = TelegramMessageEntrance(
                                  key: ValueKey('entrance_${msg.id}'),
                                  isMe: isMe,
                                  animate: true,
                                  child: cardWidget,
                                );
                              }

                              final canReply = !currentChat.isChannel || isChannelOwner;
                              cardWidget = TelegramSwipeToReply(
                                key: ValueKey('swipe_${msg.id}'),
                                enabled: canReply,
                                onReply: () => _handleReplyToMessage(msg),
                                child: cardWidget,
                              );

                              final itemKey = _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
                              final isHighlighted = _highlightedMessageId == msg.id;

                              final highlightedCard = AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                                margin: const EdgeInsets.symmetric(vertical: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isHighlighted ? const Color(0x38FFFFFF) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isHighlighted ? const Color(0x60FFFFFF) : Colors.transparent,
                                    width: 1.5,
                                  ),
                                  boxShadow: isHighlighted
                                      ? [
                                          BoxShadow(
                                            color: Colors.white.withOpacity(0.22),
                                            blurRadius: 16,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: cardWidget,
                              );

                              if (showDate) {
                                return RepaintBoundary(
                                  key: itemKey,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDateBadge(_formatDateBadge(msg.createdAt)),
                                      highlightedCard,
                                    ],
                                  ),
                                );
                              }
                              return RepaintBoundary(
                                key: itemKey,
                                child: highlightedCard,
                              );
                            },
                          ),
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
            style: TextStyle(
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: const Color(0xE6151720),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: const Color(0x1AFFFFFF),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 16,
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
  PreferredSizeWidget _buildLiquidGlassHeader(bool isTyping, Chat chat, bool isOnline, bool isChannelOwner) {
    final isActivityHidden = chat.privacyLastSeen == 'nobody' || chat.isActivityHidden;
    final effectiveOnline = !isActivityHidden && isOnline;
    final statusText = isTyping
        ? 'печатает...'
        : (chat.isChannel
            ? UserActivityHelper.formatSubscribers(_subscribersCount)
            : (chat.isGroup
                ? UserActivityHelper.formatMembers(
                    _membersCount > 0 ? _membersCount : (chat.membersCount > 0 ? chat.membersCount : 1),
                    onlineCount: _onlineMembersCount > 0 ? _onlineMembersCount : null,
                  )
                : UserActivityHelper.formatActivity(
                    isOnline: effectiveOnline,
                    lastSeen: isActivityHidden ? null : chat.lastSeen,
                    isChannel: chat.isChannel,
                    isActivityHidden: isActivityHidden,
                  )));
    final statusColor = isTyping
        ? Colors.white
        : (effectiveOnline ? AppTheme.statusOnline : const Color(0xFF929292));

    final headerTitle = (chat.isChannel && _liveTitle != null && _liveTitle!.isNotEmpty)
        ? _liveTitle!
        : chat.title;
    final headerAvatar = (chat.isChannel && _liveAvatar != null && _liveAvatar!.isNotEmpty)
        ? _liveAvatar!
        : chat.avatar;
    final rawTitle = headerTitle.startsWith('📢') ? headerTitle.substring(1).trim() : headerTitle;
    final displayTitle = rawTitle.isEmpty ? (chat.isChannel ? 'Канал' : 'Чат') : rawTitle;

    final effectiveVerif = (_liveVerification != null && _liveVerification != 'none' && _liveVerification!.isNotEmpty)
        ? _liveVerification
        : chat.effectiveVerification;
    final isGroup = chat.isGroup;
    final isVerif = !isGroup && VerificationBadge.isVerified(effectiveVerif);
    final isPrem = !isGroup && (_liveIsPremium ?? chat.isPremium);

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
                    child: ScaleTransition(
                      scale: _headerBounceAnimation,
                      child: GestureDetector(
                      onTap: () {
                        if (chat.isChannel || chat.isGroup) {
                          _showChannelInfoModal(context, chat);
                        } else {
                          Navigator.push(
                            context,
                            TelegramProfileRoute(
                              builder: (context) => UserProfileScreen(chat: chat, fromChat: true),
                            ),
                          );
                        }
                      },
                      child: Container(
                        height: 46,
                        constraints: BoxConstraints(
                          minWidth: 140,
                          maxWidth: MediaQuery.of(context).size.width - (chat.isChannel ? (isChannelOwner ? 180 : 124) : 124),
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
                            Hero(
                              tag: 'user_avatar_${chat.id}',
                              flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                                return Material(
                                  color: Colors.transparent,
                                  child: toHeroContext.widget,
                                );
                              },
                              child: AvatarWidget(
                                avatarUrl: headerAvatar,
                                title: displayTitle,
                                size: 36,
                                isOnline: !isGroup && !chat.isChannel && isOnline,
                                isSaved: chat.isSaved,
                                isChannel: chat.isChannel,
                                isGroup: isGroup,
                              ),
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
                                      if (!chat.isChannel && !isGroup && isVerif) ...[
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
                                      if (!chat.isChannel && !isGroup && isPrem) ...[
                                        const SizedBox(width: 5),
                                        const PremiumBadge(size: 18.0),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  if (isTyping)
                                    const TelegramTypingIndicator(
                                      fontSize: 11.5,
                                      dotSize: 4.0,
                                      color: Color(0xFF007AFF),
                                    )
                                  else
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
                ),

                  // 3. Actions (Right)
                  Align(
                    alignment: Alignment.centerRight,
                    child: chat.isChannel
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isChannelOwner) ...[
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
                              ],
                              GestureDetector(
                                onTap: () => _showChannelMoreMenu(context, chat),
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
                        : (chat.isGroup
                            ? GestureDetector(
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
                              )
                            : GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    TelegramProfileRoute(
                                      builder: (context) => UserProfileScreen(chat: chat, fromChat: true),
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
                              )),
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
  // CHANNEL PROFILE SCREEN & CHANNEL MENU
  // ===========================================================================
  void _showChannelInfoModal(BuildContext context, Chat chat) {
    Navigator.push(
      context,
      TelegramProfileRoute(
        builder: (_) => ChannelProfileScreen(chat: chat),
      ),
    );
  }

  void _showChannelMoreMenu(BuildContext context, Chat chat) {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ChannelMenu',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        final topPadding = MediaQuery.of(ctx).padding.top + 58;
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: topPadding,
                right: 14,
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
                  child: ScaleTransition(
                    scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
                    alignment: Alignment.topRight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          width: 240,
                          decoration: BoxDecoration(
                            color: const Color(0xCC1A1A1C),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0x2EFFFFFF),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _showGiftArtifactModal(context, chat);
                                },
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Lottie.asset(
                                          'lib/assets/material/artefact.json',
                                          repeat: true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Подарить Артефакт',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontDisplay,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(height: 1, color: Color(0x1FFFFFFF), indent: 16, endIndent: 16),
                              InkWell(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _showChannelInfoModal(context, chat);
                                },
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Информация о канале',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
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
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _triggerArtifactFlightAnimation() {
    final overlayState = Overlay.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final screenSize = MediaQuery.of(context).size;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _FlyingArtifactOverlay(
        screenSize: screenSize,
        topPadding: topPadding,
        onImpact: () {
          if (mounted) {
            _headerBounceController.forward(from: 0.0);
            HapticFeedback.heavyImpact();
          }
        },
        onCompleted: () {
          try {
            entry.remove();
          } catch (_) {}
        },
      ),
    );

    overlayState.insert(entry);
  }

  void _showGiftArtifactModal(BuildContext context, Chat chat) {
    HapticFeedback.lightImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'GiftArtifactDialog',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, _, __) {
        return _GiftArtifactModal(
          chat: chat,
          parentContext: context,
          onGiftTriggered: _triggerArtifactFlightAnimation,
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

    final rawPostTitle = (_liveTitle != null && _liveTitle!.isNotEmpty)
        ? _liveTitle!
        : widget.chat.title;
    final channelTitle = rawPostTitle.startsWith('📢')
        ? rawPostTitle.substring(2).trim()
        : rawPostTitle;
    final rawUname = (_liveUsername != null && _liveUsername!.isNotEmpty)
        ? _liveUsername!
        : (widget.chat.username ?? '');
    final channelUsername = rawUname.isNotEmpty
        ? '@${rawUname.replaceFirst('@', '')}'
        : '@channel';
    final channelAvatar = (_liveAvatar != null && _liveAvatar!.isNotEmpty)
        ? _liveAvatar!
        : widget.chat.avatar;

    Widget buildCardWidget() {
      return Container(
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
                avatarUrl: channelAvatar,
                title: channelTitle,
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
    );
  }

  return Builder(
    builder: (cardContext) {
      final cardWidget = buildCardWidget();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _showChannelPostContextMenu(msg, cardContext, cardWidget),
        onSecondaryTap: () => _showChannelPostContextMenu(msg, cardContext, cardWidget),
        child: cardWidget,
      );
    },
  );
}

  void _showChannelPostContextMenu(
    Message msg,
    BuildContext cardContext,
    Widget cardWidget,
  ) {
    HapticFeedback.mediumImpact();
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? 0;
    final currentUserName = authProvider.currentUser?.displayName ?? '';
    final currentUserAvatar = authProvider.currentUser?.avatar ?? '';

    final currentChat = chatProvider.chats.firstWhere(
      (c) => c.isChannel == widget.chat.isChannel && c.id == widget.chat.id,
      orElse: () => widget.chat,
    );
    final isChannelOwner = currentChat.isChannel &&
        (_canPostToChannel ||
         (currentUserId > 0 &&
          ((_channelOwnerId != null && _channelOwnerId == currentUserId) ||
           (currentChat.ownerId != null && currentChat.ownerId == currentUserId) ||
           (widget.chat.ownerId != null && widget.chat.ownerId == currentUserId))));

    String cleanText = msg.text;
    if (_isGiftMessage(cleanText)) {
      cleanText = 'Подарок';
    } else if (cleanText.startsWith('[PORTAL_PHOTO]:')) {
      try {
        final jsonStr = cleanText.substring('[PORTAL_PHOTO]:'.length).trim();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final caption = map['caption']?.toString() ?? '';
        cleanText = caption.isNotEmpty ? caption : 'Фотография';
      } catch (_) {
        cleanText = 'Фотография';
      }
    } else if (cleanText.startsWith('[PORTAL_STICKER]:')) {
      cleanText = 'Стикер';
    }

    final screenSize = MediaQuery.of(context).size;
    Rect bubbleRect;
    final box = cardContext.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize) {
      bubbleRect = box.localToGlobal(Offset.zero) & box.size;
    } else {
      bubbleRect = Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height / 2),
        width: screenSize.width - 20,
        height: 200,
      );
    }

    TelegramMessageContextMenu.show(
      context: context,
      message: msg,
      bubbleRect: bubbleRect,
      bubbleWidget: cardWidget,
      isMe: isChannelOwner,
      isCurrentlyPinned: false,
      showActionsMenu: isChannelOwner,
      reactions: chatProvider.getMessageReactions(msg.id),
      currentUserId: currentUserId,
      onCopy: () {
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
      onEdit: isChannelOwner
          ? () {
              setState(() {
                _editingMessage = msg;
                _replyingToMessage = null;
                _textController.text = cleanText;
                _textController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _textController.text.length),
                );
              });
              _textFocusNode.requestFocus();
            }
          : null,
      onDelete: isChannelOwner
          ? () {
              chatProvider.deleteMessage(widget.chat.id, msg.id);
            }
          : null,
      onReaction: (emoji) {
        chatProvider.toggleReaction(
          widget.chat.id,
          msg.id,
          emoji,
          userId: currentUserId,
          userName: currentUserName,
          userAvatar: currentUserAvatar,
        );
      },
      onOpenCustomEmojiPicker: () {
        _showCustomReactionPicker(msg);
      },
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
                      child: File(fullUrls.first).existsSync()
                          ? Image.file(
                              File(fullUrls.first),
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : CachedNetworkImage(
                              imageUrl: fullUrls.first,
                              cacheManager: MediaCacheService.instance.cacheManager,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              memCacheWidth: 720,
                              fadeInDuration: const Duration(milliseconds: 150),
                              fadeOutDuration: const Duration(milliseconds: 150),
                              placeholder: (context, url) => Container(
                                height: 200,
                                color: const Color(0xFF222222),
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                height: 160,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Color(0xFF929292), size: 36),
                                ),
                              ),
                            ),
                    ),
            ),
            if (caption != null && caption.isNotEmpty) const SizedBox(height: 10),
          ],
          if (caption != null && caption.isNotEmpty)
            FormattedMessageText(
              text: caption,
              messageId: msg.id,
              isMe: false,
              onUsernameTap: _handleUsernameTap,
              onLinkTap: _handleLinkTap,
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

    // 3. Sticker in Channel Post
    if (text.startsWith('[PORTAL_STICKER]:') || text.contains('[PORTAL_STICKER]:')) {
      String assetPath = 'lib/assets/sticker/sticker.gif';
      try {
        final startIdx = text.indexOf('{');
        final endIdx = text.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          final jsonStr = text.substring(startIdx, endIdx + 1);
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (map['asset'] != null && map['asset'].toString().isNotEmpty) {
            assetPath = map['asset'].toString();
          }
        }
      } catch (_) {}

      final isNetwork = assetPath.startsWith('http://') || assetPath.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: isNetwork
              ? CachedNetworkImage(
                  imageUrl: assetPath,
                  width: 200,
                  height: 200,
                  memCacheWidth: 400,
                  memCacheHeight: 400,
                  fit: BoxFit.contain,
                )
              : Image.asset(
                  assetPath,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
        ),
      );
    }

    return FormattedMessageText(
      text: msg.text,
      messageId: msg.id,
      isMe: false,
      onUsernameTap: _handleUsernameTap,
      onLinkTap: _handleLinkTap,
      style: const TextStyle(
        fontFamily: AppTheme.fontText,
        color: Colors.white,
        fontSize: 14.5,
        height: 1.38,
      ),
    );
  }

  Widget _buildPostReactions(Message msg) {
    final chatProvider = context.watch<ChatProvider>();
    final reactions = chatProvider.getMessageReactions(msg.id);
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? 0;
    final currentUserName = authProvider.currentUser?.displayName ?? '';
    final currentUserAvatar = authProvider.currentUser?.avatar ?? '';

    // Group reactions by emoji
    final Map<String, List<MessageReaction>> grouped = {};
    for (final r in reactions) {
      grouped.putIfAbsent(r.emoji, () => []).add(r);
    }

    // Sort descending by count: highest reaction count first
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: sortedEntries.map((entry) {
          final emoji = entry.key;
          final count = entry.value.length;
          final isMine = entry.value.any((r) => r.userId == currentUserId);

          return _buildReactionPill(
            emoji,
            count,
            isMine: isMine,
            onTap: () {
              HapticFeedback.lightImpact();
              chatProvider.toggleReaction(
                widget.chat.id,
                msg.id,
                emoji,
                userId: currentUserId,
                userName: currentUserName,
                userAvatar: currentUserAvatar,
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReactionPill(
    String emoji,
    int count, {
    bool isMine = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF2B6DBE) : const Color(0xFF262626),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isMine ? const Color(0x66FFFFFF) : const Color(0x1AFFFFFF),
            width: 0.8,
          ),
          boxShadow: isMine
              ? [
                  BoxShadow(
                    color: const Color(0xFF2B6DBE).withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13.5)),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isMine ? Colors.white : Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
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

    if (!nextSub) {
      // Unsubscribe & leave channel: close screen and remove from chats list
      try {
        await ApiService.instance.toggleChannelSubscription(widget.chat.id, true);
        if (!mounted) return;
        await context.read<ChatProvider>().removeChatLocally(widget.chat.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Вы отписались от канала'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).pop();
      } catch (e) {
        debugPrint('Subscription unsubscribe error: $e');
        if (mounted) {
          setState(() => _isSubscribing = false);
        }
      }
      return;
    }

    final nextCount = _subscribersCount + 1;
    setState(() {
      _isSubscribed = true;
      _subscribersCount = nextCount;
    });

    try {
      await ApiService.instance.toggleChannelSubscription(widget.chat.id, false);
      if (!mounted) return;
      final updatedChat = widget.chat.copyWith(
        isSubscribed: true,
        subscribersCount: nextCount,
      );
      await context.read<ChatProvider>().addOrUpdateChat(updatedChat);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Вы подписались на канал'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint('Subscription toggle error: $e');
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _subscribersCount = _subscribersCount <= 0 ? 0 : _subscribersCount - 1;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSubscribing = false);
      }
    }
  }

  // ===========================================================================
  // MESSAGE BUBBLE
  // ===========================================================================
  ForwardedMessageInfo? _parseForwardedInfo(String rawText) {
    final trimmed = rawText.trim();
    if (!trimmed.startsWith('[PORTAL_FORWARD]:')) return null;
    try {
      final startIdx = trimmed.indexOf('{');
      final endIdx = trimmed.lastIndexOf('}');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonStr = trimmed.substring(startIdx, endIdx + 1);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final sId = map['sender_id'] is int
            ? map['sender_id'] as int
            : int.tryParse(map['sender_id']?.toString() ?? '') ?? 0;
        final sName = map['sender_name']?.toString() ?? '';
        final sAvatar = map['sender_avatar']?.toString() ?? '';
        final text = map['text']?.toString() ?? '';
        return ForwardedMessageInfo(
          senderId: sId,
          senderName: sName,
          senderAvatar: sAvatar,
          cleanText: text,
        );
      }
    } catch (_) {}
    return null;
  }

  Widget _buildForwardedHeader(ForwardedMessageInfo fwd, bool isMe) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openForwardedSenderProfile(
        fwd.senderId,
        fwd.senderName,
        fwd.senderAvatar,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Переслано от"
            Text(
              'Переслано от',
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: isMe ? const Color(0xB3FFFFFF) : const Color(0xFF8E8E93),
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AvatarWidget(
                  avatarUrl: fwd.senderAvatar,
                  title: fwd.senderName,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    fwd.senderName.isNotEmpty ? fwd.senderName : 'Пользователь',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white : const Color(0xFF3B98FF),
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForwardedSenderProfile(int senderId, String senderName, String senderAvatar) async {
    if (senderId <= 0 && senderName.isEmpty) return;
    final chatProv = context.read<ChatProvider>();
    Chat? target = chatProv.chats.where((c) => (senderId > 0 && c.participantId == senderId)).firstOrNull;
    if (target == null && senderName.isNotEmpty) {
      target = chatProv.chats.where((c) => c.title.toLowerCase() == senderName.toLowerCase()).firstOrNull;
    }
    target ??= Chat(
      id: senderId > 0 ? senderId : DateTime.now().millisecondsSinceEpoch,
      participantId: senderId > 0 ? senderId : null,
      title: senderName.isNotEmpty ? senderName : 'Пользователь',
      type: 'direct',
      avatar: senderAvatar,
    );
    Navigator.of(context).push(
      TelegramProfileRoute(
        builder: (_) => UserProfileScreen(chat: target!, fromChat: target.id == widget.chat.id),
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool isMe) {
    final fwd = _parseForwardedInfo(msg.text);
    final effectiveMsg = fwd != null ? msg.copyWith(text: fwd.cleanText) : msg;

    if (_isGiftMessage(effectiveMsg.text)) {
      return _buildPortalGiftBubble(effectiveMsg, isMe);
    }
    if (effectiveMsg.text.trim().startsWith('[PORTAL_STICKER]:') || effectiveMsg.text.contains('[PORTAL_STICKER]:')) {
      return _buildPortalStickerBubble(effectiveMsg, isMe);
    }
    if (effectiveMsg.text.trim().startsWith('[PORTAL_PHOTO]:')) {
      return _buildPortalPhotoBubble(effectiveMsg, isMe, forwardedInfo: fwd);
    }
    if (effectiveMsg.text.trim().startsWith('[PORTAL_VOICE]:')) {
      return VoiceMessageBubble(
        message: effectiveMsg,
        isMe: isMe,
        onLongPress: () => _showMessageContextMenu(msg),
        onCancel: msg.isPending
            ? () => context.read<ChatProvider>().cancelPendingMessage(widget.chat.id, msg.id)
            : null,
      );
    }
    if (_isPureEmoji(effectiveMsg.text)) {
      return _buildPureEmojiBubble(effectiveMsg, isMe);
    }

    final bool showGroupAvatar = widget.chat.isGroup && !isMe;
    final double maxBubbleWidth = MediaQuery.of(context).size.width * (showGroupAvatar ? 0.72 : 0.78);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showGroupAvatar) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final memberChat = Chat(
                    id: msg.senderId,
                    title: msg.senderName.isNotEmpty ? msg.senderName : 'Пользователь',
                    type: 'direct',
                    avatar: msg.senderAvatar,
                    participantId: msg.senderId,
                    verification: msg.senderVerification,
                    isPremium: msg.senderIsPremium,
                  );
                  Navigator.push(
                    context,
                    TelegramProfileRoute(
                      builder: (context) => UserProfileScreen(chat: memberChat, fromChat: true),
                    ),
                  );
                },
                child: AvatarWidget(
                  avatarUrl: msg.senderAvatar,
                  title: msg.senderName.isNotEmpty ? msg.senderName : 'U',
                  size: 32,
                ),
              ),
            ),
          ],
          Flexible(
            child: Builder(
              builder: (bubbleContext) {
                final bubbleWidget = _buildBubbleBody(msg, isMe, maxBubbleWidth, forwardedInfo: fwd);
                return GestureDetector(
                  onLongPress: () => _showMessageContextMenu(
                    msg,
                    bubbleContext: bubbleContext,
                    customBubbleWidget: Container(
                      constraints: BoxConstraints(
                        maxWidth: maxBubbleWidth,
                        minWidth: 50,
                      ),
                      child: bubbleWidget,
                    ),
                    isMe: isMe,
                  ),
                  onSecondaryTap: () => _showMessageContextMenu(
                    msg,
                    bubbleContext: bubbleContext,
                    customBubbleWidget: Container(
                      constraints: BoxConstraints(
                        maxWidth: maxBubbleWidth,
                        minWidth: 50,
                      ),
                      child: bubbleWidget,
                    ),
                    isMe: isMe,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2.5),
                    constraints: BoxConstraints(
                      maxWidth: maxBubbleWidth,
                      minWidth: 50,
                    ),
                    child: bubbleWidget,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSenderHeader(Message msg) {
    final senderName = msg.senderName.isNotEmpty ? msg.senderName : 'Участник';
    final isOwner = (widget.chat.ownerId != null && msg.senderId == widget.chat.ownerId) || msg.senderRole == 'owner';
    final hasVerif = VerificationBadge.isVerified(msg.senderVerification);
    final isPrem = msg.senderIsPremium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            senderName,
            style: const TextStyle(
              fontFamily: AppTheme.fontDisplay,
              color: Color(0xFF3B98FF),
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasVerif) ...[
          const SizedBox(width: 4),
          VerificationBadge(verification: msg.senderVerification, size: 14),
        ],
        if (isPrem) ...[
          const SizedBox(width: 4),
          const PremiumBadge(size: 14),
        ],
        if (isOwner) ...[
          const SizedBox(width: 8),
          const Text(
            'владелец',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              color: Color(0xFFA594F9),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBubbleBody(Message msg, bool isMe, double maxBubbleWidth, {ForwardedMessageInfo? forwardedInfo}) {
    final effectiveMsg = forwardedInfo != null ? msg.copyWith(text: forwardedInfo.cleanText) : msg;

    return TelegramBubble(
      isMe: isMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Forwarded Header (if forwarded message)
          if (forwardedInfo != null) ...[
            _buildForwardedHeader(forwardedInfo, isMe),
          ],

          // Replied Message Quote (if any)
          if (effectiveMsg.replyToMessageId != null) ...[
            _buildReplyPreviewInBubble(effectiveMsg.replyToMessageId!),
            const SizedBox(height: 5),
          ],

          // Sender name & role & badges for groups
          if (!isMe && widget.chat.isGroup) ...[
            _buildGroupSenderHeader(effectiveMsg),
            const SizedBox(height: 3),
          ] else if (!isMe && effectiveMsg.senderName.isNotEmpty && !widget.chat.isDirect) ...[
            Text(
              effectiveMsg.senderName,
              style: const TextStyle(
                fontFamily: AppTheme.fontDisplay,
                color: Color(0xFF3B98FF),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 3),
          ],

          // Message text & time (Telegram inline layout)
          _buildMessageTextWithTime(effectiveMsg, isMe, maxBubbleWidth),
        ],
      ),
    );
  }

  Widget _buildReactionsBadge(Message msg, bool isMe) {
    final chatProvider = context.watch<ChatProvider>();
    final reactions = chatProvider.getMessageReactions(msg.id);
    if (reactions.isEmpty) return const SizedBox.shrink();

    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? 0;
    final currentUserName = authProvider.currentUser?.displayName ?? '';
    final currentUserAvatar = authProvider.currentUser?.avatar ?? '';

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.map((r) {
        final isMine = r.userId == currentUserId;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            chatProvider.toggleReaction(
              widget.chat.id,
              msg.id,
              r.emoji,
              userId: currentUserId,
              userName: currentUserName,
              userAvatar: currentUserAvatar,
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: isMine
                  ? const Color(0xFF2B6DBE)
                  : (isMe ? const Color(0x3BFFFFFF) : const Color(0xFF255A9C)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isMine ? const Color(0x55FFFFFF) : const Color(0x28FFFFFF),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  r.emoji,
                  style: const TextStyle(fontSize: 14.5, height: 1.1),
                ),
                if (r.userAvatar.isNotEmpty || r.userName.isNotEmpty) ...[
                  const SizedBox(width: 4.5),
                  ClipOval(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: AvatarWidget(
                        size: 16,
                        avatarUrl: r.userAvatar,
                        title: r.userName.isNotEmpty ? r.userName : 'User',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleLinkTap(String rawUrl) async {
    String finalUrl = rawUrl.trim();
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }

    final uri = Uri.tryParse(finalUrl);
    if (uri != null &&
        (uri.host == 'portalmsg.ru' ||
            uri.host == 'web.portalmsg.ru' ||
            uri.host == 'www.portalmsg.ru' ||
            uri.host.contains('portalmsg.ru'))) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty && s != 'join').toList();
      if (segments.isNotEmpty) {
        final slug = segments.first.trim();
        try {
          final groupData = await ApiService.instance.previewGroup(slug);
          if (mounted && groupData != null) {
            GroupJoinDialog.show(
              context,
              groupData: groupData,
              inviteCode: slug,
            );
            return;
          }
        } catch (_) {}
      }
    }

    _launchExternalUrl(finalUrl);
  }

  void _launchExternalUrl(String finalUrl) {
    try {
      if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', finalUrl]);
      } else if (Platform.isMacOS) {
        Process.run('open', [finalUrl]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [finalUrl]);
      } else if (Platform.isAndroid) {
        Process.run('am', ['start', '-a', 'android.intent.action.VIEW', '-d', finalUrl]);
      }
    } catch (e) {
      debugPrint('Error opening link in browser: $e');
    }
  }

  Future<void> _handleUsernameTap(String rawUsername) async {
    final clean = rawUsername.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.isEmpty) return;

    final chatProv = context.read<ChatProvider>();

    // 1. Check in already loaded chats
    final localMatch = chatProv.chats.where((c) {
      final u = (c.username ?? '').replaceFirst(RegExp(r'^@+'), '').toLowerCase();
      final inv = (c.inviteCode ?? '').toLowerCase();
      return u == clean.toLowerCase() || inv == clean.toLowerCase();
    }).firstOrNull;

    if (localMatch != null) {
      if (localMatch.isChannel || localMatch.isGroup) {
        Navigator.of(context).push(
          TelegramChatRoute(
            builder: (_) => ChatScreen(chat: localMatch),
          ),
        );
      } else {
        Navigator.of(context).push(
          TelegramProfileRoute(
            builder: (_) => UserProfileScreen(chat: localMatch, fromChat: localMatch.id == widget.chat.id),
          ),
        );
      }
      return;
    }

    // 2. Search on server
    try {
      final results = await ApiService.instance.searchUsers(clean);
      final exactMatch = results.where((item) {
        final u = (item['username']?.toString() ?? '').replaceFirst(RegExp(r'^@+'), '').toLowerCase();
        final inv = (item['invite_code']?.toString() ?? '').toLowerCase();
        return u == clean.toLowerCase() || inv == clean.toLowerCase();
      }).firstOrNull ?? (results.isNotEmpty ? results.first : null);

      if (exactMatch != null && mounted) {
        final isChan = exactMatch['is_channel'] == 1 || exactMatch['is_channel'] == true || exactMatch['type'] == 'channel';
        final isGrp = exactMatch['is_group'] == 1 || exactMatch['is_group'] == true || exactMatch['type'] == 'group';

        if (isGrp) {
          final isSubscribed = exactMatch['is_subscribed'] == 1 || exactMatch['is_subscribed'] == true;
          if (isSubscribed) {
            final chat = Chat.fromJson(exactMatch);
            chatProv.addOrUpdateChat(chat);
            Navigator.of(context).push(
              TelegramChatRoute(
                builder: (_) => ChatScreen(chat: chat),
              ),
            );
          } else {
            GroupJoinDialog.show(
              context,
              groupData: exactMatch,
              inviteCode: exactMatch['invite_code']?.toString() ?? clean,
            );
          }
          return;
        }

        final chat = Chat.fromJson(exactMatch);
        chatProv.addOrUpdateChat(chat);

        if (isChan) {
          Navigator.of(context).push(
            TelegramChatRoute(
              builder: (_) => ChatScreen(chat: chat),
            ),
          );
        } else {
          Navigator.of(context).push(
            TelegramProfileRoute(
              builder: (_) => UserProfileScreen(chat: chat, fromChat: chat.id == widget.chat.id),
            ),
          );
        }
        return;
      }
    } catch (_) {}

    // 3. Username not found: Show frosted blurred centered popup
    if (mounted) {
      _showUsernameNotFoundModal();
    }
  }

  void _showUsernameNotFoundModal() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (dialogCtx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: (MediaQuery.of(dialogCtx).size.width * 0.82).clamp(280.0, 360.0),
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E20).withOpacity(0.82),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Такого юзернейма не существует.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        fontFamily: AppTheme.fontDisplay,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    GestureDetector(
                      onTap: () => Navigator.of(dialogCtx).pop(),
                      child: Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'ОК',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFamily: AppTheme.fontDisplay,
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
        );
      },
    );
  }

  Widget _buildMessageTextWithTime(Message msg, bool isMe, double maxBubbleWidth) {
    final timeColor = isMe ? const Color(0xCCFFFFFF) : const Color(0xFF929292);
    final timeWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (msg.isEdited) ...[
          Text(
            'изменено ',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 11,
              color: timeColor,
            ),
          ),
        ],
        Text(
          _formatMessageTime(msg.createdAt),
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 11.5,
            color: timeColor,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 3.5),
          if (msg.isPending)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                color: timeColor,
              ),
            )
          else
            Icon(
              msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
              size: 14.5,
              color: timeColor,
            ),
        ],
      ],
    );

    final chatProvider = context.watch<ChatProvider>();
    final reactions = chatProvider.getMessageReactions(msg.id);
    final hasReactions = reactions.isNotEmpty;

    if (hasReactions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormattedMessageText(
            text: msg.text,
            messageId: msg.id,
            isMe: isMe,
            onUsernameTap: _handleUsernameTap,
            onLinkTap: _handleLinkTap,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white,
              fontSize: 15.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildReactionsBadge(msg, isMe),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: timeWidget,
              ),
            ],
          ),
        ],
      );
    }

    final bool hasNewlines = msg.text.contains('\n');
    final bool hasQuote = msg.text.contains('>') || msg.text.contains('[QUOTE]');
    if (hasNewlines || hasQuote) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormattedMessageText(
            text: msg.text,
            messageId: msg.id,
            isMe: isMe,
            onUsernameTap: _handleUsernameTap,
            onLinkTap: _handleLinkTap,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white,
              fontSize: 15.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.bottomRight,
            child: timeWidget,
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (maxBubbleWidth - 36.0);

        const textStyle = TextStyle(
          fontFamily: AppTheme.fontText,
          color: Colors.white,
          fontSize: 15.5,
          height: 1.3,
        );

        final tp = TextPainter(
          text: TextSpan(text: msg.text, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: availableWidth);

        final double estTimeWidth = (isMe ? 62.0 : 48.0) + (msg.isEdited ? 50.0 : 0.0);

        if (tp.width + estTimeWidth + 8.0 <= availableWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FormattedMessageText(
                  text: msg.text,
                  messageId: msg.id,
                  isMe: isMe,
                  style: textStyle,
                  onUsernameTap: _handleUsernameTap,
                  onLinkTap: _handleLinkTap,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 1.0),
                child: timeWidget,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FormattedMessageText(
              text: msg.text,
              messageId: msg.id,
              isMe: isMe,
              style: textStyle,
              onUsernameTap: _handleUsernameTap,
              onLinkTap: _handleLinkTap,
            ),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.bottomRight,
              child: timeWidget,
            ),
          ],
        );
      },
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
  void _showMessageContextMenu(
    Message msg, {
    BuildContext? bubbleContext,
    Widget? customBubbleWidget,
    bool? isMe,
  }) {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? 0;
    final currentUserName = authProvider.currentUser?.displayName ?? '';
    final currentUserAvatar = authProvider.currentUser?.avatar ?? '';
    final bool me = isMe ?? (msg.senderId == currentUserId);

    final currentPinned = chatProvider.getPinnedMessage(widget.chat.id);
    final isCurrentlyPinned = currentPinned?.id == msg.id;

    final bool isGift = _isGiftMessage(msg.text);
    String cleanText = msg.text;
    String? copyText;
    if (isGift) {
      Map<String, dynamic> giftData = {};
      try {
        final raw = cleanText.trim();
        final jsonStr = raw.startsWith('[PORTAL_GIFT]:')
            ? raw.substring('[PORTAL_GIFT]:'.length).trim()
            : raw;
        giftData = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {}
      final giftName = giftData['giftName']?.toString() ?? 'Подарок';
      cleanText = 'Подарок: $giftName';
      copyText = '🎁 Подарок «$giftName»';
    } else if (cleanText.startsWith('[PORTAL_PHOTO]:')) {
      try {
        final jsonStr = cleanText.substring('[PORTAL_PHOTO]:'.length).trim();
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final caption = map['caption']?.toString() ?? '';
        cleanText = caption.isNotEmpty ? caption : 'Фотография';
      } catch (_) {
        cleanText = 'Фотография';
      }
    } else if (cleanText.startsWith('[PORTAL_STICKER]:')) {
      cleanText = 'Стикер';
    }

    final screenSize = MediaQuery.of(context).size;
    Rect bubbleRect;
    if (bubbleContext != null) {
      final box = bubbleContext.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) {
        bubbleRect = box.localToGlobal(Offset.zero) & box.size;
      } else {
        bubbleRect = Rect.fromCenter(
          center: Offset(screenSize.width / 2, screenSize.height / 2),
          width: isGift ? 240.0 : math.min(screenSize.width * 0.75, 260.0),
          height: isGift ? 250.0 : 60,
        );
      }
    } else {
      bubbleRect = Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height / 2),
        width: isGift ? 240.0 : math.min(screenSize.width * 0.75, 260.0),
        height: isGift ? 250.0 : 60,
      );
    }

    final double maxBubbleWidth = screenSize.width * 0.78;
    final Widget bubbleWidget = customBubbleWidget ??
        (isGift
            ? _buildPortalGiftFallback(msg, me)
            : Container(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth, minWidth: 50),
                child: _buildBubbleBody(msg, me, maxBubbleWidth),
              ));

    TelegramMessageContextMenu.show(
      context: context,
      message: msg,
      bubbleRect: bubbleRect,
      bubbleWidget: bubbleWidget,
      isMe: me,
      isCurrentlyPinned: isCurrentlyPinned,
      reactions: chatProvider.getMessageReactions(msg.id),
      currentUserId: currentUserId,
      onReply: () {
        setState(() {
          _replyingToMessage = msg;
          _editingMessage = null;
        });
      },
      onCopy: () {
        Clipboard.setData(ClipboardData(text: copyText ?? cleanText));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Текст скопирован'),
            duration: Duration(milliseconds: 1400),
            backgroundColor: Color(0xFF191919),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onPin: () {
        chatProvider.togglePinMessage(widget.chat.id, msg.id);
      },
      onForward: () {
        _showForwardMessageSheet(msg);
      },
      onEdit: (me && !isGift)
          ? () {
              setState(() {
                _editingMessage = msg;
                _replyingToMessage = null;
                _textController.text = cleanText;
                _textController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _textController.text.length),
                );
              });
            }
          : null,
      onDelete: () {
        chatProvider.deleteMessage(widget.chat.id, msg.id);
      },
      onSelect: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сообщение выбрано'),
            duration: Duration(milliseconds: 1200),
            backgroundColor: Color(0xFF191919),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onReaction: (emoji) {
        chatProvider.toggleReaction(
          widget.chat.id,
          msg.id,
          emoji,
          userId: currentUserId,
          userName: currentUserName,
          userAvatar: currentUserAvatar,
        );
      },
      onOpenCustomEmojiPicker: () {
        _showCustomReactionPicker(msg);
      },
    );
  }

  void _showCustomReactionPicker(Message msg) {
    final chatProvider = context.read<ChatProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id ?? 0;
    final currentUserName = authProvider.currentUser?.displayName ?? '';
    final currentUserAvatar = authProvider.currentUser?.avatar ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: PortalEmojiPicker(
                  showStickersTab: false,
                  onEmojiSelected: (emoji) {
                    Navigator.pop(ctx);
                    chatProvider.toggleReaction(
                      widget.chat.id,
                      msg.id,
                      emoji,
                      userId: currentUserId,
                      userName: currentUserName,
                      userAvatar: currentUserAvatar,
                    );
                  },
                  onBackspacePressed: () {},
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showForwardMessageSheet(Message msg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ForwardMessageModalSheet(
          message: msg,
          currentChatId: widget.chat.id,
          onForwardToChat: (targetChat) {
            Navigator.pop(sheetContext);
            _executeForwardMessage(msg, targetChat);
          },
        );
      },
    );
  }

  void _executeForwardMessage(Message msg, Chat targetChat) {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    final currentUserId = currentUser?.id ?? 0;

    // Check if message is already forwarded
    final originalForward = _parseForwardedInfo(msg.text);
    final String forwardPayload;

    if (originalForward != null) {
      forwardPayload = '[PORTAL_FORWARD]:${jsonEncode({
        'sender_id': originalForward.senderId,
        'sender_name': originalForward.senderName,
        'sender_avatar': originalForward.senderAvatar,
        'text': originalForward.cleanText,
      })}';
    } else {
      final bool isAuthorMe = msg.senderId == currentUserId;
      final int senderId = msg.senderId > 0
          ? msg.senderId
          : (isAuthorMe ? currentUserId : (widget.chat.participantId ?? widget.chat.id));

      final String senderName = msg.senderName.isNotEmpty
          ? msg.senderName
          : (isAuthorMe
              ? (currentUser?.fullName.isNotEmpty == true
                  ? currentUser!.fullName
                  : (currentUser?.username.isNotEmpty == true
                      ? '@${currentUser!.username}'
                      : 'Пользователь'))
              : widget.chat.title);

      final String senderAvatar = msg.senderAvatar.isNotEmpty
          ? msg.senderAvatar
          : (isAuthorMe ? (currentUser?.avatar ?? '') : widget.chat.avatar);

      forwardPayload = '[PORTAL_FORWARD]:${jsonEncode({
        'sender_id': senderId,
        'sender_name': senderName,
        'sender_avatar': senderAvatar,
        'text': msg.text,
      })}';
    }

    context.read<ChatProvider>().sendMessage(
      targetChat.id,
      forwardPayload,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Переслано в "${targetChat.title}"',
          style: const TextStyle(fontFamily: AppTheme.fontText, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF191919),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static final RegExp _pureEmojiRegex = RegExp(
    r'^[\s\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B50}\u{2B55}\u{200D}\u{FE0E}\u{FE0F}\u{20E3}\u{E0020}-\u{E007F}\u{00A9}\u{00AE}\u{2194}-\u{21AA}\u{2934}-\u{2935}\u{3030}\u{303D}\u{3297}\u{3299}]+$',
    unicode: true,
  );

  bool _isPureEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    // Disallow regular letters, digits or Cyrillic characters
    if (RegExp(r'[a-zA-Z0-9\u0400-\u04FF]').hasMatch(trimmed)) return false;
    // Disallow special protocol tags or links
    if (trimmed.startsWith('[PORTAL_') || trimmed.contains('http://') || trimmed.contains('https://')) return false;
    return _pureEmojiRegex.hasMatch(trimmed);
  }

  // ===========================================================================
  // PURE EMOJI BUBBLE (Without podlozhka, standalone emojis)
  // ===========================================================================
  Widget _buildPureEmojiBubble(Message msg, bool isMe) {
    final trimmed = msg.text.trim();
    final cleanChars = Characters(trimmed.replaceAll(RegExp(r'\s+'), ''));
    final emojiCount = cleanChars.length;

    double emojiSize = 54.0;
    if (emojiCount == 2) {
      emojiSize = 42.0;
    } else if (emojiCount == 3) {
      emojiSize = 36.0;
    } else if (emojiCount <= 6) {
      emojiSize = 30.0;
    } else if (emojiCount > 6) {
      emojiSize = 24.0;
    }

    final timeWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (msg.isEdited) ...[
          const Text(
            'изменено ',
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
          const SizedBox(width: 3),
          if (msg.isPending)
            const SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.3,
                color: Colors.white,
              ),
            )
          else
            Icon(
              msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
              size: 13.5,
              color: Colors.white,
            ),
        ],
      ],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageContextMenu(msg),
        onSecondaryTap: () => _showMessageContextMenu(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.replyToMessageId != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xB3191919),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
                  ),
                  child: _buildReplyPreviewInBubble(msg.replyToMessageId!),
                ),
              ],
              Stack(
                alignment: isMe ? Alignment.bottomRight : Alignment.bottomLeft,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      right: isMe ? 22.0 : 4.0,
                      left: isMe ? 4.0 : 22.0,
                      bottom: 8.0,
                      top: 2.0,
                    ),
                    child: Text(
                      trimmed,
                      style: TextStyle(
                        fontSize: emojiSize,
                        height: 1.18,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: isMe ? 0 : null,
                    left: isMe ? null : 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0x73000000),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: timeWidget,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      child: Builder(
        builder: (bubbleContext) {
          final stickerBubbleWidget = Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: isMe ? Alignment.bottomRight : Alignment.bottomLeft,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        assetPath,
                        width: 205,
                        height: 205,
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

                // Reactions badge for sticker
                Builder(
                  builder: (context) {
                    final chatProvider = context.watch<ChatProvider>();
                    final reactions = chatProvider.getMessageReactions(msg.id);
                    if (reactions.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildReactionsBadge(msg, isMe),
                    );
                  },
                ),
              ],
            ),
          );

          return GestureDetector(
            onLongPress: () => _showMessageContextMenu(
              msg,
              bubbleContext: bubbleContext,
              customBubbleWidget: stickerBubbleWidget,
              isMe: isMe,
            ),
            onSecondaryTap: () => _showMessageContextMenu(
              msg,
              bubbleContext: bubbleContext,
              customBubbleWidget: stickerBubbleWidget,
              isMe: isMe,
            ),
            child: stickerBubbleWidget,
          );
        },
      ),
    );
  }

  // ===========================================================================
  // PORTAL PHOTO BUBBLE (Direct Chat Smart Collage & Caption)
  // ===========================================================================
  Widget _buildPortalPhotoBubble(Message msg, bool isMe, {ForwardedMessageInfo? forwardedInfo}) {
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
      child: Builder(
        builder: (bubbleContext) {
          final photoBubbleWidget = Container(
            margin: const EdgeInsets.symmetric(vertical: 2.5),
            constraints: BoxConstraints(
              maxWidth: bubbleWidth,
            ),
            child: TelegramBubble(
              isMe: isMe,
              padding: EdgeInsets.zero,
              child: ClipPath(
                clipper: TelegramBubbleClipper(isMe: isMe),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (forwardedInfo != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: _buildForwardedHeader(forwardedInfo, isMe),
                    ),
                  ],
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
                      padding: EdgeInsets.fromLTRB(12, 8, isMe ? 18 : 12, 8),
                      child: Builder(
                        builder: (context) {
                          final timeColor = isMe ? const Color(0xCCFFFFFF) : const Color(0xFF929292);
                          final timeWidget = Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (msg.isEdited) ...[
                                Text(
                                  'изменено ',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 10.5,
                                    color: timeColor,
                                  ),
                                ),
                              ],
                              Text(
                                _formatMessageTime(msg.createdAt),
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 11,
                                  color: timeColor,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  msg.isRead ? Icons.done_all_rounded : Icons.check_rounded,
                                  size: 13,
                                  color: timeColor,
                                ),
                              ],
                            ],
                          );

                          if (!caption.contains('\n') && caption.length < 24) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Text(
                                    caption,
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 1.0),
                                  child: timeWidget,
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FormattedMessageText(
                                text: caption,
                                messageId: msg.id,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: timeWidget,
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  // Reactions badge for photo
                  Builder(
                    builder: (context) {
                      final chatProvider = context.watch<ChatProvider>();
                      final reactions = chatProvider.getMessageReactions(msg.id);
                      if (reactions.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.fromLTRB(10, 4, isMe ? 16 : 10, 6),
                        child: _buildReactionsBadge(msg, isMe),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        return GestureDetector(
          onLongPress: () => _showMessageContextMenu(
            msg,
            bubbleContext: bubbleContext,
            customBubbleWidget: photoBubbleWidget,
            isMe: isMe,
          ),
          onSecondaryTap: () => _showMessageContextMenu(
            msg,
            bubbleContext: bubbleContext,
            customBubbleWidget: photoBubbleWidget,
            isMe: isMe,
          ),
          child: photoBubbleWidget,
        );
      },
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
              : CachedNetworkImage(
                  imageUrl: url,
                  cacheManager: MediaCacheService.instance.cacheManager,
                  fit: BoxFit.cover,
                  height: height,
                  memCacheWidth: 800,
                  fadeInDuration: const Duration(milliseconds: 150),
                  fadeOutDuration: const Duration(milliseconds: 150),
                  placeholder: (context, u) => Container(
                    color: const Color(0xFF222222),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  ),
                  errorWidget: (context, u, error) => Container(
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
  // PORTAL GIFT CARD PREVIEW (Used for Context Menu and Bubble)
  // ===========================================================================
  Widget _buildPortalGiftCardPreview(
    Message msg,
    UserGift userGift,
    String comment,
  ) {
    final isImage = userGift.isImage ||
        userGift.assetPath.toLowerCase().endsWith('.png') ||
        userGift.assetPath.toLowerCase().endsWith('.jpg') ||
        userGift.assetPath.toLowerCase().endsWith('.webp');

    return Container(
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
              color: const Color(0x1AFFFFFF),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x66000000),
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
        ],
      ),
    );
  }

  Widget _buildPortalGiftFallback(Message msg, bool isMe) {
    Map<String, dynamic> giftData = {};
    try {
      final raw = msg.text.trim();
      final jsonStr = raw.startsWith('[PORTAL_GIFT]:')
          ? raw.substring('[PORTAL_GIFT]:'.length).trim()
          : raw;
      giftData = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {}
    final userGift = UserGift.fromJson(giftData, fallbackUserId: 0);
    final comment = giftData['comment']?.toString() ?? '';
    return _buildPortalGiftCardPreview(msg, userGift, comment);
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

    final cardPreview = _buildPortalGiftCardPreview(msg, userGift, comment);

    return Align(
      alignment: Alignment.center,
      child: Builder(
        builder: (giftContext) {
          return GestureDetector(
            onLongPress: () => _showMessageContextMenu(
              msg,
              bubbleContext: giftContext,
              customBubbleWidget: cardPreview,
              isMe: isMe,
            ),
            onSecondaryTap: () => _showMessageContextMenu(
              msg,
              bubbleContext: giftContext,
              customBubbleWidget: cardPreview,
              isMe: isMe,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
            // 1. Top Pill: "Вы отправили ... подарок стоимостью / 50 Sparks"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xE61A1B24),
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

            const SizedBox(height: 10),

            // 2. Ultra-rounded Frosted Glass Card
            Container(
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

                      // Button "Посмотреть" (Transparent, darker than card)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Material(
                          color: const Color(0x66000000), // Darker transparent
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
                      ],
                    ),
                  ),

                  // 3. Reactions badge directly under the gift card!
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildReactionsBadge(msg, isMe),
                  ),
                ],
              ),
            ),
          );
        },
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

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() {
        _showEmojiPicker = false;
      });
      _textFocusNode.requestFocus();
    } else {
      _textFocusNode.unfocus();
      setState(() {
        _showEmojiPicker = true;
      });
    }
  }

  void _handleEmojiSelected(String emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    final newOffset = start + emoji.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    _handleTextChange(newText);
  }

  void _handleEmojiBackspace() {
    final text = _textController.text;
    final selection = _textController.selection;
    if (text.isEmpty) return;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    if (start > 0 && start == end) {
      final beforeCursor = Characters(text.substring(0, start));
      final dropped = beforeCursor.skipLast(1).toString();
      final afterCursor = text.substring(end);
      _textController.value = TextEditingValue(
        text: dropped + afterCursor,
        selection: TextSelection.collapsed(offset: dropped.length),
      );
    } else if (start != end) {
      final newText = text.replaceRange(start, end, '');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    }
    _handleTextChange(_textController.text);
  }

  Future<void> _handleStickerSelected(String assetPath) async {
    if (_isSendingSticker) return;
    _isSendingSticker = true;
    HapticFeedback.mediumImpact();
    final provider = context.read<ChatProvider>();
    final payload = '[PORTAL_STICKER]:{"asset":"$assetPath"}';
    final replyId = _replyingToMessage?.id;
    if (_replyingToMessage != null) {
      setState(() {
        _replyingToMessage = null;
      });
    }
    try {
      await provider.sendMessage(widget.chat.id, payload, replyToMessageId: replyId);
      _scrollToBottom();
    } catch (_) {} finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _isSendingSticker = false;
        }
      });
    }
  }

  // ===========================================================================
  // FLOATING INPUT BAR (No podlozhka, 3 floating widgets)
  // ===========================================================================
  Widget _buildFloatingInputBar() {
    final hasText = _textController.text.trim().isNotEmpty;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = bottomInset > 0
        ? 8.0
        : (mediaQuery.padding.bottom > 0 ? mediaQuery.padding.bottom : 10.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_editingMessage != null)
          _buildEditBar()
        else if (_replyingToMessage != null)
          _buildReplyBar(),
        Padding(
          padding: EdgeInsets.fromLTRB(10, 6, 10, _showEmojiPicker ? 6.0 : bottomPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!_isRecordingVoice) ...[
                // 1. Слева: круглая кнопка скрепки (анимированная как в Telegram)
                GestureDetector(
                  onTap: _openPhotoGallerySheet,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _pickerProgress,
                    builder: (context, progress, child) {
                      // При открытии фото-меню кнопка плавно растворяется в рождающийся круг шторки (первые 25% прогресса)
                      final double t = (progress * 4.0).clamp(0.0, 1.0);
                      final double btnFade = 1.0 - t;
                      final double btnScale = 1.0 - (0.18 * t);
                      final double rotateAngle = -math.pi / 4 * (1.0 - t);

                      return Opacity(
                        opacity: btnFade,
                        child: Transform.scale(
                          scale: btnScale,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: progress > 0.05
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFF191919),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x1AFFFFFF),
                                width: 1.0,
                              ),
                            ),
                            child: Center(
                              child: Transform.rotate(
                                angle: rotateAngle,
                                child: const Icon(
                                  Icons.attach_file_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Посередине: красивый пузырь с текстом Сообщение
                Expanded(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 40,
                        maxHeight: 140,
                      ),
                      padding: const EdgeInsets.only(left: 16, right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF191919),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0x1AFFFFFF),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: _textController.text.contains('\n')
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center,
                        children: [
                          // Текстовое поле ввода
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              focusNode: _textFocusNode,
                              onChanged: _handleTextChange,
                              contextMenuBuilder: TelegramTextSelectionToolbar.buildToolbar,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 1,
                              maxLines: 6,
                              textInputAction: TextInputAction.newline,
                              scrollPhysics: const BouncingScrollPhysics(),
                              textAlignVertical: TextAlignVertical.center,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Сообщение',
                                hintStyle: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Color(0xFF8E8E93),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -0.2,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // Смайлик справа внутри пузыря (прижат к низу как в Telegram)
                          GestureDetector(
                            onTap: _toggleEmojiPicker,
                            child: SizedBox(
                              height: 40,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(
                                    _showEmojiPicker
                                        ? Icons.keyboard_rounded
                                        : Icons.sentiment_satisfied_rounded,
                                    color: _showEmojiPicker
                                        ? const Color(0xFF007AFF)
                                        : const Color(0xFF929292),
                                    size: 22,
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
              ] else ...[
                // Индикатор записи голосового сообщения
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0x1AFFFFFF),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        FadeTransition(
                          opacity: _blinkAnimation,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatRecordingTime(_recordElapsedMs),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 14,
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
                                    fontSize: 12,
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
              const SizedBox(width: 8),

              // 3. Справа: круглая кнопка голосового сообщения / отправки
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: hasText
                    ? GestureDetector(
                        key: const ValueKey('send_btn'),
                        onTap: _handleSend,
                        child: ScaleTransition(
                          scale: _sendBtnScaleAnim,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2AABEE),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SlideTransition(
                                position: _sendBtnArrowSlideAnim,
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : GestureDetector(
                        key: const ValueKey('mic_btn'),
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
                          width: 40,
                          height: 40,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
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
                                          width: 44 + (34 * v1),
                                          height: 44 + (34 * v1),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withOpacity((1.0 - v1) * 0.22),
                                          ),
                                        ),
                                        Container(
                                          width: 44 + (34 * v2),
                                          height: 44 + (34 * v2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withOpacity((1.0 - v2) * 0.22),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                width: _isRecordingVoice ? 50 : 40,
                                height: _isRecordingVoice ? 50 : 40,
                                decoration: BoxDecoration(
                                  color: _isRecordingVoice ? Colors.white : const Color(0xFF191919),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isRecordingVoice ? Colors.transparent : const Color(0x1AFFFFFF),
                                    width: 1.0,
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
                                    size: _isRecordingVoice ? 26 : 21,
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
        if (_showEmojiPicker)
          PortalEmojiPicker(
            onEmojiSelected: _handleEmojiSelected,
            onBackspacePressed: _handleEmojiBackspace,
            onStickerSelected: _handleStickerSelected,
            bottomPadding: mediaQuery.padding.bottom,
          ),
      ],
    );
  }

  Future<void> _openPhotoGallerySheet() async {
    FocusScope.of(context).unfocus();
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = bottomInset > 0
        ? 8.0
        : (mediaQuery.padding.bottom > 0 ? mediaQuery.padding.bottom : 10.0);

    await PhotoPickerBottomSheet.show(
      context,
      btnLeft: 10.0,
      btnBottom: bottomPadding,
      btnSize: 40.0,
      btnRadius: 20.0,
      onProgressChanged: (p) {
        _pickerProgress.value = p;
      },
      onSend: (files, caption) async {
        Navigator.of(context).pop();
        await _sendSelectedPhotos(files, caption);
      },
      onOpenGifts: () {
        SendGiftModal.show(
          context,
          chat: widget.chat,
          recipientId: widget.chat.participantId ?? widget.chat.id,
          recipientUsername: widget.chat.username,
        );
      },
    );
    if (mounted) {
      _pickerProgress.value = 0.0;
    }
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

  void _showFullscreenGallery(List<String> imageUrls, int initialIndex) {
    FullscreenGalleryViewer.show(context, imageUrls: imageUrls, initialIndex: initialIndex);
  }
}

// ===========================================================================
// GIFT ARTIFACT MODAL WIDGET
// ===========================================================================
class _GiftArtifactModal extends StatefulWidget {
  final Chat chat;
  final BuildContext parentContext;
  final VoidCallback onGiftTriggered;

  const _GiftArtifactModal({
    required this.chat,
    required this.parentContext,
    required this.onGiftTriggered,
  });

  @override
  State<_GiftArtifactModal> createState() => _GiftArtifactModalState();
}

class _GiftArtifactModalState extends State<_GiftArtifactModal> {
  String _formatArtifacts(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$count артефактов';
    if (mod10 == 1) return '$count артефакт';
    if (mod10 >= 2 && mod10 <= 4) return '$count артефакта';
    return '$count артефактов';
  }

  Future<void> _handleGift() async {
    final auth = widget.parentContext.read<AuthProvider>();
    final user = auth.currentUser;
    final int currentArtifacts = user?.artifacts ?? 0;

    if (currentArtifacts <= 0) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: const Text(
            'У вас нет артефактов. Оформите Premium подписку, чтобы получить 3 артефакта!',
          ),
          backgroundColor: const Color(0xFF2C2C2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // 1. Trigger Telegram-style flight animation into header
    widget.onGiftTriggered();

    // 2. Close modal card smoothly
    Navigator.of(context).pop();

    // 3. Deduct locally and transfer on backend
    final chatProvider = widget.parentContext.read<ChatProvider>();
    auth.deductArtifacts(1);

    try {
      final res = await chatProvider.giftArtifactToChannel(widget.chat.id);
      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'Ошибка передачи артефакта');
      }
    } catch (e) {
      auth.setArtifacts(currentArtifacts);
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.parentContext.watch<AuthProvider>();
    final int userArtifacts = auth.currentUser?.artifacts ?? 0;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: const Color(0xEB1A1A1C),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0x22FFFFFF),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Center Animated Logo
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Lottie.asset(
                        'lib/assets/material/artefact.json',
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Bold Title "Артефакт"
                    const Text(
                      'Артефакт',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Description text
                    const Text(
                      'Артефакты дарятся для улучшения возможностей канала, даря его вы поможете авторам каналов стилизовать их',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 13.5,
                        color: Color(0xFF9E9E9E),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Maximally rounded pill: "у вас (кол-во) артефактов"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0x1AFFFFFF),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        'У вас ${_formatArtifacts(userArtifacts)}',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Long maximally rounded white button "Подарить"
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        onPressed: _handleGift,
                        child: const Text(
                          'Подарить',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: -0.2,
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
      ),
    );
  }
}

// ===========================================================================
// FLYING ARTIFACT OVERLAY ANIMATION (TELEGRAM-LEVEL POLISH)
// ===========================================================================
class _FlyingArtifactOverlay extends StatefulWidget {
  final Size screenSize;
  final double topPadding;
  final VoidCallback onImpact;
  final VoidCallback onCompleted;

  const _FlyingArtifactOverlay({
    required this.screenSize,
    required this.topPadding,
    required this.onImpact,
    required this.onCompleted,
  });

  @override
  State<_FlyingArtifactOverlay> createState() => _FlyingArtifactOverlayState();
}

class _FlyingArtifactOverlayState extends State<_FlyingArtifactOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _impactTriggered = false;
  late final List<_SparkleParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );

    final rnd = math.Random();
    _particles = List.generate(24, (i) {
      final angle = (i / 24) * 2 * math.pi + (rnd.nextDouble() - 0.5) * 0.35;
      final speed = 40.0 + rnd.nextDouble() * 65.0;
      final size = 2.5 + rnd.nextDouble() * 3.5;
      final color = i % 3 == 0
          ? const Color(0xFFFFD700)
          : (i % 3 == 1 ? const Color(0xFF2990FF) : Colors.white);
      return _SparkleParticle(
        angle: angle,
        speed: speed,
        size: size,
        color: color,
      );
    });

    _controller.addListener(() {
      if (_controller.value >= 0.70 && !_impactTriggered) {
        _impactTriggered = true;
        widget.onImpact();
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });

    // Slight initial anticipation haptic
    HapticFeedback.mediumImpact();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startY = widget.screenSize.height / 2 - 70;
    final startX = widget.screenSize.width / 2;
    final targetY = widget.topPadding + 29;
    final targetX = widget.screenSize.width / 2;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;

        double currentX = startX;
        double currentY = startY;
        double currentScale = 1.0;
        double currentOpacity = 1.0;
        double rotation = 0.0;

        if (t < 0.20) {
          // Phase 1: Recoil / Anticipation (Отдача назад с усадкой)
          final progress = t / 0.20;
          final eased = Curves.easeOutQuad.transform(progress);
          currentY = startY + (36.0 * math.sin(eased * math.pi / 2));
          currentScale = 1.0 - (0.16 * math.sin(eased * math.pi / 2));
          currentOpacity = 1.0;
        } else if (t < 0.70) {
          // Phase 2: Launch into the header
          final progress = (t - 0.20) / (0.70 - 0.20);
          final eased = Curves.easeInOutCubic.transform(progress);
          final recoilY = startY + 36.0;
          currentY = recoilY + (targetY - recoilY) * eased;
          currentScale = 0.84 + (0.34 - 0.84) * eased;
          rotation = math.sin(progress * math.pi * 2) * 0.14;
          currentOpacity = 1.0;
        } else {
          // Phase 3: Impact with header capsule and dissolve
          final progress = ((t - 0.70) / (1.0 - 0.70)).clamp(0.0, 1.0);
          currentY = targetY;
          currentScale = 0.34 * (1.0 - progress);
          currentOpacity = (1.0 - progress * 2.2).clamp(0.0, 1.0);
        }

        return Stack(
          children: [
            // Shockwave & Particles at Target Header Capsule on Impact (t >= 0.68)
            if (t >= 0.68)
              Positioned(
                left: targetX - 70,
                top: targetY - 70,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(140, 140),
                    painter: _ImpactShockwavePainter(
                      progress: ((t - 0.68) / 0.32).clamp(0.0, 1.0),
                      particles: _particles,
                    ),
                  ),
                ),
              ),

            // The flying Lottie Artifact
            if (currentOpacity > 0.01)
              Positioned(
                left: currentX - (50 * currentScale),
                top: currentY - (50 * currentScale),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: currentOpacity,
                    child: Transform.rotate(
                      angle: rotation,
                      child: Transform.scale(
                        scale: currentScale,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x662990FF),
                                blurRadius: 28 * currentScale,
                                spreadRadius: 4 * currentScale,
                              ),
                              BoxShadow(
                                color: const Color(0x44FFFFFF),
                                blurRadius: 18 * currentScale,
                              ),
                            ],
                          ),
                          child: Lottie.asset(
                            'lib/assets/material/artefact.json',
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SparkleParticle {
  final double angle;
  final double speed;
  final double size;
  final Color color;

  _SparkleParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}

class _ImpactShockwavePainter extends CustomPainter {
  final double progress;
  final List<_SparkleParticle> particles;

  _ImpactShockwavePainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = 14.0 + (56.0 * Curves.easeOutCubic.transform(progress));
    final ringOpacity = (1.0 - progress).clamp(0.0, 1.0);

    // Glowing expanding shockwave rings
    final ringPaint = Paint()
      ..color = const Color(0xCC2990FF).withOpacity(ringOpacity * 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * (1.0 - progress * 0.6);
    canvas.drawCircle(center, ringRadius, ringPaint);

    final innerRingPaint = Paint()
      ..color = Colors.white.withOpacity(ringOpacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(center, ringRadius * 0.72, innerRingPaint);

    // Sparkle particles flying outwards with deceleration
    for (final p in particles) {
      final dist = p.speed * Curves.easeOutQuad.transform(progress);
      final px = center.dx + math.cos(p.angle) * dist;
      final py = center.dy + math.sin(p.angle) * dist;
      final pAlpha = (1.0 - progress).clamp(0.0, 1.0);
      final pPaint = Paint()
        ..color = p.color.withOpacity(pAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), p.size * (1.0 - progress * 0.5), pPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ImpactShockwavePainter oldDelegate) => true;
}

class ForwardedMessageInfo {
  final int senderId;
  final String senderName;
  final String senderAvatar;
  final String cleanText;

  ForwardedMessageInfo({
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.cleanText,
  });
}

class _ForwardMessageModalSheet extends StatefulWidget {
  final Message message;
  final int currentChatId;
  final void Function(Chat targetChat) onForwardToChat;

  const _ForwardMessageModalSheet({
    required this.message,
    required this.currentChatId,
    required this.onForwardToChat,
  });

  @override
  State<_ForwardMessageModalSheet> createState() => _ForwardMessageModalSheetState();
}

class _ForwardMessageModalSheetState extends State<_ForwardMessageModalSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = context.watch<ChatProvider>().chats;
    final filtered = _searchQuery.isEmpty
        ? chats
        : chats.where((c) {
            final q = _searchQuery.toLowerCase();
            return c.title.toLowerCase().contains(q) ||
                (c.username != null && c.username!.toLowerCase().contains(q));
          }).toList();

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF090909),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Верхняя полоска-индикатор
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Верхняя плашка: Слева круглая кнопка с крестиком, по центру "Пересылка", справа отступ для баланса
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Пересылка',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 17,
                      fontWeight: FontWeight.w500, // Средний, не жирный шрифт
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34), // Для идеального центрирования заголовка
                ],
              ),
            ),

            // Поле поиска чатов
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF191919),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x14FFFFFF), width: 0.8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF8E8E93), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 14.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Поиск чатов...',
                          hintStyle: TextStyle(
                            fontFamily: AppTheme.fontText,
                            color: Color(0xFF8E8E93),
                            fontSize: 14.5,
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
                          setState(() => _searchQuery = '');
                        },
                        child: const Icon(Icons.cancel_rounded, color: Color(0xFF8E8E93), size: 16),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Divider(color: Color(0x14FFFFFF), height: 1),

            // Список доступных чатов
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Чаты не найдены',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Color(0xFF8E8E93),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: Color(0x0DFFFFFF),
                        height: 1,
                        indent: 72,
                      ),
                      itemBuilder: (ctx, i) {
                        final chat = filtered[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: AvatarWidget(
                            avatarUrl: chat.avatar,
                            title: chat.title,
                            size: 46,
                            isChannel: chat.isChannel,
                            isSaved: chat.isSaved,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  chat.title,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (chat.isVerified) ...[
                                const SizedBox(width: 4),
                                VerificationBadge(
                                  verification: chat.effectiveVerification,
                                  size: 15,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            chat.displayLastMessage.isNotEmpty
                                ? chat.displayLastMessage
                                : (chat.username != null && chat.username!.isNotEmpty
                                    ? '@${chat.username}'
                                    : 'Нет сообщений'),
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            widget.onForwardToChat(chat);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
