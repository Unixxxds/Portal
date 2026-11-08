import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants.dart';
import '../theme.dart';

class AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final String title;
  final double size;
  final bool isOnline;
  final bool isSaved;
  final bool isBot;
  final bool isChannel;

  const AvatarWidget({
    super.key,
    this.avatarUrl,
    required this.title,
    this.size = 52,
    this.isOnline = false,
    this.isSaved = false,
    this.isBot = false,
    this.isChannel = false,
  });

  Color _getDeterministicColor(String text) {
    final colors = [
      const Color(0xFFE56555),
      const Color(0xFFF27438),
      const Color(0xFFE5884B),
      const Color(0xFF4FA04F),
      const Color(0xFF3399BB),
      const Color(0xFF4094EF),
      const Color(0xFF7562D8),
      const Color(0xFFC04AB4),
    ];
    if (text.isEmpty) return colors[0];
    final hash = text.codeUnits.fold(0, (acc, val) => acc + val);
    return colors[hash % colors.length];
  }

  String _getInitials(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Saved Messages special avatar (Graphite #191919 with white bookmark)
    final checkSaved = isSaved || title.toLowerCase() == 'избранное' || title.toLowerCase().contains('сохранен');
    if (checkSaved) {
      return _buildFrame(
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF191919),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.bookmark_rounded,
              color: Colors.white,
              size: size * 0.52,
            ),
          ),
        ),
      );
    }

    // 2. Portal Official channel special avatar
    final fullUrl = AppConstants.formatMediaUrl(avatarUrl);
    final hasValidUrl = fullUrl.isNotEmpty;
    if (!hasValidUrl && title.toLowerCase().contains('portal')) {
      return _buildFrame(
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF191919),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.door_sliding_outlined,
              color: Colors.white,
              size: size * 0.54,
            ),
          ),
        ),
      );
    }

    // 3. Channel avatar if no image
    final checkChannel = isChannel || title.toLowerCase().contains('канал');

    if (!hasValidUrl && checkChannel) {
      return _buildFrame(
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF191919),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.campaign_outlined,
              color: const Color(0xFFE5E7EB),
              size: size * 0.54,
            ),
          ),
        ),
      );
    }

    // 4. Bot avatar (Shield VPN, ChatGPT) if no image
    final checkBot = isBot || title.toLowerCase().contains('bot') || title.toLowerCase().contains('gpt') || title.toLowerCase().contains('vpn');

    if (!hasValidUrl && checkBot) {
      return _buildFrame(
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF191919),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              Icons.smart_toy_outlined,
              color: const Color(0xFFE5E7EB),
              size: size * 0.54,
            ),
          ),
        ),
      );
    }

    // 5. User Avatar with image or initials
    return _buildFrame(
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hasValidUrl ? const Color(0xFF191919) : _getDeterministicColor(title),
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: hasValidUrl
              ? CachedNetworkImage(
                  imageUrl: fullUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Center(
                    child: Text(
                      _getInitials(title),
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: size * 0.38,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Center(
                    child: Text(
                      _getInitials(title),
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: size * 0.38,
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    _getInitials(title),
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.38,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFrame(Widget content) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: AppTheme.statusOnline,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.appBg,
                  width: 2.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
