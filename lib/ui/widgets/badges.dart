import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// Renders the dev verification badge (verifdev.png), artist badge (artistverif.png), or standard verification badge (userverif.png).
/// Returns SizedBox.shrink() if verification is null or 'none'.
class VerificationBadge extends StatelessWidget {
  final String? verification;
  final double size;
  final Color? color;
  final double? opacity;
  final bool interactive;

  const VerificationBadge({
    super.key,
    required this.verification,
    this.size = 18.5,
    this.color,
    this.opacity,
    this.interactive = true,
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

  static bool isArtist(String? v) {
    if (v == null) return false;
    return v.trim().toLowerCase() == 'artist';
  }

  static String getAsset(String? v) {
    final clean = v?.trim().toLowerCase();
    if (clean == 'dev') return 'lib/assets/verifdev.png';
    if (clean == 'artist') return 'lib/assets/artistverif.png';
    return 'lib/assets/userverif.png';
  }

  /// Displays an animated popover above/below the target widget explaining the badge status.
  static void showVerificationPopover(
      BuildContext context, String? verification) {
    if (!isVerified(verification)) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final targetOffset = renderBox.localToGlobal(Offset.zero);
    final targetSize = renderBox.size;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (ctx) => _VerificationPopoverOverlay(
        targetOffset: targetOffset,
        targetSize: targetSize,
        verification: verification,
        onDismiss: () {
          entry?.remove();
          entry = null;
        },
      ),
    );

    overlay.insert(entry!);
  }

  @override
  Widget build(BuildContext context) {
    if (!isVerified(verification)) {
      return const SizedBox.shrink();
    }

    final asset = getAsset(verification);

    Widget img = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: color != null ? BlendMode.srcIn : null,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

    if (opacity != null) {
      img = Opacity(opacity: opacity!, child: img);
    }

    if (!interactive) {
      return img;
    }

    return Builder(
      builder: (badgeContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showVerificationPopover(badgeContext, verification),
        child: img,
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  final bool isDownwards;

  _TrianglePainter({required this.color, required this.isDownwards});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isDownwards) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
      path.close();
    } else {
      path.moveTo(size.width / 2, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VerificationPopoverOverlay extends StatefulWidget {
  final Offset targetOffset;
  final Size targetSize;
  final String? verification;
  final VoidCallback onDismiss;

  const _VerificationPopoverOverlay({
    required this.targetOffset,
    required this.targetSize,
    required this.verification,
    required this.onDismiss,
  });

  @override
  State<_VerificationPopoverOverlay> createState() =>
      _VerificationPopoverOverlayState();
}

class _VerificationPopoverOverlayState
    extends State<_VerificationPopoverOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
    HapticFeedback.lightImpact();
  }

  Future<void> _handleDismiss() async {
    if (!_controller.isAnimating) {
      await _controller.reverse();
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const popoverWidth = 270.0;

    final targetCenter = widget.targetOffset.dx + widget.targetSize.width / 2;
    var popoverLeft = targetCenter - popoverWidth / 2;
    popoverLeft =
        popoverLeft.clamp(14.0, screenSize.width - popoverWidth - 14.0);

    final arrowCenterOffset =
        (targetCenter - popoverLeft).clamp(16.0, popoverWidth - 28.0);

    final isDev = VerificationBadge.isDev(widget.verification);
    final isArtist = VerificationBadge.isArtist(widget.verification);
    final asset = VerificationBadge.getAsset(widget.verification);

    final String title;
    final String description;

    if (isDev) {
      title = 'Разработчик Portal';
      description =
          'Официальный аккаунт разработчиков Portal. Подтверждён специальным знаком команды.';
    } else if (isArtist) {
      title = 'Официальный артист';
      description =
          'Подтверждённый аккаунт музыканта или автора контента в Portal.';
    } else {
      title = 'Официальный аккаунт';
      description =
          'Этот аккаунт подтверждён представителями Portal как официальный.';
    }

    final isAbove = widget.targetOffset.dy > 130;
    const arrowHeight = 7.0;
    const arrowWidth = 14.0;

    return Stack(
      children: [
        // Transparent barrier to dismiss on tap
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Popover content
        Positioned(
          left: popoverLeft,
          top: isAbove
              ? null
              : widget.targetOffset.dy + widget.targetSize.height + 6,
          bottom:
              isAbove ? screenSize.height - widget.targetOffset.dy + 6 : null,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  alignment:
                      isAbove ? Alignment.bottomCenter : Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: _handleDismiss,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isAbove)
                    Padding(
                      padding: EdgeInsets.only(
                          left: arrowCenterOffset - arrowWidth / 2),
                      child: CustomPaint(
                        size: const Size(arrowWidth, arrowHeight),
                        painter: _TrianglePainter(
                            color: const Color(0xFF1E1E22), isDownwards: false),
                      ),
                    ),
                  Container(
                    width: popoverWidth,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0x33FFFFFF), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              asset,
                              width: 19,
                              height: 19,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withOpacity(0.72),
                            height: 1.35,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAbove)
                    Padding(
                      padding: EdgeInsets.only(
                          left: arrowCenterOffset - arrowWidth / 2),
                      child: CustomPaint(
                        size: const Size(arrowWidth, arrowHeight),
                        painter: _TrianglePainter(
                            color: const Color(0xFF1E1E22), isDownwards: true),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
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
