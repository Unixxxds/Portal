import 'package:flutter/material.dart';
import '../theme.dart';

/// Pixel-perfect Telegram iOS typing indicator:
/// Three sequentially pulsing dots (wave left to right) + "печатает"
class TelegramTypingIndicator extends StatefulWidget {
  final Color color;
  final double fontSize;
  final double dotSize;
  final String text;
  final bool showText;
  final MainAxisSize mainAxisSize;

  const TelegramTypingIndicator({
    super.key,
    this.color = const Color(0xFF007AFF),
    this.fontSize = 12.0,
    this.dotSize = 4.5,
    this.text = 'печатает',
    this.showText = true,
    this.mainAxisSize = MainAxisSize.min,
  });

  @override
  State<TelegramTypingIndicator> createState() => _TelegramTypingIndicatorState();
}

class _TelegramTypingIndicatorState extends State<TelegramTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _calculateScale(double t, double phase) {
    final raw = (t - phase) % 1.0;
    final progress = raw < 0 ? raw + 1.0 : raw;
    if (progress <= 0.35) {
      final subT = Curves.easeInOut.transform(progress / 0.35);
      return 0.74 + (1.06 - 0.74) * subT;
    } else if (progress <= 0.70) {
      final subT = Curves.easeInOut.transform((progress - 0.35) / 0.35);
      return 1.06 - (1.06 - 0.74) * subT;
    } else {
      return 0.74;
    }
  }

  double _calculateOpacity(double t, double phase) {
    final raw = (t - phase) % 1.0;
    final progress = raw < 0 ? raw + 1.0 : raw;
    if (progress <= 0.35) {
      final subT = Curves.easeInOut.transform(progress / 0.35);
      return 0.32 + (1.0 - 0.32) * subT;
    } else if (progress <= 0.70) {
      final subT = Curves.easeInOut.transform((progress - 0.35) / 0.35);
      return 1.0 - (1.0 - 0.32) * subT;
    } else {
      return 0.32;
    }
  }

  Widget _buildDot(int index, double t) {
    final phase = index * 0.18;
    final scale = _calculateScale(t, phase);
    final opacity = _calculateOpacity(t, phase);

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Row(
          mainAxisSize: widget.mainAxisSize,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot(0, t),
                  const SizedBox(width: 2.5),
                  _buildDot(1, t),
                  const SizedBox(width: 2.5),
                  _buildDot(2, t),
                ],
              ),
            ),
            if (widget.showText) ...[
              const SizedBox(width: 4.5),
              Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w400,
                  color: widget.color,
                  letterSpacing: -0.08,
                  height: 1.15,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
