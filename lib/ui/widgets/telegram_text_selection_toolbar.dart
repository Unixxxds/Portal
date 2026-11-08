import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Telegram-styled iOS text selection toolbar with frosted dark theme,
/// pointer beak arrow, and Russian action labels.
class TelegramTextSelectionToolbar extends StatelessWidget {
  final EditableTextState editableTextState;

  const TelegramTextSelectionToolbar({
    super.key,
    required this.editableTextState,
  });

  static Widget buildToolbar(BuildContext context, EditableTextState editableTextState) {
    return TelegramTextSelectionToolbar(editableTextState: editableTextState);
  }

  static void _applyFormatting(
    EditableTextState editableTextState,
    String prefix,
    String suffix,
  ) {
    HapticFeedback.lightImpact();
    final val = editableTextState.textEditingValue;
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

    editableTextState.userUpdateTextEditingValue(
      TextEditingValue(
        text: newText,
        selection: newSelection,
      ),
      SelectionChangedCause.toolbar,
    );
    editableTextState.hideToolbar();
  }

  @override
  Widget build(BuildContext context) {
    final value = editableTextState.textEditingValue;
    final selection = value.selection;
    final isCollapsed = selection.isCollapsed || !selection.isValid;

    final List<ContextMenuButtonItem> buttonItems = [
      if (!isCollapsed) ...[
        ContextMenuButtonItem(
          label: 'Вырезать',
          onPressed: () {
            HapticFeedback.lightImpact();
            editableTextState.cutSelection(SelectionChangedCause.toolbar);
          },
        ),
        ContextMenuButtonItem(
          label: 'Скопировать',
          onPressed: () {
            HapticFeedback.lightImpact();
            editableTextState.copySelection(SelectionChangedCause.toolbar);
          },
        ),
      ],
      ContextMenuButtonItem(
        label: 'Вставить',
        onPressed: () {
          HapticFeedback.lightImpact();
          editableTextState.pasteText(SelectionChangedCause.toolbar);
        },
      ),
      ContextMenuButtonItem(
        label: 'Выбрать всё',
        onPressed: () {
          HapticFeedback.lightImpact();
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
      ),
      if (!isCollapsed) ...[
        ContextMenuButtonItem(
          label: 'Жирный',
          onPressed: () => _applyFormatting(editableTextState, '**', '**'),
        ),
        ContextMenuButtonItem(
          label: 'Курсив',
          onPressed: () => _applyFormatting(editableTextState, '*', '*'),
        ),
        ContextMenuButtonItem(
          label: 'Моно',
          onPressed: () => _applyFormatting(editableTextState, '`', '`'),
        ),
        ContextMenuButtonItem(
          label: 'Скрытый',
          onPressed: () => _applyFormatting(editableTextState, '||', '||'),
        ),
      ],
    ];

    return CupertinoTheme(
      data: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.white,
        barBackgroundColor: Color(0xFF222224),
        scaffoldBackgroundColor: Color(0xFF191919),
      ),
      child: CupertinoAdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: buttonItems,
      ),
    );
  }
}
