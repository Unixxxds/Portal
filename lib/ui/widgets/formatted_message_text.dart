import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Renders message text with:
/// - Telegram-style colored Quote ("Цитата") blocks
/// - Clickable @username mentions (blue for others, white underlined for self)
/// - Clickable links / URLs (blue for others, white underlined for self)
class FormattedMessageText extends StatelessWidget {
  final String text;
  final int messageId;
  final TextStyle? style;
  final bool isMe;
  final void Function(String username)? onUsernameTap;
  final void Function(String url)? onLinkTap;
  final void Function(String command)? onCommandTap;

  const FormattedMessageText({
    super.key,
    required this.text,
    this.messageId = 0,
    this.style,
    this.isMe = false,
    this.onUsernameTap,
    this.onLinkTap,
    this.onCommandTap,
  });

  static const List<Color> _quotePalette = [
    Color(0xFF32C759), // Emerald Green
    Color(0xFF00C8FF), // Neon Cyan
    Color(0xFFA855F7), // Vivid Purple
    Color(0xFFFF9500), // Sunset Orange
    Color(0xFFFF2D55), // Bright Coral/Pink
    Color(0xFF3B82F6), // Royal Blue
    Color(0xFFFFCC00), // Sunburst Gold
    Color(0xFF10B981), // Mint
  ];

  static final RegExp _combinedRegex = RegExp(
    r'((?:https?:\/\/|www\.)[^\s]+|[a-zA-Z0-9.\-]+\.(?:com|ru|org|net|io|me|app|dev|by|kz|ua)[^\s]*)|(@[a-zA-Z0-9_]{3,32})|((?:^|(?<=[\s(]))\/[a-zA-Z0-9_]+(?:@[a-zA-Z0-9_]+)?)',
    caseSensitive: false,
  );

  Widget _buildRichText(String rawText, TextStyle defaultStyle) {
    final matches = _combinedRegex.allMatches(rawText);
    if (matches.isEmpty) {
      return Text(rawText, style: defaultStyle);
    }

    final linkStyle = isMe
        ? defaultStyle.copyWith(
            color: Colors.white,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white,
          )
        : defaultStyle.copyWith(
            color: const Color(0xFF2990FF),
            decoration: TextDecoration.none,
          );

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: rawText.substring(lastIndex, match.start),
          style: defaultStyle,
        ));
      }

      final matchedText = match.group(0)!;
      final isUsername = matchedText.startsWith('@');
      final isCommand = matchedText.startsWith('/');

      if (isCommand) {
        spans.add(TextSpan(
          text: matchedText,
          style: defaultStyle.copyWith(
            color: const Color(0xFF3B98FF),
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              onCommandTap?.call(matchedText);
            },
        ));
      } else if (isUsername) {
        final cleanUsername = matchedText.substring(1);
        spans.add(TextSpan(
          text: matchedText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              onUsernameTap?.call(cleanUsername);
            },
        ));
      } else {
        spans.add(TextSpan(
          text: matchedText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              onLinkTap?.call(matchedText);
            },
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < rawText.length) {
      spans.add(TextSpan(
        text: rawText.substring(lastIndex),
        style: defaultStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: defaultStyle,
    );
  }

  Widget _buildQuoteBlock(String quoteText, Color color) {
    const quoteTextStyle = TextStyle(
      fontFamily: AppTheme.fontText,
      color: Colors.white,
      fontSize: 14.5,
      height: 1.35,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3.5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: _buildRichText(quoteText, quoteTextStyle),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -2,
            right: 2,
            child: Text(
              '”',
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: 'serif',
                height: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ??
        const TextStyle(
          fontFamily: AppTheme.fontText,
          color: Colors.white,
          fontSize: 15,
          height: 1.35,
        );

    final sanitizedText = text.replaceAll('&gt;', '>');
    if (!sanitizedText.contains('>') && !sanitizedText.contains('[QUOTE]')) {
      return _buildRichText(text, defaultStyle);
    }

    final lines = sanitizedText.split('\n');
    final List<Widget> widgets = [];
    final List<String> currentQuoteLines = [];
    final List<String> currentNormalLines = [];
    int quoteCounter = 0;

    void flushNormal() {
      if (currentNormalLines.isNotEmpty) {
        final normalText = currentNormalLines.join('\n');
        widgets.add(_buildRichText(normalText, defaultStyle));
        currentNormalLines.clear();
      }
    }

    void flushQuote() {
      if (currentQuoteLines.isNotEmpty) {
        final quoteText = currentQuoteLines.join('\n');
        final seed = messageId.abs() != 0 ? messageId.abs() : text.hashCode.abs();
        final color = _quotePalette[(seed + quoteCounter * 3) % _quotePalette.length];
        quoteCounter++;
        widgets.add(_buildQuoteBlock(quoteText, color));
        currentQuoteLines.clear();
      }
    }

    bool insideTagQuote = false;
    for (final line in lines) {
      if (line.contains('[QUOTE]')) {
        insideTagQuote = true;
        flushNormal();
        final content = line.replaceAll('[QUOTE]', '').replaceAll('[/QUOTE]', '');
        if (content.isNotEmpty) currentQuoteLines.add(content);
        if (line.contains('[/QUOTE]')) {
          insideTagQuote = false;
          flushQuote();
        }
        continue;
      }
      if (insideTagQuote) {
        if (line.contains('[/QUOTE]')) {
          insideTagQuote = false;
          final content = line.replaceAll('[/QUOTE]', '');
          if (content.isNotEmpty) currentQuoteLines.add(content);
          flushQuote();
        } else {
          currentQuoteLines.add(line);
        }
        continue;
      }

      final trimmed = line.trimLeft();
      if (trimmed.startsWith('> ') || trimmed.startsWith('>') || trimmed.startsWith('**>')) {
        flushNormal();
        String clean = trimmed;
        if (clean.startsWith('**>')) {
          clean = clean.substring(3).trimLeft();
        } else if (clean.startsWith('> ')) {
          clean = clean.substring(2);
        } else if (clean.startsWith('>')) {
          clean = clean.substring(1).trimLeft();
        }
        currentQuoteLines.add(clean.isEmpty ? ' ' : clean);
      } else {
        flushQuote();
        currentNormalLines.add(line);
      }
    }

    flushNormal();
    flushQuote();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}
