import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

enum _ToolbarPage {
  main,
  secondary,
  formatting,
}

Path _buildTelegramToolbarPath({
  required Size size,
  required double beakX,
  required bool isAbove,
}) {
  const double beakHeight = 6.5;
  final Rect bodyRect = Rect.fromLTWH(
    0,
    isAbove ? 0 : beakHeight,
    size.width,
    size.height - beakHeight,
  );

  final clampedBeakX = beakX.clamp(14.0, math.max(14.0, size.width - 14.0)).toDouble();
  final path = Path();
  path.addRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(13.0)));

  if (isAbove) {
    path.moveTo(clampedBeakX - 7.0, bodyRect.bottom - 0.5);
    path.lineTo(clampedBeakX, bodyRect.bottom + beakHeight);
    path.lineTo(clampedBeakX + 7.0, bodyRect.bottom - 0.5);
  } else {
    path.moveTo(clampedBeakX - 7.0, bodyRect.top + 0.5);
    path.lineTo(clampedBeakX, bodyRect.top - beakHeight);
    path.lineTo(clampedBeakX + 7.0, bodyRect.top + 0.5);
  }
  return path;
}

class _TelegramToolbarClipper extends CustomClipper<Path> {
  final double beakX;
  final bool isAbove;

  _TelegramToolbarClipper({required this.beakX, required this.isAbove});

  @override
  Path getClip(Size size) {
    return _buildTelegramToolbarPath(size: size, beakX: beakX, isAbove: isAbove);
  }

  @override
  bool shouldReclip(covariant _TelegramToolbarClipper oldClipper) {
    return oldClipper.beakX != beakX || oldClipper.isAbove != isAbove;
  }
}

class _TelegramToolbarPainter extends CustomPainter {
  final double beakX;
  final bool isAbove;
  final Color backgroundColor;
  final Color borderColor;

  _TelegramToolbarPainter({
    required this.beakX,
    required this.isAbove,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildTelegramToolbarPath(
      size: size,
      beakX: beakX,
      isAbove: isAbove,
    );

    // Subtle drop shadow
    canvas.drawShadow(path, Colors.black.withOpacity(0.4), 14.0, true);

    // Translucent dark glass fill
    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Subtle crisp border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _TelegramToolbarPainter oldDelegate) {
    return oldDelegate.beakX != beakX ||
        oldDelegate.isAbove != isAbove ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor;
  }
}

/// A Telegram-styled iOS text selection toolbar (floating frosted glass capsule with beak).
class TelegramTextSelectionToolbar extends StatefulWidget {
  final EditableTextState editableTextState;

  const TelegramTextSelectionToolbar({
    super.key,
    required this.editableTextState,
  });

  static Widget build(BuildContext context, EditableTextState editableTextState) {
    return TelegramTextSelectionToolbar(editableTextState: editableTextState);
  }

  @override
  State<TelegramTextSelectionToolbar> createState() => _TelegramTextSelectionToolbarState();
}

class _TelegramTextSelectionToolbarState extends State<TelegramTextSelectionToolbar>
    with SingleTickerProviderStateMixin {
  _ToolbarPage _page = _ToolbarPage.main;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _applyFormatting(String prefix, String suffix) {
    HapticFeedback.lightImpact();
    final val = widget.editableTextState.textEditingValue;
    final sel = val.selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final start = math.min(sel.start, sel.end);
    final end = math.max(sel.start, sel.end);
    final text = val.text;
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);

    final newText = '$before$prefix$selected$suffix$after';
    final newSelection = TextSelection(
      baseOffset: start,
      extentOffset: end + prefix.length + suffix.length,
    );

    widget.editableTextState.userUpdateTextEditingValue(
      TextEditingValue(
        text: newText,
        selection: newSelection,
      ),
      SelectionChangedCause.toolbar,
    );
    widget.editableTextState.hideToolbar();
  }

  void _cut() {
    HapticFeedback.lightImpact();
    widget.editableTextState.cutSelection(SelectionChangedCause.toolbar);
  }

  void _copy() {
    HapticFeedback.lightImpact();
    widget.editableTextState.copySelection(SelectionChangedCause.toolbar);
  }

  void _paste() {
    HapticFeedback.lightImpact();
    widget.editableTextState.pasteText(SelectionChangedCause.toolbar);
  }

  void _selectAll() {
    HapticFeedback.lightImpact();
    widget.editableTextState.selectAll(SelectionChangedCause.toolbar);
    setState(() {
      _page = _ToolbarPage.main;
    });
  }

  Widget _buildDivider() {
    return Container(
      width: 0.6,
      height: 20,
      color: const Color(0x38FFFFFF),
    );
  }

  Widget _buildPageContent() {
    final isCollapsed = widget.editableTextState.textEditingValue.selection.isCollapsed;

    if (isCollapsed) {
      // Nothing selected: show Paste | Select All
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarButton(
            text: 'Вставить',
            onTap: _paste,
          ),
          _buildDivider(),
          _ToolbarButton(
            text: 'Выбрать всё',
            onTap: _selectAll,
          ),
        ],
      );
    }

    switch (_page) {
      case _ToolbarPage.main:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              text: 'Вырезать',
              onTap: _cut,
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Скопировать',
              onTap: _copy,
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Вставить',
              onTap: _paste,
            ),
            _buildDivider(),
            _ToolbarButton(
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _page = _ToolbarPage.secondary);
              },
            ),
          ],
        );

      case _ToolbarPage.secondary:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 20,
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _page = _ToolbarPage.main);
              },
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Выбрать всё',
              onTap: _selectAll,
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Форматировать',
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _page = _ToolbarPage.formatting);
              },
            ),
          ],
        );

      case _ToolbarPage.formatting:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 20,
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _page = _ToolbarPage.secondary);
              },
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Жирный',
              onTap: () => _applyFormatting('**', '**'),
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Курсив',
              onTap: () => _applyFormatting('*', '*'),
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Моно',
              onTap: () => _applyFormatting('`', '`'),
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Зачёркнутый',
              onTap: () => _applyFormatting('~~', '~~'),
            ),
            _buildDivider(),
            _ToolbarButton(
              text: 'Скрытый',
              onTap: () => _applyFormatting('||', '||'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchors = widget.editableTextState.contextMenuAnchors;
    final anchorAbove = anchors.primaryAnchor;
    final anchorBelow = anchors.secondaryAnchor ?? anchorAbove;

    if (!anchorAbove.dx.isFinite || !anchorAbove.dy.isFinite) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    const double screenPadding = 8.0;
    const double kToolbarContentDistance = 8.0;
    const double kToolbarHeight = 46.5; // 40 body + 6.5 beak

    final Offset anchorAbovePadded = anchorAbove - const Offset(0.0, kToolbarContentDistance);
    final Offset anchorBelowPadded = anchorBelow + const Offset(0.0, kToolbarContentDistance);

    final double paddingAbove = mediaQuery.padding.top + screenPadding;
    final double availableHeight = anchorAbovePadded.dy - kToolbarContentDistance - paddingAbove;
    final bool fitsAbove = kToolbarHeight <= availableHeight;
    final Offset localAdjustment = Offset(screenPadding, paddingAbove);

    final Offset localAnchorAbove = anchorAbovePadded - localAdjustment;
    final Offset localAnchorBelow = anchorBelowPadded - localAdjustment;

    final double anchorX = localAnchorAbove.dx;
    final double availableWidth = mediaQuery.size.width - (screenPadding * 2);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenPadding,
        paddingAbove,
        screenPadding,
        screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: localAnchorAbove,
          anchorBelow: localAnchorBelow,
          fitsAbove: fitsAbove,
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: _ToolbarContainer(
              anchorX: anchorX,
              availableWidth: availableWidth,
              fitsAbove: fitsAbove,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: KeyedSubtree(
                  key: ValueKey<int>(_page.index * 10 + (widget.editableTextState.textEditingValue.selection.isCollapsed ? 1 : 0)),
                  child: _buildPageContent(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarContainer extends StatelessWidget {
  final double anchorX;
  final double availableWidth;
  final bool fitsAbove;
  final Widget child;

  const _ToolbarContainer({
    required this.anchorX,
    required this.availableWidth,
    required this.fitsAbove,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: LayoutBuilder(
        builder: (context, boxConstraints) {
          final width = boxConstraints.maxWidth;
          final childLeft = TextSelectionToolbarLayoutDelegate.centerOn(
            anchorX,
            width,
            availableWidth,
          );
          final beakX = (anchorX - childLeft).clamp(16.0, math.max(16.0, width - 16.0)).toDouble();

          return ClipPath(
            clipper: _TelegramToolbarClipper(beakX: beakX, isAbove: fitsAbove),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: CustomPaint(
                painter: _TelegramToolbarPainter(
                  beakX: beakX,
                  isAbove: fitsAbove,
                  backgroundColor: const Color(0xDC232326),
                  borderColor: const Color(0x35FFFFFF),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: fitsAbove ? 0 : 6.5,
                    bottom: fitsAbove ? 6.5 : 0,
                  ),
                  child: SizedBox(
                    height: 39,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String? text;
  final Widget? icon;
  final VoidCallback? onTap;

  const _ToolbarButton({
    this.text,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x22FFFFFF),
        highlightColor: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 39,
          padding: EdgeInsets.symmetric(horizontal: icon != null ? 12 : 14),
          alignment: Alignment.center,
          child: icon ??
              Text(
                text!,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: AppTheme.fontText,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2,
                  decoration: TextDecoration.none,
                ),
              ),
        ),
      ),
    );
  }
}
