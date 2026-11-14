import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A native Telegram-like swipe-to-reply gesture wrapper.
///
/// Supports swiping a message bubble smoothly (both left and right)
/// with physics-based rubber band damping, haptic feedback, a morphing
/// reply circle icon, and a bouncy spring-back animation upon release.
class TelegramSwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const TelegramSwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<TelegramSwipeToReply> createState() => _TelegramSwipeToReplyState();
}

class _TelegramSwipeToReplyState extends State<TelegramSwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<double> _anim;
  double _offset = 0.0;
  bool _thresholdReached = false;

  static const double _threshold = 46.0;
  static const double _maxOffset = 76.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _animController.addListener(() {
      setState(() {
        _offset = _anim.value;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _animController.stop();
    _thresholdReached = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    final delta = details.primaryDelta ?? 0.0;
    if (delta == 0.0) return;

    double newOffset;
    if (_offset <= 0) {
      if (delta < 0) {
        // Dragging left: apply rubber-band damping
        final factor = (1.0 - (_offset.abs() / (_maxOffset * 1.4))).clamp(0.25, 1.0);
        newOffset = (_offset + delta * factor).clamp(-_maxOffset, 0.0);
      } else {
        newOffset = (_offset + delta).clamp(-_maxOffset, _maxOffset);
      }
    } else {
      if (delta > 0) {
        // Dragging right: apply rubber-band damping
        final factor = (1.0 - (_offset.abs() / (_maxOffset * 1.4))).clamp(0.25, 1.0);
        newOffset = (_offset + delta * factor).clamp(0.0, _maxOffset);
      } else {
        newOffset = (_offset + delta).clamp(-_maxOffset, _maxOffset);
      }
    }

    if (!_thresholdReached && newOffset.abs() >= _threshold) {
      _thresholdReached = true;
      HapticFeedback.lightImpact();
    } else if (_thresholdReached && newOffset.abs() < _threshold) {
      _thresholdReached = false;
    }

    setState(() {
      _offset = newOffset;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    if (_thresholdReached) {
      widget.onReply();
    }
    _animateBack();
  }

  void _onHorizontalDragCancel() {
    if (!widget.enabled) return;
    _animateBack();
  }

  void _animateBack() {
    _anim = Tween<double>(begin: _offset, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward(from: 0.0);
    _thresholdReached = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_offset.abs() / _threshold).clamp(0.0, 1.0);
    final isLeft = _offset < 0; // dragging left (reveals icon on right)

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Reveal Telegram reply icon circle behind the bubble
        if (_offset != 0.0)
          Positioned(
            left: isLeft ? null : 14.0,
            right: isLeft ? 14.0 : null,
            child: Opacity(
              opacity: (progress * 1.4).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.65 + (0.35 * progress) + (_thresholdReached ? 0.12 : 0.0),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _thresholdReached
                        ? const Color(0xFF2A85FF)
                        : const Color(0xFF2C2C2E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (_thresholdReached)
                        BoxShadow(
                          color: const Color(0xFF2A85FF).withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.reply_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Message bubble with translation and drag gesture
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: _onHorizontalDragCancel,
            behavior: HitTestBehavior.translucent,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

