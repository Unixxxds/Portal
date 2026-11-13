import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

enum _MenuState {
  main,
  formatSelect,
  allFormats,
}

class _BeakPainter extends CustomPainter {
  final bool isAbove;
  final Color color;

  _BeakPainter({required this.isAbove, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (isAbove) {
      // Pointing down
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      // Pointing up
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width / 2, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BeakPainter oldDelegate) =>
      oldDelegate.isAbove != isAbove || oldDelegate.color != color;
}

/// Telegram-styled iOS text selection toolbar (fully rounded stadium capsule,
/// frosted dark glass, pointer beak arrow, and Russian action navigation).
class TelegramTextSelectionToolbar extends StatefulWidget {
  final EditableTextState editableTextState;

  const TelegramTextSelectionToolbar({
    super.key,
    required this.editableTextState,
  });

  static Widget buildToolbar(BuildContext context, EditableTextState editableTextState) {
    return TelegramTextSelectionToolbar(editableTextState: editableTextState);
  }

  @override
  State<TelegramTextSelectionToolbar> createState() => _TelegramTextSelectionToolbarState();
}

class _TelegramTextSelectionToolbarState extends State<TelegramTextSelectionToolbar> {
  _MenuState _state = _MenuState.main;

  void _applyQuote() {
    HapticFeedback.mediumImpact();
    final val = widget.editableTextState.textEditingValue;
    final sel = val.selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final start = math.min(sel.start, sel.end);
    final end = math.max(sel.start, sel.end);
    final text = val.text;
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);

    // Prefix each line with '> '
    final lines = selected.split('\n');
    final quoted = lines.map((l) {
      final t = l.trimLeft();
      if (t.startsWith('>')) return l;
      return '> $l';
    }).join('\n');

    final prefixNewline = (before.isNotEmpty && !before.endsWith('\n')) ? '\n' : '';
    final suffixNewline = (after.isNotEmpty && !after.startsWith('\n')) ? '\n' : '';
    final newQuoted = '$prefixNewline$quoted$suffixNewline';

    final newText = '$before$newQuoted$after';
    final newSelection = TextSelection(
      baseOffset: start + prefixNewline.length,
      extentOffset: start + prefixNewline.length + quoted.length,
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
      _state = _MenuState.main;
    });
  }

  Widget _buildButton({
    String? text,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x22FFFFFF),
        highlightColor: const Color(0x18FFFFFF),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: icon != null ? 11 : 13),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.white, size: 18)
              : Text(
                  text!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: AppTheme.fontText,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.2,
                    decoration: TextDecoration.none,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 0.6,
      height: 18,
      color: const Color(0x33FFFFFF),
    );
  }

  List<Widget> _buildButtons() {
    final value = widget.editableTextState.textEditingValue;
    final selection = value.selection;
    final isCollapsed = selection.isCollapsed || !selection.isValid;

    if (isCollapsed) {
      return [
        _buildButton(text: 'Вставить', onTap: _paste),
        _buildDivider(),
        _buildButton(text: 'Выбрать всё', onTap: _selectAll),
      ];
    }

    switch (_state) {
      case _MenuState.main:
        return [
          _buildButton(text: 'Вырезать', onTap: _cut),
          _buildDivider(),
          _buildButton(text: 'Скопировать', onTap: _copy),
          _buildDivider(),
          _buildButton(text: 'Вставить', onTap: _paste),
          _buildDivider(),
          _buildButton(
            icon: Icons.chevron_right_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _state = _MenuState.formatSelect);
            },
          ),
        ];

      case _MenuState.formatSelect:
        return [
          _buildButton(
            icon: Icons.chevron_left_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _state = _MenuState.main);
            },
          ),
          _buildDivider(),
          _buildButton(
            text: 'Форматирование',
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _state = _MenuState.allFormats);
            },
          ),
          _buildDivider(),
          _buildButton(
            text: 'Цитата',
            onTap: _applyQuote,
          ),
        ];

      case _MenuState.allFormats:
        return [
          _buildButton(
            icon: Icons.chevron_left_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _state = _MenuState.formatSelect);
            },
          ),
          _buildDivider(),
          _buildButton(
            text: 'Цитата',
            onTap: _applyQuote,
          ),
          _buildDivider(),
          _buildButton(
            text: 'Жирный',
            onTap: () => _applyFormatting('**', '**'),
          ),
          _buildDivider(),
          _buildButton(
            text: 'Курсив',
            onTap: () => _applyFormatting('*', '*'),
          ),
          _buildDivider(),
          _buildButton(
            text: 'Моно',
            onTap: () => _applyFormatting('`', '`'),
          ),
          _buildDivider(),
          _buildButton(
            text: 'Скрытый',
            onTap: () => _applyFormatting('||', '||'),
          ),
        ];
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
    const double kToolbarHeight = 44.0; // 38 body + 6 beak

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

    final double normalizedX = (anchorX / availableWidth).clamp(0.0, 1.0);
    final double alignX = (normalizedX * 2.0) - 1.0;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!fitsAbove)
              Align(
                alignment: Alignment(alignX.clamp(-0.80, 0.80), 0),
                child: CustomPaint(
                  size: const Size(13, 6),
                  painter: _BeakPainter(isAbove: false, color: const Color(0xEE1E1E22)),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999), // Максимально скруглена
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E1E22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x35FFFFFF), width: 0.6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildButtons(),
                  ),
                ),
              ),
            ),
            if (fitsAbove)
              Align(
                alignment: Alignment(alignX.clamp(-0.80, 0.80), 0),
                child: CustomPaint(
                  size: const Size(13, 6),
                  painter: _BeakPainter(isAbove: true, color: const Color(0xEE1E1E22)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
