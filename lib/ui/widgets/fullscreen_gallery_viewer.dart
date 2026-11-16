import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants.dart';
import '../theme.dart';
import '../../services/media_cache_service.dart';

class FullscreenGalleryViewer {
  static void show(BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (ctx, anim1, anim2) {
          final pageController = PageController(initialPage: initialIndex);
          int currentIndex = initialIndex;

          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return Scaffold(
                backgroundColor: Colors.black.withOpacity(0.95),
                body: Stack(
                  children: [
                    PageView.builder(
                      controller: pageController,
                      itemCount: imageUrls.length,
                      onPageChanged: (idx) =>
                          setModalState(() => currentIndex = idx),
                      itemBuilder: (ctx, idx) {
                        final rawU = imageUrls[idx];
                        final isLocal = File(rawU).existsSync();
                        final fullUrl = isLocal ? rawU : AppConstants.formatMediaUrl(rawU);

                        return Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 3.5,
                            child: isLocal
                                ? Image.file(
                                    File(fullUrl),
                                    fit: BoxFit.contain,
                                  )
                                : CachedNetworkImage(
                                    imageUrl: fullUrl,
                                    cacheManager: MediaCacheService.instance.cacheManager,
                                    fit: BoxFit.contain,
                                    placeholder: (c, u) => const Center(
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                      ),
                                    ),
                                    errorWidget: (c, u, s) => const Center(
                                      child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),

                    // Top Bar: Close Button & Album Counter
                    Positioned(
                      top: MediaQuery.of(ctx).padding.top + 12,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0x33FFFFFF), width: 1),
                              ),
                              child: const Center(
                                child: Icon(Icons.close_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (imageUrls.length > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0x22FFFFFF), width: 1),
                              ),
                              child: Text(
                                '${currentIndex + 1} из ${imageUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

