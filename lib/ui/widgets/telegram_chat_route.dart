import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Smooth Telegram-style page route for opening regular chats and channels.
///
/// Features:
/// - Snappy 290ms cubic transition matching Telegram iOS / Android
/// - Distinct physical left-edge drop shadow cast onto the underlying chat list
/// - Parallax shift and subtle dimming on secondary navigation
/// - Edge swipe-to-back interactive gesture support
class TelegramChatRoute<T> extends CupertinoPageRoute<T> {
  TelegramChatRoute({
    required super.builder,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 290);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Parallax shift when another screen (e.g. Profile) is pushed on top of this chat
    final secondarySlideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.20, 0.0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    final secondaryDimAnim = Tween<double>(
      begin: 0.0,
      end: 0.20,
    ).animate(secondaryAnimation);

    // Primary entry transition: slide from right with Telegram ease-out curve
    final primarySlideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.2, 0.0, 0.0, 1.0),
      reverseCurve: Curves.easeInCubic,
    ));

    // Shadow on the left edge of the opening chat
    final shadowAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (context, _) {
        return SlideTransition(
          position: secondarySlideAnim,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              SlideTransition(
                position: primarySlideAnim,
                child: AnimatedBuilder(
                  animation: shadowAnim,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35 * shadowAnim.value),
                            blurRadius: 20.0,
                            spreadRadius: 2.0,
                            offset: const Offset(-6, 0),
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: child,
                ),
              ),
              if (secondaryDimAnim.value > 0.0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(secondaryDimAnim.value),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

