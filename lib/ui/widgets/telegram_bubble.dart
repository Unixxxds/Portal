import 'package:flutter/material.dart';

/// Accurate Telegram Message Bubble shape with authentic curved corner tail.
///
/// Matches Telegram iOS / Android design:
/// - Outgoing (`isMe == true`): Vibrant blue (`#5B65F6`), smooth rounded corners (radius 18),
///   and iconic bottom-right tail with outer sweep and inner concave arch.
/// - Incoming (`isMe == false`): Dark charcoal (`#252332`), smooth rounded corners (radius 18),
///   and iconic bottom-left tail.
class TelegramBubble extends StatelessWidget {
  final Widget child;
  final bool isMe;
  final Color? color;
  final double radius;
  final double tailWidth;
  final EdgeInsetsGeometry? padding;

  const TelegramBubble({
    super.key,
    required this.child,
    required this.isMe,
    this.color,
    this.radius = 18.0,
    this.tailWidth = 9.0,
    this.padding,
  });

  // Authentic colors: outgoing is Telegram blue, incoming is Portal dark grey
  static const Color defaultOutgoingColor = Color(0xFF5B65F6);
  static const Color defaultIncomingColor = Color(0xFF191919);

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? (isMe ? defaultOutgoingColor : defaultIncomingColor);
    final effectivePadding = padding ??
        (isMe
            ? const EdgeInsets.fromLTRB(14, 8, 20, 8) // Extra padding on right for tail
            : const EdgeInsets.fromLTRB(20, 8, 14, 8)); // Extra padding on left for tail

    return CustomPaint(
      painter: TelegramBubblePainter(
        color: effectiveColor,
        isMe: isMe,
        radius: radius,
        tailWidth: tailWidth,
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );
  }
}

/// CustomPainter that renders the Telegram message bubble path.
class TelegramBubblePainter extends CustomPainter {
  final Color color;
  final bool isMe;
  final double radius;
  final double tailWidth;

  const TelegramBubblePainter({
    required this.color,
    required this.isMe,
    this.radius = 18.0,
    this.tailWidth = 9.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildTelegramBubblePath(
      size: size,
      isMe: isMe,
      radius: radius,
      tailWidth: tailWidth,
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);

    if (!isMe) {
      final borderPaint = Paint()
        ..color = const Color(0x14FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..isAntiAlias = true;
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TelegramBubblePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isMe != isMe ||
        oldDelegate.radius != radius ||
        oldDelegate.tailWidth != tailWidth;
  }
}

/// CustomClipper for clipping image/media bubbles to the exact Telegram shape with tail.
class TelegramBubbleClipper extends CustomClipper<Path> {
  final bool isMe;
  final double radius;
  final double tailWidth;

  const TelegramBubbleClipper({
    required this.isMe,
    this.radius = 18.0,
    this.tailWidth = 9.0,
  });

  @override
  Path getClip(Size size) {
    return buildTelegramBubblePath(
      size: size,
      isMe: isMe,
      radius: radius,
      tailWidth: tailWidth,
    );
  }

  @override
  bool shouldReclip(covariant TelegramBubbleClipper oldClipper) {
    return oldClipper.isMe != isMe ||
        oldClipper.radius != radius ||
        oldClipper.tailWidth != tailWidth;
  }
}

/// Mathematical vector path of the Telegram message bubble.
Path buildTelegramBubblePath({
  required Size size,
  required bool isMe,
  double radius = 18.0,
  double tailWidth = 9.0,
}) {
  final path = Path();
  final double w = size.width;
  final double h = size.height;
  final double r = radius.clamp(4.0, h / 2);
  final double tw = tailWidth;

  if (isMe) {
    // -------------------------------------------------------------
    // OUTGOING BUBBLE (Tail at bottom-right)
    // -------------------------------------------------------------
    // 1. Start right after top-left rounded corner
    path.moveTo(r, 0);

    // 2. Top flat edge
    path.lineTo(w - tw - r, 0);

    // 3. Top-right rounded corner
    path.arcToPoint(
      Offset(w - tw, r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 4. Right vertical wall down to where the tail begins
    path.lineTo(w - tw, h - 18.0);

    // 5. Outer smooth curve sweeping down to the sharp tail tip at (w, h)
    path.cubicTo(
      w - tw + 1.0, h - 10.0,
      w - 3.5, h - 2.0,
      w, h,
    );

    // 6. Inner scoop curve from tip (w, h) arching into the bottom edge
    path.cubicTo(
      w - 9.5, h,
      w - 18.5, h - 9.0,
      w - tw - 19.0, h,
    );

    // 7. Bottom flat edge to bottom-left corner
    path.lineTo(r, h);

    // 8. Bottom-left rounded corner
    path.arcToPoint(
      Offset(0, h - r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 9. Left vertical wall
    path.lineTo(0, r);

    // 10. Top-left rounded corner
    path.arcToPoint(
      Offset(r, 0),
      radius: Radius.circular(r),
      clockwise: true,
    );

    path.close();
  } else {
    // -------------------------------------------------------------
    // INCOMING BUBBLE (Tail at bottom-left)
    // -------------------------------------------------------------
    // 1. Start right after top-left corner
    path.moveTo(tw + r, 0);

    // 2. Top flat edge
    path.lineTo(w - r, 0);

    // 3. Top-right rounded corner
    path.arcToPoint(
      Offset(w, r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 4. Right vertical wall
    path.lineTo(w, h - r);

    // 5. Bottom-right rounded corner
    path.arcToPoint(
      Offset(w - r, h),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 6. Bottom flat edge to inner scoop start
    path.lineTo(tw + 19.0, h);

    // 7. Inner scoop curve arching into the tail tip at (0, h)
    path.cubicTo(
      18.5, h - 9.0,
      9.5, h,
      0, h,
    );

    // 8. Outer smooth curve sweeping from tip (0, h) back up to left wall
    path.cubicTo(
      3.5, h - 2.0,
      tw - 1.0, h - 10.0,
      tw, h - 18.0,
    );

    // 9. Left vertical wall
    path.lineTo(tw, r);

    // 10. Top-left rounded corner
    path.arcToPoint(
      Offset(tw + r, 0),
      radius: Radius.circular(r),
      clockwise: true,
    );

    path.close();
  }

  return path;
}

