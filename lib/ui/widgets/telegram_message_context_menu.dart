import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/message.dart';
import '../../models/message_reaction.dart';
import '../theme.dart';

class TelegramMessageContextMenu extends StatefulWidget {
  final Message message;
  final Rect bubbleRect;
  final Widget bubbleWidget;
  final bool isMe;
  final bool isCurrentlyPinned;
  final List<MessageReaction> reactions;
  final int currentUserId;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onForward;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  final ValueChanged<String> onReaction;
  final VoidCallback onOpenCustomEmojiPicker;

  const TelegramMessageContextMenu({
    super.key,
    required this.message,
    required this.bubbleRect,
    required this.bubbleWidget,
    required this.isMe,
    required this.isCurrentlyPinned,
    required this.reactions,
    required this.currentUserId,
    required this.onReply,
    required this.onCopy,
    required this.onPin,
    required this.onForward,
    this.onEdit,
    required this.onDelete,
    required this.onSelect,
    required this.onReaction,
    required this.onOpenCustomEmojiPicker,
  });

  static Future<void> show({
    required BuildContext context,
    required Message message,
    required Rect bubbleRect,
    required Widget bubbleWidget,
    required bool isMe,
    required bool isCurrentlyPinned,
    required List<MessageReaction> reactions,
    required int currentUserId,
    required VoidCallback onReply,
    required VoidCallback onCopy,
    required VoidCallback onPin,
    required VoidCallback onForward,
    VoidCallback? onEdit,
    required VoidCallback onDelete,
    required VoidCallback onSelect,
    required ValueChanged<String> onReaction,
    required VoidCallback onOpenCustomEmojiPicker,
  }) {
    HapticFeedback.mediumImpact();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: Duration.zero, // Instant unmount on reverse complete
        pageBuilder: (ctx, anim, secAnim) {
          return TelegramMessageContextMenu(
            message: message,
            bubbleRect: bubbleRect,
            bubbleWidget: bubbleWidget,
            isMe: isMe,
            isCurrentlyPinned: isCurrentlyPinned,
            reactions: reactions,
            currentUserId: currentUserId,
            onReply: onReply,
            onCopy: onCopy,
            onPin: onPin,
            onForward: onForward,
            onEdit: onEdit,
            onDelete: onDelete,
            onSelect: onSelect,
            onReaction: onReaction,
            onOpenCustomEmojiPicker: onOpenCustomEmojiPicker,
          );
        },
      ),
    );
  }

  @override
  State<TelegramMessageContextMenu> createState() => _TelegramMessageContextMenuState();
}

class _TelegramMessageContextMenuState extends State<TelegramMessageContextMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _blurAnim;
  late final Animation<double> _dimAnim;
  late final Animation<double> _reactionBarScale;
  late final Animation<double> _reactionBarFade;
  late final Animation<double> _menuScale;
  late final Animation<double> _menuFade;
  late final Animation<Offset> _menuSlide;
  late final Animation<double> _isolatedBubbleFade;

  // Exact quick reactions matching iOS Telegram and user reference image
  static const List<String> _quickReactions = [
    '❤️',
    '👌',
    '🔥',
    '😢',
    '🎉',
    '❤️‍🔥',
    '😱',
  ];

  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 170),
    );

    _blurAnim = Tween<double>(begin: 0.0, end: 24.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    _dimAnim = Tween<double>(begin: 0.0, end: 0.38).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    // Isolated snapshot message bubble fades synchronously
    _isolatedBubbleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Reactions bar spring pop-in
    _reactionBarScale = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.0, 0.9, curve: Curves.easeOutBack),
      ),
    );

    _reactionBarFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Menu scale & slide
    _menuScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.08, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _menuFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.08, 0.75, curve: Curves.easeOut),
      ),
    );

    _menuSlide = Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.08, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _close([VoidCallback? onAfterClosed]) async {
    if (_isClosing) return;
    _isClosing = true;
    await _animCtrl.reverse();
    if (mounted) {
      Navigator.of(context).pop();
      onAfterClosed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Check current user reaction on this message
    final myReaction = widget.reactions.where((r) => r.userId == widget.currentUserId).firstOrNull?.emoji;

    // Dimensions
    const double reactionBarWidth = 328.0;
    const double reactionBarHeight = 46.0;
    const double menuWidth = 245.0;

    // Calculate vertical fit
    final double rawBubbleTop = widget.bubbleRect.top;
    final double rawBubbleBottom = widget.bubbleRect.bottom;
    final double bubbleHeight = widget.bubbleRect.height;

    // Height of menu
    final int itemCount = widget.isMe ? 7 : 6;
    final double menuHeight = (itemCount * 44.0) + 12.0;

    // Safe margins
    final double topLimit = padding.top + 60.0;
    final double bottomLimit = screenSize.height - padding.bottom - 20.0;

    double dyOffset = 0.0;
    // Check if bottom menu fits below bubble
    if (rawBubbleBottom + 12.0 + menuHeight > bottomLimit) {
      final double excess = (rawBubbleBottom + 12.0 + menuHeight) - bottomLimit;
      dyOffset = -excess;

      if (rawBubbleTop + dyOffset - reactionBarHeight - 16.0 < topLimit) {
        dyOffset = topLimit - (rawBubbleTop - reactionBarHeight - 16.0);
      }
    } else if (rawBubbleTop - reactionBarHeight - 16.0 < topLimit) {
      dyOffset = topLimit - (rawBubbleTop - reactionBarHeight - 16.0);
    }

    final double effectiveBubbleTop = rawBubbleTop + dyOffset;
    final double effectiveBubbleBottom = effectiveBubbleTop + bubbleHeight;

    // Reactions bar positioning
    final double reactionBarTop = effectiveBubbleTop - reactionBarHeight - 16.0;
    double reactionBarLeft;
    if (widget.isMe) {
      reactionBarLeft = widget.bubbleRect.right - reactionBarWidth;
    } else {
      reactionBarLeft = widget.bubbleRect.left;
    }
    // Clamp inside screen bounds
    reactionBarLeft = reactionBarLeft.clamp(14.0, screenSize.width - reactionBarWidth - 14.0);

    // Tail cusp & dot positioning (aligned over the corner of the message bubble)
    final double tailX = widget.isMe
        ? (widget.bubbleRect.right - 26.0).clamp(reactionBarLeft + 22.0, reactionBarLeft + reactionBarWidth - 22.0)
        : (widget.bubbleRect.left + 26.0).clamp(reactionBarLeft + 22.0, reactionBarLeft + reactionBarWidth - 22.0);

    final double cuspY = reactionBarTop + reactionBarHeight - 1.0;
    final double dotY = cuspY + 5.5;

    // Action menu positioning
    final double menuTop = effectiveBubbleBottom + 8.0;
    double menuLeft;
    if (widget.isMe) {
      menuLeft = widget.bubbleRect.right - menuWidth;
    } else {
      menuLeft = widget.bubbleRect.left;
    }
    menuLeft = menuLeft.clamp(14.0, screenSize.width - menuWidth - 14.0);

    return WillPopScope(
      onWillPop: () async {
        await _close();
        return false;
      },
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. BLURRED BACKDROP
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _close(),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: _blurAnim.value,
                        sigmaY: _blurAnim.value,
                      ),
                      child: Container(
                        color: Colors.black.withOpacity(_dimAnim.value),
                      ),
                    ),
                  ),
                ),

                // 2. ISOLATED MESSAGE BUBBLE (Fades in/out smoothly so no duplicate remains)
                Positioned(
                  left: widget.bubbleRect.left,
                  top: effectiveBubbleTop,
                  width: widget.bubbleRect.width,
                  height: widget.bubbleRect.height,
                  child: IgnorePointer(
                    ignoring: true,
                    child: FadeTransition(
                      opacity: _isolatedBubbleFade,
                      child: widget.bubbleWidget,
                    ),
                  ),
                ),

                // 3. QUICK REACTIONS BAR (TOP - Translucent Frosted Glass)
                Positioned(
                  left: reactionBarLeft,
                  top: reactionBarTop,
                  width: reactionBarWidth,
                  height: reactionBarHeight,
                  child: Transform.scale(
                    scale: _reactionBarScale.value,
                    alignment: widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
                    child: Opacity(
                      opacity: _reactionBarFade.value,
                      child: _buildFrostedQuickReactionsBar(myReaction),
                    ),
                  ),
                ),

                // 3.1 Thought bubble tail: Cusp on bar bottom + 1 circle bubble dot below
                if (_reactionBarFade.value > 0.2) ...[
                  // Downward Cusp attached to the bar
                  Positioned(
                    left: tailX - 6.0,
                    top: cuspY,
                    child: Opacity(
                      opacity: _reactionBarFade.value,
                      child: CustomPaint(
                        size: const Size(12, 5.5),
                        painter: _TailCuspPainter(
                          color: const Color(0xB81C1C22),
                          borderColor: const Color(0x38FFFFFF),
                        ),
                      ),
                    ),
                  ),

                  // Floating circle bubble dot (8x8) pointing to message
                  Positioned(
                    left: tailX - 4.0,
                    top: dotY,
                    child: Opacity(
                      opacity: _reactionBarFade.value,
                      child: ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xB81C1C22),
                              border: Border.all(color: const Color(0x38FFFFFF), width: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // 4. ACTION CONTEXT MENU (BOTTOM - Translucent Frosted Glass)
                Positioned(
                  left: menuLeft,
                  top: menuTop,
                  width: menuWidth,
                  child: SlideTransition(
                    position: _menuSlide,
                    child: Transform.scale(
                      scale: _menuScale.value,
                      alignment: widget.isMe ? Alignment.topRight : Alignment.topLeft,
                      child: Opacity(
                        opacity: _menuFade.value,
                        child: _buildFrostedActionMenuCard(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // QUICK REACTIONS BAR (Translucent, Frosted Glass)
  // ===========================================================================
  Widget _buildFrostedQuickReactionsBar(String? myReaction) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xB81C1C22), // Translucent dark glass
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x38FFFFFF), width: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ..._quickReactions.asMap().entries.map((entry) {
                final int index = entry.key;
                final String emoji = entry.value;
                final bool isSelected = myReaction == emoji;

                final double start = (index * 0.04).clamp(0.0, 0.4);
                final double end = (start + 0.5).clamp(0.0, 1.0);
                final emojiAnim = CurvedAnimation(
                  parent: _animCtrl,
                  curve: Interval(start, end, curve: Curves.easeOutBack),
                );

                return ScaleTransition(
                  scale: emojiAnim,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _close(() => widget.onReaction(emoji));
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0x40FFFFFF) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style: const TextStyle(
                          fontSize: 21,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Expand Chevron Button to pick any emoji
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _close(() => widget.onOpenCustomEmojiPicker());
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0x28FFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x22FFFFFF), width: 0.8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: Colors.white,
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
  // ACTION CONTEXT MENU CARD (Translucent, Frosted Glass)
  // ===========================================================================
  Widget _buildFrostedActionMenuCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xC41B1B20), // Translucent dark frosted glass
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x2BFFFFFF), width: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Ответить
              _buildActionItem(
                icon: Icons.reply_rounded,
                title: 'Ответить',
                onTap: () => _close(widget.onReply),
              ),

              // 2. Скопировать
              _buildActionItem(
                icon: Icons.copy_rounded,
                title: 'Скопировать',
                onTap: () => _close(widget.onCopy),
              ),

              // 3. Закрепить / Открепить
              _buildActionItem(
                icon: Icons.push_pin_outlined,
                title: widget.isCurrentlyPinned ? 'Открепить' : 'Закрепить',
                onTap: () => _close(widget.onPin),
              ),

              // 4. Переслать
              _buildActionItem(
                icon: Icons.reply_rounded,
                flipIcon: true,
                title: 'Переслать',
                onTap: () => _close(widget.onForward),
              ),

              // 5. Редактировать (если сообщение пользователя)
              if (widget.isMe && widget.onEdit != null)
                _buildActionItem(
                  icon: Icons.edit_outlined,
                  title: 'Редактировать',
                  onTap: () => _close(widget.onEdit!),
                ),

              // 6. Удалить
              _buildActionItem(
                icon: Icons.delete_outline_rounded,
                title: 'Удалить',
                isDestructive: true,
                onTap: () => _close(widget.onDelete),
              ),

              // Divider
              Container(
                height: 0.7,
                color: const Color(0x1FFFFFFF),
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              ),

              // 7. Выбрать
              _buildActionItem(
                icon: Icons.check_circle_outline_rounded,
                title: 'Выбрать',
                onTap: () => _close(widget.onSelect),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool flipIcon = false,
  }) {
    final Color itemColor = isDestructive ? const Color(0xFFFF453A) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        highlightColor: const Color(0x1AFFFFFF),
        splashColor: const Color(0x22FFFFFF),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (flipIcon)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(3.14159),
                  child: Icon(icon, size: 20, color: itemColor),
                )
              else
                Icon(icon, size: 20, color: itemColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: itemColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Downward cusp connecting the reactions bar to the message bubble
class _TailCuspPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _TailCuspPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.45, size.width * 0.5, size.height);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.45, size.width, 0);
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final borderPath = Path();
    borderPath.moveTo(0, 0);
    borderPath.quadraticBezierTo(size.width * 0.25, size.height * 0.45, size.width * 0.5, size.height);
    borderPath.quadraticBezierTo(size.width * 0.75, size.height * 0.45, size.width, 0);
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
