import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/user_gift.dart';
import 'gift_detail_modal.dart';
import 'gift_visuals.dart';

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

/// Single bubble simulation state matching 1:1 physics from the Telegram prototype
class BubbleSimulationState {
  final int id;
  final UserGift gift;
  final double slotAngle;
  final double phase;
  final double baseR;
  final double orbitRX;
  final double orbitRY;

  double x;
  double y;
  double vx;
  double vy;
  double r;
  double vr;
  double stretchMag;
  double stretchAngle;
  double tailX;
  double tailY;
  double giftOffsetX;
  double giftOffsetY;
  double giftVelX;
  double giftVelY;
  double giftTilt;
  double giftTiltVel;
  double heroProgress;
  double animTime;
  bool isDragged;
  bool isHero;
  int zIndex;

  BubbleSimulationState({
    required this.id,
    required this.gift,
    required this.slotAngle,
    required this.phase,
    required this.baseR,
    required this.orbitRX,
    required this.orbitRY,
    required this.x,
    required this.y,
  })  : vx = 0,
        vy = 0,
        r = baseR,
        vr = 0,
        stretchMag = 0.12,
        stretchAngle = slotAngle + math.pi / 2,
        tailX = 0,
        tailY = 0,
        giftOffsetX = 0,
        giftOffsetY = 0,
        giftVelX = 0,
        giftVelY = 0,
        giftTilt = 0,
        giftTiltVel = 0,
        heroProgress = 0,
        animTime = 0,
        isDragged = false,
        isHero = false,
        zIndex = 1;
}

class DemoEvent {
  final BubbleSimulationState bubble;
  final double duration;
  final double pullX;
  final double pullY;
  final double dropX;
  final double dropY;
  final double dropAt;
  double elapsed;

  DemoEvent({
    required this.bubble,
    required this.duration,
    required this.pullX,
    required this.pullY,
    required this.dropX,
    required this.dropY,
    required this.dropAt,
  }) : elapsed = 0;
}

/// A Telegram-style 3D avatar wrapper with orbiting gift bubbles
/// featuring 1:1 spring physics, soft-body jelly deformation,
/// internal gift inertia, liquid glass reflections, and interactive dragging & flinging.
class ProfileGiftBubblesAvatar extends StatefulWidget {
  final Widget child;
  final double avatarRadius;
  final List<UserGift> gifts;
  final VoidCallback? onAvatarTap;
  final void Function(UserGift gift)? onGiftTap;
  final bool enableAutoDemo;
  final bool showBorder;

  const ProfileGiftBubblesAvatar({
    super.key,
    required this.child,
    this.avatarRadius = 46.0,
    this.gifts = const [],
    this.onAvatarTap,
    this.onGiftTap,
    this.enableAutoDemo = true,
    this.showBorder = false,
  });

  @override
  State<ProfileGiftBubblesAvatar> createState() => _ProfileGiftBubblesAvatarState();
}

class _ProfileGiftBubblesAvatarState extends State<ProfileGiftBubblesAvatar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _lastTimestamp = 0;
  double _simTime = 0;
  double _orbitAngle = 0.35;

  List<BubbleSimulationState> _bubbles = [];
  BubbleSimulationState? _draggedBubble;
  Offset _pointerPos = Offset.zero;
  Offset _dragStartPos = Offset.zero;
  bool _hasMovedFar = false;

  // Velocity tracker for flings/throws
  Offset _lastMovePos = Offset.zero;
  DateTime _lastMoveTime = DateTime.now();
  double _flingVx = 0;
  double _flingVy = 0;

  DemoEvent? _activeDemoEvent;
  double _demoTimer = 3.2;
  int _demoStepIndex = 0;

  Offset _currentCenter = Offset.zero;

  @override
  void initState() {
    super.initState();
    _rebuildBubbles();
    _ticker = createTicker(_onTick);
    // Delay ticker start until route transition completes (350 ms)
    // so weak phones don't stutter during the screen opening animation!
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && !_ticker.isActive) {
        _ticker.start();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProfileGiftBubblesAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gifts.length != widget.gifts.length ||
        oldWidget.avatarRadius != widget.avatarRadius) {
      _rebuildBubbles();
    }
  }

  @override
  void dispose() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _ticker.dispose();
    super.dispose();
  }

  void _rebuildBubbles() {
    final activeGifts = widget.gifts.take(5).toList();
    final count = activeGifts.length;
    if (count == 0) {
      _bubbles = [];
      return;
    }

    final avR = widget.avatarRadius;
    final rx = avR * 1.54;
    final ry = avR * 1.22;

    _bubbles = List.generate(count, (i) {
      final slotAngle = 0.15 + i * (2 * math.pi / count);
      final phase = i * 1.15;
      final baseR = avR * (0.33 + (i % 3) * 0.035);
      final x = math.cos(slotAngle) * rx;
      final y = math.sin(slotAngle) * ry;

      return BubbleSimulationState(
        id: i,
        gift: activeGifts[i],
        slotAngle: slotAngle,
        phase: phase,
        baseR: baseR,
        orbitRX: rx,
        orbitRY: ry,
        x: x,
        y: y,
      );
    });
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / 1000000.0;
    if (_lastTimestamp == 0) {
      _lastTimestamp = seconds;
      return;
    }
    double dt = seconds - _lastTimestamp;
    _lastTimestamp = seconds;
    if (dt > 0.05) dt = 0.05; // clamp spikes
    if (dt <= 0) return;

    _stepPhysics(dt);
    if (mounted) {
      setState(() {});
    }
  }

  void _stepPhysics(double dt) {
    _simTime += dt;
    _orbitAngle += 0.52 * dt;

    // Auto-demo choreographer from HTML prototype
    if (widget.enableAutoDemo && _draggedBubble == null && _bubbles.isNotEmpty) {
      if (_activeDemoEvent == null) {
        _demoTimer -= dt;
        if (_demoTimer <= 0) {
          _demoStepIndex++;
          final targetIdx = _demoStepIndex % _bubbles.length;
          final targetBubble = _bubbles[targetIdx];
          final pullX = (targetIdx % 2 == 0 ? 1.0 : -1.0) * (widget.avatarRadius * 0.35);
          final pullY = widget.avatarRadius * 0.25;
          final dropX = (targetIdx % 2 == 0 ? 0.8 : -0.8) * (widget.avatarRadius * 0.5);
          final dropY = widget.avatarRadius * 0.65;

          _activeDemoEvent = DemoEvent(
            bubble: targetBubble,
            duration: 1.35,
            pullX: pullX,
            pullY: pullY,
            dropX: dropX,
            dropY: dropY,
            dropAt: 0.52,
          );
        }
      } else {
        _activeDemoEvent!.elapsed += dt;
        if (_activeDemoEvent!.elapsed >= _activeDemoEvent!.duration) {
          _activeDemoEvent = null;
          _demoTimer = 3.6; // cooldown between pulses
        }
      }
    }

    // Solve 1:1 springs for each bubble
    for (final b in _bubbles) {
      b.animTime += dt;

      final currentSlotAngle = b.slotAngle + _orbitAngle;
      final sinA = math.sin(currentSlotAngle);
      final cosA = math.cos(currentSlotAngle);

      // 3D depth coordinate: negative = behind avatar, positive = in front
      final depthZ = sinA + 0.22 * math.sin(_simTime * 1.5 + b.phase);
      final isBehindAvatar = depthZ < -0.08;

      // When passing behind the avatar, tuck radial distance inward
      final backTuck = isBehindAvatar
          ? (0.72 + 0.12 * cosA.abs())
          : (1.0 + 0.12 * math.sin(_simTime * 1.7 + b.phase));

      final orbitX = cosA * b.orbitRX * backTuck;
      final orbitY = sinA * b.orbitRY * (isBehindAvatar ? 0.84 : 1.04);
      final perspectiveScale = isBehindAvatar
          ? (0.84 + 0.08 * (1.0 + depthZ))
          : (1.0 + 0.08 * depthZ);

      double desiredX = orbitX;
      double desiredY = orbitY;
      double desiredR = b.baseR * perspectiveScale;
      double targetTailX = 0;
      double targetTailY = 0;
      b.isHero = false;
      b.zIndex = isBehindAvatar ? -5 : 5;

      final currentSpeed = _hypot(b.vx, b.vy);

      if (b.isDragged) {
        desiredX = _pointerPos.dx;
        desiredY = _pointerPos.dy;
        desiredR = b.baseR * 3.05;
        b.isHero = true;
        b.zIndex = 20;

        // Elastic tether tail toward orbit anchor while dragging
        targetTailX = (orbitX - b.x) * 0.26;
        targetTailY = (orbitY - b.y) * 0.26;
      } else if (currentSpeed > 75.0) {
        // In free flight after fling/throw:
        // Bubble flies with momentum and stretches teardrop tail backward opposite to velocity
        b.isHero = true;
        b.zIndex = 20;
        desiredR = b.baseR * math.min(2.8, 1.0 + currentSpeed * 0.0016);
        targetTailX = (-b.vx * 0.065).clamp(-b.r * 0.65, b.r * 0.65);
        targetTailY = (-b.vy * 0.065).clamp(-b.r * 0.65, b.r * 0.65);
      } else if (_activeDemoEvent != null && _activeDemoEvent!.bubble == b) {
        final ev = _activeDemoEvent!;
        final u = ev.elapsed / ev.duration;
        b.isHero = true;
        b.zIndex = 15;

        if (u < ev.dropAt) {
          // Phase A: Hero zoom
          final easeIn = 1.0 - math.pow(1.0 - u / ev.dropAt, 3);
          desiredR = b.baseR * (1.0 + 1.85 * easeIn);
          desiredX = ev.pullX * easeIn + orbitX * 0.35;
          desiredY = ev.pullY * easeIn + orbitY * 0.35;
        } else {
          // Phase B: Teardrop stretch sweep across avatar then snap back
          final v = (u - ev.dropAt) / (1.0 - ev.dropAt);
          final sweepBell = math.sin(v * math.pi);
          desiredR = b.baseR * (2.85 - 1.85 * math.pow(v, 1.4));
          desiredX = orbitX * v + (ev.pullX + ev.dropX * sweepBell) * (1.0 - v);
          desiredY = orbitY * v + (ev.pullY + ev.dropY * sweepBell) * (1.0 - v);

          targetTailX = -ev.dropX * 0.45 * sweepBell;
          targetTailY = -ev.dropY * 0.52 * sweepBell;
        }
      }

      // Smooth heroProgress
      final targetHero = b.isHero ? 1.0 : 0.0;
      b.heroProgress += (targetHero - b.heroProgress) * math.min(1.0, dt * 12.0);

      // Spring physics for (x, y) matching 1:1 HTML constants
      final kPos = b.isDragged ? 240.0 : (b.isHero ? 80.0 : 70.0);
      final dPos = b.isDragged ? 20.0 : (b.isHero ? 10.5 : 12.5);
      final ax = (desiredX - b.x) * kPos - b.vx * dPos;
      final ay = (desiredY - b.y) * kPos - b.vy * dPos;
      b.vx += ax * dt;
      b.vy += ay * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;

      // Spring physics for radius r
      const kRad = 140.0;
      const dRad = 13.0;
      final ar = (desiredR - b.r) * kRad - b.vr * dRad;
      b.vr += ar * dt;
      b.r = math.max(12.0, b.r + b.vr * dt);

      // Velocity-based squash & stretch + tangent alignment
      final speed = _hypot(b.vx, b.vy);
      final tangentAngle = currentSlotAngle + math.pi / 2;
      final velAngle = speed > 18.0 ? math.atan2(b.vy, b.vx) : tangentAngle;

      final angleDiff = math.atan2(
        math.sin(velAngle - b.stretchAngle),
        math.cos(velAngle - b.stretchAngle),
      );
      b.stretchAngle += angleDiff * math.min(1.0, dt * 10.0);

      final targetStretch = math.min(0.48, 0.11 + speed * 0.0011);
      b.stretchMag += (targetStretch - b.stretchMag) * math.min(1.0, dt * 12.0);

      b.tailX += (targetTailX - b.tailX) * math.min(1.0, dt * 14.0);
      b.tailY += (targetTailY - b.tailY) * math.min(1.0, dt * 14.0);

      // Internal gift lag & tilt
      final maxShift = b.r * 0.36;
      final leadOffsetX = (b.vx * 0.045 - b.tailX * 0.32).clamp(-maxShift, maxShift);
      final leadOffsetY = (b.vy * 0.045 - b.tailY * 0.32).clamp(-maxShift, maxShift);

      const kGift = 90.0;
      const dGift = 10.0;
      b.giftVelX += ((leadOffsetX - b.giftOffsetX) * kGift - b.giftVelX * dGift) * dt;
      b.giftVelY += ((leadOffsetY - b.giftOffsetY) * kGift - b.giftVelY * dGift) * dt;
      b.giftOffsetX += b.giftVelX * dt;
      b.giftOffsetY += b.giftVelY * dt;

      final targetTilt = ((b.vx * 0.0015) + math.sin(_simTime * 3.0 + b.phase) * 0.06)
          .clamp(-0.45, 0.45);
      b.giftTiltVel += ((targetTilt - b.giftTilt) * 80.0 - b.giftTiltVel * 9.0) * dt;
      b.giftTilt += b.giftTiltVel * dt;
    }
  }

  Offset toLocalCenter(Offset globalPos) => globalPos - _currentCenter;

  BubbleSimulationState? findHitBubble(Offset local) {
    final sorted = [..._bubbles]..sort((a, b) {
        if (b.zIndex != a.zIndex) return b.zIndex.compareTo(a.zIndex);
        return b.r.compareTo(a.r);
      });

    for (final b in sorted) {
      if (_hypot(local.dx - b.x, local.dy - b.y) <= b.r * 1.35) {
        return b;
      }
    }
    return null;
  }

  void handlePointerDown(BubbleSimulationState b, Offset local) {
    _draggedBubble = b;
    b.isDragged = true;
    b.animTime = 0;
    _activeDemoEvent = null;
    _pointerPos = local;
    _dragStartPos = local;
    _lastMovePos = local;
    _lastMoveTime = DateTime.now();
    _flingVx = 0;
    _flingVy = 0;
    _hasMovedFar = false;
    HapticFeedback.lightImpact();
  }

  void handlePointerMove(Offset local) {
    if (_draggedBubble == null) return;
    _pointerPos = local;
    if (_hypot(local.dx - _dragStartPos.dx, local.dy - _dragStartPos.dy) > 7.0) {
      _hasMovedFar = true;
    }

    final now = DateTime.now();
    final dtSec = now.difference(_lastMoveTime).inMicroseconds / 1000000.0;
    if (dtSec > 0.002) {
      // Calculate instantaneous finger speed
      final instVx = (local.dx - _lastMovePos.dx) / dtSec;
      final instVy = (local.dy - _lastMovePos.dy) / dtSec;
      // Exponential smoothing for flick velocity
      _flingVx = _flingVx * 0.35 + instVx * 0.65;
      _flingVy = _flingVy * 0.35 + instVy * 0.65;
      _lastMovePos = local;
      _lastMoveTime = now;
    }
  }

  void handlePointerUp() {
    if (_draggedBubble == null) return;
    final b = _draggedBubble!;
    b.isDragged = false;

    final flingSpeed = _hypot(_flingVx, _flingVy);
    if (flingSpeed > 100.0) {
      // Transfer fling momentum so the bubble shoots across screen and bounces back
      b.vx = _flingVx.clamp(-2600.0, 2600.0);
      b.vy = _flingVy.clamp(-2600.0, 2600.0);
      HapticFeedback.mediumImpact();
    } else if (!_hasMovedFar) {
      // Tap without drag
      HapticFeedback.selectionClick();
      if (widget.onGiftTap != null) {
        widget.onGiftTap!(b.gift);
      } else {
        GiftDetailModal.show(context, gift: b.gift);
      }
    } else {
      HapticFeedback.selectionClick();
    }

    _draggedBubble = null;
    _activeDemoEvent = null;
    _demoTimer = 3.5;
  }

  void handleAvatarTap() {
    if (widget.onAvatarTap != null) {
      widget.onAvatarTap!();
    } else if (_bubbles.isNotEmpty) {
      final randomIdx = math.Random().nextInt(_bubbles.length);
      final b = _bubbles[randomIdx];
      _activeDemoEvent = DemoEvent(
        bubble: b,
        duration: 1.3,
        pullX: widget.avatarRadius * 0.4,
        pullY: widget.avatarRadius * 0.25,
        dropX: widget.avatarRadius * 0.6,
        dropY: widget.avatarRadius * 0.7,
        dropAt: 0.5,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avR = widget.avatarRadius;
    final containerHeight = avR * 3.5;

    if (_bubbles.isEmpty) {
      return SizedBox(
        height: containerHeight,
        child: Center(
          child: GestureDetector(
            onTap: handleAvatarTap,
            child: widget.child,
          ),
        ),
      );
    }

    // Split into Back Layer (zIndex < 0 and not hero/dragged) and Front Layer
    final backBubbles = _bubbles
        .where((b) => b.zIndex < 0 && !b.isHero && !b.isDragged)
        .toList()
      ..sort((a, b) => a.r.compareTo(b.r));

    final frontBubbles = _bubbles
        .where((b) => !(b.zIndex < 0 && !b.isHero && !b.isDragged))
        .toList()
      ..sort((a, b) => a.zIndex != b.zIndex
          ? a.zIndex.compareTo(b.zIndex)
          : a.r.compareTo(b.r));

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        _currentCenter = Offset(totalWidth / 2, containerHeight / 2);

        return RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            _BubbleDragRecognizer: GestureRecognizerFactoryWithHandlers<_BubbleDragRecognizer>(
              () => _BubbleDragRecognizer(state: this),
              (instance) {},
            ),
          },
          child: SizedBox(
            width: totalWidth,
            height: containerHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 1. Back-layer Bubbles (behind the avatar)
                for (final b in backBubbles)
                  _buildBubbleWidget(b, _currentCenter),

                // 2. Avatar with Dark-Glass Halo Ring & Drop-Shadow (occludes back bubbles)
                Center(
                  child: IgnorePointer(
                    child: _buildAvatarWithHalo(widget.child, avR),
                  ),
                ),

                // 3. Front-layer Bubbles (in front of the avatar & user UI)
                for (final b in frontBubbles)
                  _buildBubbleWidget(b, _currentCenter),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dark-Glass Halo Ring sampled 1:1 from the original video prototype
  Widget _buildAvatarWithHalo(Widget child, double avR) {
    if (!widget.showBorder) {
      return Container(
        width: avR * 2,
        height: avR * 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    const haloPadding = 5.0; // 5-7px dark glass halo rim
    final outerD = (avR + haloPadding) * 2;

    return Container(
      width: outerD,
      height: outerD,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 18,
            spreadRadius: 2,
            offset: Offset(0, 4),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x33FFFFFF),
            Color(0xEE16151A),
            Color(0xFF0C0B0F),
          ],
          stops: [0.0, 0.40, 1.0],
        ),
        border: Border.all(
          color: const Color(0x38FFFFFF),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(haloPadding),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0x28FFFFFF),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _buildBubbleWidget(BubbleSimulationState b, Offset center) {
    final pts = getBubbleContourPoints(b, _simTime, 28);
    final boxW = b.r * 3.2;
    final boxH = b.r * 3.2;

    // All individual bubble widgets are IgnorePointer,
    // so touches are managed exclusively by the parent coordinator without conflicts!
    return Positioned(
      left: center.dx + b.x - boxW / 2,
      top: center.dy + b.y - boxH / 2,
      width: boxW,
      height: boxH,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            size: Size(boxW, boxH),
            painter: BubbleBackgroundPainter(
              bubble: b,
              contourPoints: pts,
              simTime: _simTime,
            ),
            foregroundPainter: BubbleForegroundPainter(
              bubble: b,
              contourPoints: pts,
              simTime: _simTime,
            ),
            child: Center(
              child: Transform.translate(
                offset: Offset(b.giftOffsetX, b.giftOffsetY),
                child: Transform.rotate(
                  angle: b.giftTilt,
                  child: SizedBox(
                    width: b.r * 1.48,
                    height: b.r * 1.48,
                    child: GiftModelWidget(
                      gift: b.gift,
                      size: b.r * 1.48,
                      animate: b.isHero,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom Gesture Recognizer that claims the gesture arena ONLY when a bubble or avatar is touched,
/// allowing the parent ListView to scroll smoothly when touching empty space,
/// and giving exclusive, stutter-free drag & fling control when touching a bubble!
class _BubbleDragRecognizer extends OneSequenceGestureRecognizer {
  final _ProfileGiftBubblesAvatarState state;

  _BubbleDragRecognizer({required this.state});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final local = state.toLocalCenter(event.localPosition);
    final hit = state.findHitBubble(local);
    if (hit != null) {
      state.handlePointerDown(hit, local);
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
    } else if (local.distance <= state.widget.avatarRadius) {
      state.handleAvatarTap();
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final local = state.toLocalCenter(event.localPosition);
      state.handlePointerMove(local);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      state.handlePointerUp();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'bubble_drag_recognizer';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

/// 28-point soft-body membrane calculation with velocity stretch,
/// harmonic surface-tension wobble, and asymmetric teardrop tail pull
List<Offset> getBubbleContourPoints(
  BubbleSimulationState b,
  double simTime,
  int numPts,
) {
  final pts = <Offset>[];
  final cosA = math.cos(b.stretchAngle);
  final sinA = math.sin(b.stretchAngle);
  final sx = 1.0 + b.stretchMag;
  final sy = 1.0 / math.sqrt(sx);

  // Local tail vector
  final localTailX = b.tailX * cosA + b.tailY * sinA;
  final localTailY = -b.tailX * sinA + b.tailY * cosA;
  final tailLen = _hypot(localTailX, localTailY) + 0.001;

  for (int i = 0; i < numPts; i++) {
    final theta = (i / numPts) * math.pi * 2;
    final c = math.cos(theta);
    final s = math.sin(theta);

    // Harmonic surface-tension jelly wobble
    final wobble = math.sin(theta * 3.0 + simTime * 5.2 + b.phase) * 0.024 +
        math.cos(theta * 2.0 - simTime * 3.8 + b.phase) * 0.018;

    double rx = c * b.r * sx * (1.0 + wobble);
    double ry = s * b.r * sy * (1.0 - wobble);

    // Asymmetric teardrop membrane pull
    final tailDot = (rx * localTailX + ry * localTailY) / (b.r * tailLen);
    final tailInfluence = math.max(0.0, tailDot);
    rx += localTailX * (0.35 + 0.65 * tailInfluence * tailInfluence);
    ry += localTailY * (0.35 + 0.65 * tailInfluence * tailInfluence);

    // Rotate back to bubble-local coordinates (center is box center)
    final bx = rx * cosA - ry * sinA;
    final by = rx * sinA + ry * cosA;
    pts.add(Offset(bx, by));
  }
  return pts;
}

/// Smooth quadratic curve path builder from contour vertices
Path traceSmoothContour(List<Offset> pts, Offset center) {
  final path = Path();
  if (pts.isEmpty) return path;
  final n = pts.length;
  final firstMid = Offset(
    center.dx + (pts[n - 1].dx + pts[0].dx) / 2,
    center.dy + (pts[n - 1].dy + pts[0].dy) / 2,
  );
  path.moveTo(firstMid.dx, firstMid.dy);
  for (int i = 0; i < n; i++) {
    final p0 = Offset(center.dx + pts[i].dx, center.dy + pts[i].dy);
    final p1 = Offset(center.dx + pts[(i + 1) % n].dx, center.dy + pts[(i + 1) % n].dy);
    final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
  }
  path.close();
  return path;
}

/// Background painter: paints ambient glow & translucent glass body inside clipped contour
class BubbleBackgroundPainter extends CustomPainter {
  final BubbleSimulationState bubble;
  final List<Offset> contourPoints;
  final double simTime;

  BubbleBackgroundPainter({
    required this.bubble,
    required this.contourPoints,
    required this.simTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final contourPath = traceSmoothContour(contourPoints, center);

    canvas.save();
    canvas.clipPath(contourPath);

    // 1. Soft ambient glow matching gift backdrop theme
    final glowColor = GiftVisuals.getAmbientGlowColor(
      bubble.gift.backdropName,
      bubble.gift.giftName,
      bubble.gift.backdropGradient,
    );

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withOpacity(0.35 + bubble.heroProgress * 0.15),
          glowColor.withOpacity(0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bubble.r * 1.15));
    canvas.drawCircle(center, bubble.r * 1.15, glowPaint);

    // 2. Translucent glass body gradient
    final glassShader = RadialGradient(
      center: Alignment(
        -bubble.r * 0.28 / (bubble.r * 1.35),
        -bubble.r * 0.28 / (bubble.r * 1.35),
      ),
      radius: 1.35,
      colors: const [
        Color(0x18FFFFFF),
        Color(0x28D2D7E4),
        Color(0x55FFFFFF),
      ],
      stops: const [0.0, 0.65, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: bubble.r));

    final glassPaint = Paint()..shader = glassShader;
    canvas.drawPaint(glassPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BubbleBackgroundPainter oldDelegate) => true;
}

/// Foreground painter: paints top-left crescent glare, dual bottom-right droplets, and 1.2px rim stroke
class BubbleForegroundPainter extends CustomPainter {
  final BubbleSimulationState bubble;
  final List<Offset> contourPoints;
  final double simTime;

  BubbleForegroundPainter({
    required this.bubble,
    required this.contourPoints,
    required this.simTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final contourPath = traceSmoothContour(contourPoints, center);

    canvas.save();
    canvas.clipPath(contourPath);

    // 1. Top-left curved crescent glare
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bubble.stretchAngle * 0.25);

    final glareRect = Rect.fromCenter(
      center: Offset(-bubble.r * 0.34, -bubble.r * 0.38),
      width: bubble.r * 0.72,
      height: bubble.r * 0.30,
    );
    final glarePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0x9EFFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(glareRect);

    canvas.save();
    canvas.rotate(-0.62);
    canvas.drawOval(glareRect, glarePaint);
    canvas.restore();

    // 2. Dual bottom-right droplet reflections
    final dropletPaint = Paint()..color = const Color(0x38FFFFFF);
    final droplet1Rect = Rect.fromCenter(
      center: Offset(bubble.r * 0.48, bubble.r * 0.34),
      width: bubble.r * 0.28,
      height: bubble.r * 0.16,
    );
    canvas.save();
    canvas.rotate(-0.70);
    canvas.drawOval(droplet1Rect, dropletPaint);
    canvas.restore();

    canvas.drawCircle(
      Offset(bubble.r * 0.58, bubble.r * 0.16),
      bubble.r * 0.06,
      dropletPaint,
    );

    canvas.restore(); // Restore translation/rotation

    canvas.restore(); // Restore clip

    // 3. Outer rim stroke (1.2px)
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + bubble.heroProgress * 0.6
      ..color = const Color(0x44FFFFFF);
    canvas.drawPath(contourPath, rimPaint);
  }

  @override
  bool shouldRepaint(covariant BubbleForegroundPainter oldDelegate) => true;
}
