import 'dart:math' as math;
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

    _blurAnim = Tween<double>(begin: 0.0, end: 28.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    _dimAnim = Tween<double>(begin: 0.0, end: 0.50).animate(
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

  double _safeClamp(double val, double min, double max) {
    if (min > max) {
      return (min + max) / 2.0;
    }
    return val.clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Check current user reaction on this message
    final myReaction = widget.reactions.where((r) => r.userId == widget.currentUserId).firstOrNull?.emoji;

    // Dimensions - dynamically clamped to fit even small 320-360dp phone screens safely
    final double maxBarWidth = math.min(338.0, screenSize.width - 20.0);
    final double reactionBarWidth = _safeClamp(maxBarWidth, 240.0, 338.0);
    const double reactionBarHeight = 50.0;
    final double menuWidth = math.min(250.0, screenSize.width - 24.0);

    // Guard against NaN/infinite bubbleRect
    Rect safeBubbleRect = widget.bubbleRect;
    if (safeBubbleRect.left.isNaN ||
        safeBubbleRect.top.isNaN ||
        safeBubbleRect.width.isNaN ||
        safeBubbleRect.height.isNaN ||
        safeBubbleRect.isEmpty) {
      safeBubbleRect = Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height / 2),
        width: math.min(screenSize.width * 0.75, 260.0),
        height: 60,
      );
    }

    // Calculate vertical fit
    final double rawBubbleTop = safeBubbleRect.top;
    final double rawBubbleBottom = safeBubbleRect.bottom;
    final double bubbleHeight = safeBubbleRect.height;

    // Height of menu
    final int itemCount = widget.isMe ? 7 : 6;
    final double menuHeight = (itemCount * 44.0) + 14.0;

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
      reactionBarLeft = safeBubbleRect.right - reactionBarWidth;
    } else {
      reactionBarLeft = safeBubbleRect.left;
    }
    // Clamp inside screen bounds safely without lower > upper exceptions
    final double maxBarLeft = math.max(10.0, screenSize.width - reactionBarWidth - 10.0);
    reactionBarLeft = _safeClamp(reactionBarLeft, 10.0, maxBarLeft);

    // Tail cusp & dot positioning (aligned over the corner of the message bubble)
    final double minTail = reactionBarLeft + 24.0;
    final double maxTail = math.max(minTail, reactionBarLeft + reactionBarWidth - 24.0);
    final double tailX = widget.isMe
        ? _safeClamp(safeBubbleRect.right - 34.0, minTail, maxTail)
        : _safeClamp(safeBubbleRect.left + 34.0, minTail, maxTail);

    final double cuspY = reactionBarTop + reactionBarHeight - 0.5;
    final double dotY = cuspY + 11.0;

    // Action menu positioning
    final double menuTop = effectiveBubbleBottom + 8.0;
    double menuLeft;
    if (widget.isMe) {
      menuLeft = safeBubbleRect.right - menuWidth;
    } else {
      menuLeft = safeBubbleRect.left;
    }
    final double maxMenuLeft = math.max(10.0, screenSize.width - menuWidth - 10.0);
    menuLeft = _safeClamp(menuLeft, 10.0, maxMenuLeft);

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
            // Guard sigmaX against 0.0 division-by-zero on Android Skia/Impeller
            final double blurSigma = math.max(0.001, _blurAnim.value);

            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. BLURRED BACKDROP (Wrapped in ClipRect to prevent unbound buffer white-out on Android)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _close(),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurSigma,
                          sigmaY: blurSigma,
                        ),
                        child: Container(
                          color: Colors.black.withOpacity(_dimAnim.value),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. ISOLATED MESSAGE BUBBLE (Fades in/out smoothly so no duplicate remains)
                Positioned(
                  left: safeBubbleRect.left,
                  top: effectiveBubbleTop,
                  width: safeBubbleRect.width,
                  height: safeBubbleRect.height,
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
                      child: _buildFrostedQuickReactionsBar(myReaction, reactionBarWidth),
                    ),
                  ),
                ),

                // 3.1 Thought bubble tail: Cusp on bar bottom + 1 circle bubble dot below
                if (_reactionBarFade.value > 0.2) ...[
                  // Downward Cusp attached directly to the bar bottom
                  Positioned(
                    left: tailX - 8.0,
                    top: cuspY,
                    child: Opacity(
                      opacity: _reactionBarFade.value,
                      child: CustomPaint(
                        size: const Size(16.0, 8.5),
                        painter: _TailCuspPainter(
                          color: const Color(0xD61E1E26),
                          borderColor: const Color(0x30FFFFFF),
                        ),
                      ),
                    ),
                  ),

                  // Floating circle bubble dot (7.5x7.5) pointing to message (no heavy nested BackdropFilter)
                  Positioned(
                    left: tailX - 3.75,
                    top: dotY,
                    child: Opacity(
                      opacity: _reactionBarFade.value,
                      child: Container(
                        width: 7.5,
                        height: 7.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xD61E1E26),
                          border: Border.all(color: const Color(0x30FFFFFF), width: 0.85),
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
  Widget _buildFrostedQuickReactionsBar(String? myReaction, double barWidth) {
    final double itemSize = barWidth < 300 ? 30.0 : 36.0;
    final double emojiFontSize = barWidth < 300 ? 19.0 : 23.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xD61E1E26), // Translucent dark glass
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x30FFFFFF), width: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ..._quickReactions.asMap().entries.map((entry) {
                final int index = entry.key;
                final String emoji = entry.value;
                final bool isSelected = myReaction == emoji;
                // Highlight first emoji by default (or active selected emoji) matching Telegram iOS reference
                final bool isHighlighted = isSelected || (myReaction == null && index == 0);

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
                      width: itemSize,
                      height: itemSize,
                      decoration: BoxDecoration(
                        color: isHighlighted ? const Color(0x40000000) : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isHighlighted
                            ? Border.all(color: const Color(0x24FFFFFF), width: 0.8)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style: TextStyle(
                          fontSize: emojiFontSize,
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
                  width: barWidth < 300 ? 28.0 : 32.0,
                  height: barWidth < 300 ? 28.0 : 32.0,
                  decoration: BoxDecoration(
                    color: const Color(0x28FFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x24FFFFFF), width: 0.8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: barWidth < 300 ? 17.0 : 20.0,
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
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xD61E1E26), // Translucent dark frosted glass matching reaction bar
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x28FFFFFF), width: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 30,
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
                height: 0.6,
                color: const Color(0x1FFFFFFF),
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
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

// Downward cusp connecting the reactions bar seamlessly to the message bubble
class _TailCuspPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _TailCuspPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill the cusp
    final fillPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.45, size.width * 0.5, size.height)
      ..quadraticBezierTo(size.width * 0.72, size.height * 0.45, size.width, 0)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, paint);

    // Stroke ONLY the left and right downward curves (leaving top open to merge with bar border)
    final borderPath = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.45, size.width * 0.5, size.height)
      ..quadraticBezierTo(size.width * 0.72, size.height * 0.45, size.width, 0);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
