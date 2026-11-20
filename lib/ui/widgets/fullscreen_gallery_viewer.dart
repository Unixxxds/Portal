import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants.dart';
import '../theme.dart';
import '../../services/media_cache_service.dart';

class FullscreenGalleryViewer {
  static void show(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim, secondaryAnim) => _TelegramPhotoViewerScreen(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (ctx, anim, secondaryAnim, child) {
          final curve = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.90, end: 1.0).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _TelegramPhotoViewerScreen extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _TelegramPhotoViewerScreen({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_TelegramPhotoViewerScreen> createState() =>
      _TelegramPhotoViewerScreenState();
}

class _TelegramPhotoViewerScreenState extends State<_TelegramPhotoViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;

  // Vertical drag state for Telegram-like swipe-to-dismiss
  double _dragOffsetY = 0.0;
  bool _isDismissing = false;
  bool _showControls = true;

  late AnimationController _animController;
  Animation<double>? _dragOffsetAnimation;

  // Track zoom scale for the current image so we don't dismiss when zoomed
  final Map<int, TransformationController> _transformControllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _animController.addListener(() {
      if (_dragOffsetAnimation != null) {
        setState(() {
          _dragOffsetY = _dragOffsetAnimation!.value;
        });
      }
    });

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isDismissing) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TransformationController _getTransformController(int index) {
    if (!_transformControllers.containsKey(index)) {
      _transformControllers[index] = TransformationController();
    }
    return _transformControllers[index]!;
  }

  bool _isCurrentlyZoomed() {
    final controller = _getTransformController(_currentIndex);
    return controller.value.getMaxScaleOnAxis() > 1.04;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isDismissing) return;
    if (_isCurrentlyZoomed()) return;

    if (_animController.isAnimating) {
      _animController.stop();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    if (_isCurrentlyZoomed()) return;

    setState(() {
      _dragOffsetY += details.primaryDelta!;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    if (_isCurrentlyZoomed()) return;

    final velocity = details.primaryVelocity ?? 0.0;
    final absOffset = _dragOffsetY.abs();

    // Telegram threshold: drag > 80px or quick fling > 400px/s
    final shouldDismiss = absOffset > 80 || velocity.abs() > 400;

    if (shouldDismiss) {
      _dismissWithAnimation(velocity);
    } else {
      _springBackToCenter();
    }
  }

  void _dismissWithAnimation(double velocity) {
    _isDismissing = true;
    final screenH = MediaQuery.of(context).size.height;
    final direction = _dragOffsetY != 0
        ? (_dragOffsetY > 0 ? 1.0 : -1.0)
        : (velocity >= 0 ? 1.0 : -1.0);

    final targetY = direction * (screenH * 1.1);

    _dragOffsetAnimation = Tween<double>(
      begin: _dragOffsetY,
      end: targetY,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.duration = const Duration(milliseconds: 180);
    _animController.forward(from: 0.0);
  }

  void _springBackToCenter() {
    _dragOffsetAnimation = Tween<double>(
      begin: _dragOffsetY,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.duration = const Duration(milliseconds: 220);
    _animController.forward(from: 0.0);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _handleDoubleTap(int index) {
    final controller = _getTransformController(index);
    if (controller.value.getMaxScaleOnAxis() > 1.05) {
      controller.value = Matrix4.identity();
    } else {
      controller.value = Matrix4.identity()..scale(2.4);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final absOffset = _dragOffsetY.abs();

    // Dynamically calculate backdrop opacity and scale
    final dragProgress = (absOffset / 320.0).clamp(0.0, 1.0);
    final bgOpacity = (1.0 - dragProgress * 0.95).clamp(0.0, 1.0);
    final photoScale = (1.0 - (absOffset / 1400.0)).clamp(0.72, 1.0);

    // Controls fade out quickly on drag
    final controlsOpacity =
        _showControls ? (1.0 - (absOffset / 90.0)).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _isDismissing) return;
        _dismissWithAnimation(0);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          color: Colors.black.withOpacity(bgOpacity * 0.98),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main Interactive Gallery
              GestureDetector(
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: Transform.translate(
                  offset: Offset(0, _dragOffsetY),
                  child: Transform.scale(
                    scale: photoScale,
                    child: PageView.builder(
                      controller: _pageController,
                      physics: _dragOffsetY != 0.0
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      itemCount: widget.imageUrls.length,
                      onPageChanged: (idx) {
                        setState(() {
                          _currentIndex = idx;
                        });
                      },
                      itemBuilder: (ctx, idx) {
                        final rawU = widget.imageUrls[idx];
                        final isLocal = File(rawU).existsSync();
                        final fullUrl =
                            isLocal ? rawU : AppConstants.formatMediaUrl(rawU);
                        final transformCtrl = _getTransformController(idx);

                        return GestureDetector(
                          onTap: _toggleControls,
                          onDoubleTap: () => _handleDoubleTap(idx),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: InteractiveViewer(
                              transformationController: transformCtrl,
                              minScale: 0.85,
                              maxScale: 4.0,
                              onInteractionEnd: (_) {
                                setState(() {});
                              },
                              child: isLocal
                                  ? Image.file(
                                      File(fullUrl),
                                      fit: BoxFit.contain,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: fullUrl,
                                      cacheManager: MediaCacheService
                                          .instance.cacheManager,
                                      fit: BoxFit.contain,
                                      placeholder: (c, u) => const Center(
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (c, u, s) => const Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          color: Colors.white54,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Top Bar with Close Button & Page Counter (Fades out when dragging)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  ignoring: controlsOpacity <= 0.05,
                  child: Opacity(
                    opacity: controlsOpacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Telegram Circular Close Button
                        GestureDetector(
                          onTap: () {
                            if (!_isDismissing) {
                              _dismissWithAnimation(0);
                            }
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0x33FFFFFF),
                                width: 1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),

                        // Multi-photo indicator
                        if (widget.imageUrls.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0x22FFFFFF),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${_currentIndex + 1} из ${widget.imageUrls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
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
      ),
    );
  }
}
