import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../../core/user_activity_helper.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../screens/chat_screen.dart';
import 'avatar_widget.dart';
import 'telegram_chat_route.dart';

class GroupJoinDialog extends StatefulWidget {
  final Map<String, dynamic> groupData;
  final String inviteCode;

  const GroupJoinDialog({
    super.key,
    required this.groupData,
    required this.inviteCode,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> groupData,
    required String inviteCode,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => GroupJoinDialog(
        groupData: groupData,
        inviteCode: inviteCode,
      ),
    );
  }

  @override
  State<GroupJoinDialog> createState() => _GroupJoinDialogState();
}

class _GroupJoinDialogState extends State<GroupJoinDialog> {
  bool _isJoining = false;

  Future<void> _handleJoin() async {
    if (_isJoining) return;
    HapticFeedback.mediumImpact();
    setState(() => _isJoining = true);

    final chatProvider = context.read<ChatProvider>();

    try {
      final res = await ApiService.instance.joinGroup(widget.inviteCode);
      final rawChatId = res['chatId'] ??
          (res['group'] is Map ? (res['group']['chat_id'] ?? res['group']['id']) : null) ??
          widget.groupData['chat_id'] ??
          widget.groupData['id'];

      final chatId = rawChatId is int ? rawChatId : int.tryParse(rawChatId?.toString() ?? '') ?? 0;

      await chatProvider.syncBootstrap();

      if (!mounted) return;
      Navigator.of(context).pop(); // Close dialog

      if (chatId > 0) {
        var targetChat = chatProvider.chats.where((c) => c.isGroup && c.id == chatId).firstOrNull;
        targetChat ??= Chat(
          id: chatId,
          title: widget.groupData['title']?.toString() ?? 'Группа',
          type: 'group',
          avatar: widget.groupData['avatar']?.toString() ?? '',
          ownerId: widget.groupData['owner_id'] as int?,
          username: widget.groupData['username']?.toString() ?? widget.inviteCode,
          inviteCode: widget.groupData['invite_code']?.toString() ?? widget.inviteCode,
          membersCount: (widget.groupData['members_count'] as int? ?? 1) + 1,
          subscribersCount: (widget.groupData['members_count'] as int? ?? 1) + 1,
          isGroupChat: true,
          isSubscribed: true,
        );

        Navigator.of(context).push(
          TelegramChatRoute(
            builder: (_) => ChatScreen(chat: targetChat!),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isJoining = false);
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'Не удалось присоединиться к группе'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.groupData['title']?.toString() ?? 'Группа';
    final avatar = widget.groupData['avatar']?.toString() ?? '';
    final description = widget.groupData['description']?.toString() ?? '';
    final membersCount = widget.groupData['members_count'] is int
        ? widget.groupData['members_count'] as int
        : (int.tryParse(widget.groupData['members_count']?.toString() ?? '') ?? 1);
    final isMember = widget.groupData['is_member'] == 1 || widget.groupData['is_member'] == true;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.84,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0x1AFFFFFF),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Group Avatar in center
              AvatarWidget(
                avatarUrl: avatar,
                title: title,
                size: 80,
                isChannel: false,
                isGroup: true,
              ),
              const SizedBox(height: 16),

              // 2. Group Title
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),

              // 3. Members count
              Text(
                UserActivityHelper.formatMembers(membersCount),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF8E8E93),
                ),
              ),

              // 4. Description (if any)
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 13,
                    color: Color(0xFFB0B0B0),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // 5. White Rounded Pill Button "Присоединиться"
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isJoining ? null : _handleJoin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white.withOpacity(0.7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: _isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Text(
                          isMember ? 'Перейти в группу' : 'Присоединиться',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 10),

              // Cancel button
              SizedBox(
                width: double.infinity,
                height: 38,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8E8E93),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    'Отмена',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
