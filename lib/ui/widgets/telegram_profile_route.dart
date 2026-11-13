import 'package:flutter/cupertino.dart';

/// Smooth Telegram-style page route for opening user profiles.
/// Includes subtle scale, slide, and fade with full iOS edge swipe-to-back support.
class TelegramProfileRoute<T> extends CupertinoPageRoute<T> {
  TelegramProfileRoute({
    required super.builder,
    super.settings,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 270);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.status == AnimationStatus.reverse) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeInCubic,
        )),
        child: child,
      );
    }

    final curvedForward = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    final slideAnim = Tween<Offset>(
      begin: const Offset(0.18, 0.0),
      end: Offset.zero,
    ).animate(curvedForward);

    final scaleAnim = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(curvedForward);

    final fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    ));

    return SlideTransition(
      position: slideAnim,
      child: ScaleTransition(
        scale: scaleAnim,
        child: FadeTransition(
          opacity: fadeAnim,
          child: child,
        ),
      ),
    );
  }
}

