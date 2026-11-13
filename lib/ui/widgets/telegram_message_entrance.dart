import 'package:flutter/material.dart';

/// Telegram-style entrance animation for newly sent or received message bubbles.
/// Smoothly scales up with spring overshoot, fades in, and slides into place.
class TelegramMessageEntrance extends StatefulWidget {
  final Widget child;
  final bool animate;
  final bool isMe;
  final VoidCallback? onAnimationComplete;

  const TelegramMessageEntrance({
    super.key,
    required this.child,
    this.animate = true,
    this.isMe = true,
    this.onAnimationComplete,
  });

  @override
  State<TelegramMessageEntrance> createState() => _TelegramMessageEntranceState();
}

class _TelegramMessageEntranceState extends State<TelegramMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 270),
    );

    if (widget.animate) {
      _scaleAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutBack,
        ),
      );

      _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.60, curve: Curves.easeOut),
        ),
      );

      _slideAnimation = Tween<Offset>(
        begin: widget.isMe ? const Offset(0.07, 0.22) : const Offset(-0.07, 0.22),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
      );

      _controller.forward().then((_) {
        widget.onAnimationComplete?.call();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment: widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}

