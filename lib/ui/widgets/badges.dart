import 'package:flutter/material.dart';

/// Renders either the dev verification badge (verifdev.png) or standard verification badge (userverif.png).
/// Returns SizedBox.shrink() if verification is null or 'none'.
class VerificationBadge extends StatelessWidget {
  final String? verification;
  final double size;

  const VerificationBadge({
    super.key,
    required this.verification,
    this.size = 18.5,
  });

  static bool isVerified(String? v) {
    if (v == null) return false;
    final clean = v.trim().toLowerCase();
    return clean.isNotEmpty &&
        clean != 'none' &&
        clean != 'null' &&
        clean != 'false' &&
        clean != '0';
  }

  static bool isDev(String? v) {
    if (v == null) return false;
    return v.trim().toLowerCase() == 'dev';
  }

  @override
  Widget build(BuildContext context) {
    if (!isVerified(verification)) {
      return const SizedBox.shrink();
    }

    final asset = isDev(verification)
        ? 'lib/assets/verifdev.png'
        : 'lib/assets/userverif.png';

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// Renders the 4-pointed star premium subscriber badge matching lib/assets/premium.svg in blue (#3B98FF).
class PremiumBadge extends StatelessWidget {
  final double size;
  final Color color;

  const PremiumBadge({
    super.key,
    this.size = 18.5,
    this.color = const Color(0xFF3B98FF),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PremiumStarPainter(color: color),
    );
  }
}

class _PremiumStarPainter extends CustomPainter {
  final Color color;
  const _PremiumStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final s = size.width / 24.0;
    final path = Path()
      ..moveTo(12 * s, 1 * s)
      ..cubicTo(10.9 * s, 7.2 * s, 7.2 * s, 10.9 * s, 1 * s, 12 * s)
      ..cubicTo(7.2 * s, 13.1 * s, 10.9 * s, 16.8 * s, 12 * s, 23 * s)
      ..cubicTo(13.1 * s, 16.8 * s, 16.8 * s, 13.1 * s, 23 * s, 12 * s)
      ..cubicTo(16.8 * s, 10.9 * s, 13.1 * s, 7.2 * s, 12 * s, 1 * s)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PremiumStarPainter oldDelegate) =>
      oldDelegate.color != color;
}

