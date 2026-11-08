import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/chat.dart';
import '../../models/message.dart';
import '../../models/post_comment.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';

class PostCommentsScreen extends StatefulWidget {
  final Chat channel;
  final Message post;
  final ValueChanged<int>? onCommentsCountChanged;

  const PostCommentsScreen({
    super.key,
    required this.channel,
    required this.post,
    this.onCommentsCountChanged,
  });

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<PostComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  int _viewsCount = 1;

  @override
  void initState() {
    super.initState();
    _viewsCount = widget.post.viewsCount > 0 ? widget.post.viewsCount : 1;
    _loadComments();
    _registerPostView();
  }

  void _registerPostView() {
    if (widget.post.id > 0) {
      ApiService.instance.viewMessage(widget.post.id).then((serverViews) {
        if (serverViews != null && mounted) {
          setState(() {
            _viewsCount = serverViews;
          });
          context.read<ChatProvider>().updateMessageViews(widget.post.id, serverViews);
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService.instance.getPostComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = list;
          _isLoading = false;
        });
        widget.onCommentsCountChanged?.call(list.length);
        context.read<ChatProvider>().updateMessageCommentsCount(widget.post.id, list.length);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    _textController.clear();
    setState(() => _isSending = true);

    // Optimistic comment
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final optimisticComment = PostComment(
      id: tempId,
      messageId: widget.post.id,
      userId: currentUser?.id ?? 0,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
      firstName: currentUser?.firstName ?? '',
      lastName: currentUser?.lastName ?? '',
      username: currentUser?.username ?? '',
      avatar: currentUser?.avatar ?? '',
      verification: currentUser?.effectiveVerification ?? 'none',
      isPremium: currentUser?.isPremium ?? false,
    );

    setState(() {
      _comments.add(optimisticComment);
    });
    _scrollToBottom();
    widget.onCommentsCountChanged?.call(_comments.length);

    try {
      final res = await ApiService.instance.sendPostComment(widget.post.id, text);
      if (res['comment'] is Map<String, dynamic>) {
        final serverComment = PostComment.fromJson(Map<String, dynamic>.from(res['comment'] as Map));
        if (mounted) {
          setState(() {
            final idx = _comments.indexWhere((c) => c.id == tempId);
            if (idx != -1) {
              _comments[idx] = serverComment;
            }
          });
        }
      }
      final newCount = res['commentsCount'] is int ? res['commentsCount'] as int : _comments.length;
      widget.onCommentsCountChanged?.call(newCount);
      if (mounted) {
        context.read<ChatProvider>().updateMessageCommentsCount(widget.post.id, newCount);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _comments.removeWhere((c) => c.id == tempId);
        });
        widget.onCommentsCountChanged?.call(_comments.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.destructive,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      const months = [
        'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
        'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
      ];
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) {
      return 'Сегодня';
    }
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '00:00';
    }
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

  String _getSubtitleText() {
    if (_isLoading && _comments.isEmpty) {
      return 'Комментарии';
    }
    final count = _comments.length;
    if (count == 0) return 'Комментарии';
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 19) return '$count комментариев';
    if (mod10 == 1) return '$count комментарий';
    if (mod10 >= 2 && mod10 <= 4) return '$count комментария';
    return '$count комментариев';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;
    final hasText = _textController.text.trim().isNotEmpty;
    final channel = widget.channel;
    final post = widget.post;

    final rawTitle = channel.title.startsWith('📢') ? channel.title.substring(1).trim() : channel.title;
    final channelTitle = rawTitle.isEmpty ? 'Канал' : rawTitle;

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090909),
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarWidget(
              avatarUrl: channel.avatar,
              title: channelTitle,
              size: 38,
              isChannel: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          channelTitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (channel.isVerified) ...[
                        const SizedBox(width: 5),
                        VerificationBadge(
                          verification: channel.effectiveVerification,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _getSubtitleText(),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF929292),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Color(0xFF929292), size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF929292), size: 22),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // =================================================================
            // COMMENTS & ROOT POST BODY
            // =================================================================
            Expanded(
              child: RefreshIndicator(
                color: Colors.white,
                backgroundColor: const Color(0xFF191919),
                onRefresh: _loadComments,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  children: [
                    // Centered Date Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x33000000),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x14FFFFFF), width: 0.8),
                        ),
                        child: Text(
                          _formatDate(post.createdAt),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB0B0B0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // =========================================================
                    // ROOT POST CARD (Reference Post)
                    // =========================================================
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF191919),
                        borderRadius: BorderRadius.circular(18),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Channel title row
                          Row(
                            children: [
                              Text(
                                channelTitle,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              if (channel.isVerified) ...[
                                const SizedBox(width: 5),
                                VerificationBadge(
                                  verification: channel.effectiveVerification,
                                  size: 14,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Post content
                          _buildRootPostContent(post),
                          const SizedBox(height: 8),

                          // Post footer meta row: Views, Share, Time
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.remove_red_eye_outlined, size: 14, color: Color(0xFF929292)),
                              const SizedBox(width: 4),
                              Text(
                                _formatViewsCount(_viewsCount),
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 11.5,
                                  color: Color(0xFF929292),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(Icons.near_me_rounded, size: 14, color: Color(0xFF929292)),
                              const SizedBox(width: 10),
                              Text(
                                _formatTime(post.createdAt),
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 11.5,
                                  color: Color(0xFF929292),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // =========================================================
                    // COMMENTS LIST OR EMPTY PILL
                    // =========================================================
                    if (_isLoading && _comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    else if (_comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0x33000000),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0x14FFFFFF), width: 0.8),
                            ),
                            child: const Text(
                              'Комментариев пока нет...',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF929292),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      ..._comments.map((comment) => _buildCommentItem(comment, currentUser?.id)),
                  ],
                ),
              ),
            ),

            // =================================================================
            // BOTTOM INPUT BAR (Matching messenger style)
            // =================================================================
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: Color(0xFF090909),
                border: Border(
                  top: BorderSide(color: Color(0x14FFFFFF), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  // Attachment / Paperclip button
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF929292), size: 24),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 8),

                  // Current user avatar preview
                  AvatarWidget(
                    size: 28,
                    avatarUrl: currentUser?.avatar ?? '',
                    title: currentUser?.displayName ?? 'Я',
                  ),
                  const SizedBox(width: 8),

                  // Input pill
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF191919),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _sendComment(),
                              style: const TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Colors.white,
                                fontSize: 14.5,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Сообщение...',
                                hintStyle: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Color(0xFF929292),
                                  fontSize: 14.5,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(
                              Icons.sentiment_satisfied_rounded,
                              color: Color(0xFF929292),
                              size: 20,
                            ),
                            onPressed: () {},
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send button or mic
                  if (hasText)
                    GestureDetector(
                      onTap: _isSending ? null : _sendComment,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3B98FF),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.mic_rounded, color: Color(0xFF929292), size: 24),
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRootPostContent(Message post) {
    final text = post.text.trim();
    if (text.startsWith('[PORTAL_PHOTO]:') || text.contains('[PORTAL_PHOTO]:')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.image_outlined, color: Color(0xFF929292), size: 40),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '📷 Фотография',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white,
              fontSize: 14.5,
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTheme.fontText,
        color: Colors.white,
        fontSize: 14.5,
        height: 1.35,
      ),
    );
  }

  Widget _buildCommentItem(PostComment comment, int? currentUserId) {
    final isMe = currentUserId != null && comment.userId == currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User avatar
          AvatarWidget(
            size: 34,
            avatarUrl: comment.avatar,
            title: comment.displayName,
          ),
          const SizedBox(width: 8),

          // Comment bubble
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF1B2230) : const Color(0xFF191919),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMe ? const Color(0x333B98FF) : const Color(0x14FFFFFF),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author Name & badges row
                  Row(
                    children: [
                      if (comment.isVerified) ...[
                        VerificationBadge(
                          verification: comment.effectiveVerification,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          comment.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isMe ? const Color(0xFF3B98FF) : Colors.white,
                          ),
                        ),
                      ),
                      if (comment.isPremium) ...[
                        const SizedBox(width: 4),
                        const PremiumBadge(size: 15),
                      ],
                      const Spacer(),
                      Text(
                        _formatTime(comment.createdAt),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 11,
                          color: Color(0xFF929292),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Comment text
                  Text(
                    comment.text,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

