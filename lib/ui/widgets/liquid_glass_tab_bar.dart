import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class LiquidGlassTabBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final int totalUnreadCount;

  const LiquidGlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.totalUnreadCount = 0,
  });

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar>
    with SingleTickerProviderStateMixin {
  static const double barHeight = 74.0;
  static const double pillHeight = 60.0;
  static const double barPadding = 7.0;
  static const int tabCount = 5;

  late AnimationController _animController;
  late Animation<double> _animX;
  late Animation<double> _stretchAnim;

  double _currentPillCenter = -1; // Center X of the pill
  bool _isDragging = false;
  double _pressScale = 1.0;
  double _velocityStretch = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _animController.addListener(() {
      setState(() {
        _currentPillCenter = _animX.value;
        _velocityStretch = _stretchAnim.value;
      });
    });
  }

  @override
  void didUpdateWidget(covariant LiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isDragging) {
      _animateToTab(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateToTab(int targetIndex, {bool withSpringOvershoot = true}) {
    if (!mounted) return;
    // Calculate centers
    final barWidth = _getBarWidth(context);
    final innerWidth = barWidth - (barPadding * 2);
    final slotWidth = innerWidth / tabCount;
    final targetX = barPadding + (targetIndex * slotWidth) + (slotWidth / 2);

    final startX = _currentPillCenter < 0 ? targetX : _currentPillCenter;
    final distance = (targetX - startX).abs();
    final stretchIntensity = math.min(distance / slotWidth * 0.22, 0.35);

    _animX = Tween<double>(begin: startX, end: targetX).animate(
      CurvedAnimation(
        parent: _animController,
        curve: withSpringOvershoot ? Curves.easeOutBack : Curves.easeOutCubic,
      ),
    );

    _stretchAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: stretchIntensity)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: stretchIntensity, end: 0.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_animController);

    _animController.forward(from: 0.0);
  }

  double _getBarWidth(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    return math.min(screenW * 0.94, 416.0);
  }

  double _rubberBand(double val, double min, double max, [double resistance = 0.28]) {
    if (val < min) {
      final overscroll = min - val;
      return min - math.pow(overscroll, 0.78) * resistance * 3.5;
    }
    if (val > max) {
      final overscroll = val - max;
      return max + math.pow(overscroll, 0.78) * resistance * 3.5;
    }
    return val;
  }

  int _getClosestTabIndex(double localX, double barWidth) {
    final innerWidth = barWidth - (barPadding * 2);
    final slotWidth = innerWidth / tabCount;
    double bestDist = double.infinity;
    int bestIdx = 0;

    for (int i = 0; i < tabCount; i++) {
      final center = barPadding + (i * slotWidth) + (slotWidth / 2);
      final dist = (localX - center).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = _getBarWidth(context);
    final innerWidth = barWidth - (barPadding * 2);
    final slotWidth = innerWidth / tabCount;
    final pillWidth = slotWidth;

    if (_currentPillCenter < 0) {
      _currentPillCenter = barPadding + (widget.selectedIndex * slotWidth) + (slotWidth / 2);
    }

    final minCenter = barPadding + (slotWidth / 2);
    final maxCenter = barPadding + ((tabCount - 1) * slotWidth) + (slotWidth / 2);

    // Dynamic stretch & squash from motion & press
    final effectiveStretchX = (1.0 + _velocityStretch) * _pressScale;
    final effectiveSquashY = (1.0 - _velocityStretch * 0.3) * (1.0 + (_pressScale - 1.0) * 0.8);

    final pillLeft = _currentPillCenter - (pillWidth / 2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              _animController.stop();
              setState(() {
                _isDragging = true;
                _pressScale = 1.08;
                _currentPillCenter = _rubberBand(details.localPosition.dx, minCenter, maxCenter);
              });
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                final speed = (details.delta.dx).abs();
                _velocityStretch = math.min(speed * 0.04, 0.28);
                _currentPillCenter = _rubberBand(details.localPosition.dx, minCenter, maxCenter);
              });
            },
            onHorizontalDragEnd: (details) {
              setState(() {
                _isDragging = false;
                _pressScale = 1.0;
              });
              final targetIndex = _getClosestTabIndex(_currentPillCenter, barWidth);
              widget.onTabSelected(targetIndex);
              _animateToTab(targetIndex);
            },
            onTapDown: (details) {
              setState(() => _pressScale = 1.06);
            },
            onTapUp: (details) {
              setState(() => _pressScale = 1.0);
              final targetIndex = _getClosestTabIndex(details.localPosition.dx, barWidth);
              widget.onTabSelected(targetIndex);
              _animateToTab(targetIndex);
            },
            onTapCancel: () {
              setState(() => _pressScale = 1.0);
            },
            child: Container(
              width: barWidth,
              height: barHeight,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                // Graphite #191919 translucent shell
                color: const Color(0xF2191919),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0x1AFFFFFF),
                  width: 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 28,
                    spreadRadius: -4,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ============================================================
                  // THE FLAT LIQUID PILL (Strictly behind tab items, z: 1)
                  // ============================================================
                  Positioned(
                    left: pillLeft,
                    top: barPadding,
                    width: pillWidth,
                    height: pillHeight,
                    child: Transform.scale(
                      scaleX: effectiveStretchX,
                      scaleY: effectiveSquashY,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0x29FFFFFF),
                            width: 1.0,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x4D000000),
                              blurRadius: 10,
                              spreadRadius: -1,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ============================================================
                  // TAB ITEMS (Icons & Labels — Always crisp on top, z: 2)
                  // ============================================================
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(barPadding),
                      child: Row(
                        children: [
                          _buildTabItem(
                            index: 0,
                            label: 'Контакты',
                            outlineIcon: Icons.person_outline_rounded,
                            filledIcon: Icons.person_rounded,
                            slotWidth: slotWidth,
                            barWidth: barWidth,
                          ),
                          _buildTabItem(
                            index: 1,
                            label: 'Звонки',
                            outlineIcon: Icons.phone_outlined,
                            filledIcon: Icons.phone_rounded,
                            slotWidth: slotWidth,
                            barWidth: barWidth,
                          ),
                          _buildTabItem(
                            index: 2,
                            label: 'Чаты',
                            outlineIcon: Icons.chat_bubble_outline_rounded,
                            filledIcon: Icons.chat_bubble_rounded,
                            slotWidth: slotWidth,
                            barWidth: barWidth,
                            badgeCount: widget.totalUnreadCount,
                          ),
                          _buildTabItem(
                            index: 3,
                            label: 'Настройки',
                            outlineIcon: Icons.settings_outlined,
                            filledIcon: Icons.settings_rounded,
                            slotWidth: slotWidth,
                            barWidth: barWidth,
                          ),
                          _buildTabItem(
                            index: 4,
                            label: 'Я',
                            outlineIcon: Icons.account_circle_outlined,
                            filledIcon: Icons.account_circle_rounded,
                            slotWidth: slotWidth,
                            barWidth: barWidth,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildTabItem({
    required int index,
    required String label,
    required IconData outlineIcon,
    required IconData filledIcon,
    required double slotWidth,
    required double barWidth,
    int badgeCount = 0,
  }) {
    // Proximity to current pill position
    final center = barPadding + (index * slotWidth) + (slotWidth / 2);
    final dist = (center - _currentPillCenter).abs();
    final maxRadius = slotWidth * 0.85;
    final proximity = math.max(0.0, 1.0 - (dist / maxRadius));
    final smoothCurve = math.sin(proximity * math.pi * 0.5);

    final isActive = proximity > 0.45;
    final iconColor = isActive ? const Color(0xFFFFFFFF) : const Color(0xFF929292);
    final iconScale = 1.0 + (smoothCurve * 0.10);

    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.scale(
              scale: iconScale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isActive ? filledIcon : outlineIcon,
                    color: iconColor,
                    size: 23,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -3,
                      right: -8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30), // Apple iOS Red Badge
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF1A1D24),
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66FF3B30),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                color: iconColor,
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.15,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
