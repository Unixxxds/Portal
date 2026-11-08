import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

class CreateChannelScreen extends StatefulWidget {
  final int ownedCount;
  final int maxChannels;

  const CreateChannelScreen({
    super.key,
    required this.ownedCount,
    required this.maxChannels,
  });

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _localAvatarPath;
  String _uploadedAvatarUrl = '';
  bool _isUploadingAvatar = false;
  bool _isSubmitting = false;

  Timer? _debounceTimer;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameStatusMessage;

  @override
  void initState() {
    super.initState();
    _usernameStatusMessage = 'От 5 до 12 символов (латиница, цифры, _)';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _titleController.dispose();
    _usernameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    _debounceTimer?.cancel();
    final clean = value.trim().replaceFirst(RegExp(r'^@+'), '');

    if (clean.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
        _usernameStatusMessage = 'От 5 до 12 символов (латиница, цифры, _)';
      });
      return;
    }

    if (clean.length < 5) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Минимум 5 символов';
      });
      return;
    }

    if (clean.length > 12) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Максимум 12 символов';
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(clean)) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Разрешены только латинские буквы, цифры и _';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
      _usernameStatusMessage = 'Проверка доступности...';
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      final available = await ApiService.instance.checkChannelUsername(clean);
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = available;
        if (available) {
          _usernameStatusMessage = 'Имя пользователя @$clean свободно';
        } else {
          _usernameStatusMessage = 'Это имя пользователя уже занято';
        }
      });
    });
  }

  Future<void> _pickAvatar() async {
    String? pickedPath;
    if (Platform.isWindows) {
      try {
        final script = r"""
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Выберите аватарку канала'
$dialog.Filter = 'Изображения (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp|Все файлы (*.*)|*.*'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output $dialog.FileName
}
""";
        final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          pickedPath = path;
        }
      } catch (e) {
        debugPrint('File picker error: $e');
      }
    }

    if (pickedPath == null) return;

    setState(() {
      _localAvatarPath = pickedPath;
      _isUploadingAvatar = true;
    });

    try {
      final file = File(pickedPath);
      final url = await ApiService.instance.uploadPhoto(file);
      if (mounted) {
        setState(() {
          _uploadedAvatarUrl = url;
          _isUploadingAvatar = false;
        });
      }
    } catch (e) {
      debugPrint('Error uploading channel avatar: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _createChannel() async {
    final title = _titleController.text.trim();
    final username = _usernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите название канала'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (username.length < 5 || username.length > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Имя пользователя должно содержать от 5 до 12 символов'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_isUsernameAvailable != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Выбранное имя пользователя недоступно'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      String avatar = _uploadedAvatarUrl;
      if (avatar.isEmpty && _localAvatarPath != null) {
        try {
          avatar = await ApiService.instance.uploadPhoto(File(_localAvatarPath!));
        } catch (_) {}
      }

      final res = await ApiService.instance.createChannel(
        title: title,
        username: username,
        description: description,
        avatar: avatar,
      );

      final channelMap = res['channel'] is Map<String, dynamic> ? res['channel'] as Map<String, dynamic> : null;
      final chatId = channelMap != null ? (channelMap['chat_id'] ?? channelMap['id']) : null;

      final chatProvider = context.read<ChatProvider>();
      await chatProvider.syncBootstrap();

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Канал «$title» успешно создан!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      if (chatId != null) {
        final parsedId = chatId is int ? chatId : int.tryParse(chatId.toString());
        final currentUserId = context.read<AuthProvider>().currentUser?.id;
        if (parsedId != null) {
          var createdChat = chatProvider.chats.where((c) => c.id == parsedId).firstOrNull;
          createdChat ??= Chat(
            id: parsedId,
            title: title,
            type: 'channel',
            avatar: avatar,
            isChannel: true,
            username: username,
            description: description,
            ownerId: currentUserId,
            subscribersCount: 1,
            isSubscribed: true,
          );
          if (createdChat.ownerId == null && currentUserId != null) {
            createdChat = createdChat.copyWith(ownerId: currentUserId);
          }
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ChatScreen(chat: createdChat!)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.destructive,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isPremium = auth.currentUser?.isPremium == true;

    final canSubmit = _titleController.text.trim().isNotEmpty &&
        _isUsernameAvailable == true &&
        !_isCheckingUsername &&
        !_isSubmitting;

    Color statusColor;
    IconData? statusIcon;
    if (_isCheckingUsername) {
      statusColor = const Color(0xFF929292);
      statusIcon = null;
    } else if (_isUsernameAvailable == true) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
    } else if (_isUsernameAvailable == false) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.error_outline_rounded;
    } else {
      statusColor = const Color(0xFF929292);
      statusIcon = null;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090909),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Новый канал',
          style: TextStyle(
            fontFamily: AppTheme.fontDisplay,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: canSubmit ? _createChannel : null,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3B98FF),
                disabledForegroundColor: const Color(0x663B98FF),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B98FF)),
                    )
                  : const Text('Создать'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // =================================================================
            // LIMITS BANNER (Premium indicator)
            // =================================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPremium ? const Color(0x333B98FF) : const Color(0x1AFFFFFF),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isPremium ? const Color(0x263B98FF) : const Color(0x1AFFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPremium ? Icons.star_rounded : Icons.campaign_rounded,
                      color: isPremium ? const Color(0xFF3B98FF) : Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Каналы: ${widget.ownedCount} из ${widget.maxChannels}',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPremium
                              ? 'Лимит подписки Premium (до 8 каналов)'
                              : 'Базовый лимит: до 3 каналов (Premium: до 8)',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12,
                            color: Color(0xFF929292),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // =================================================================
            // AVATAR PICKER
            // =================================================================
            Center(
              child: GestureDetector(
                onTap: _isUploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: const Color(0xFF191919),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x26FFFFFF), width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _localAvatarPath != null
                          ? Image.file(
                              File(_localAvatarPath!),
                              fit: BoxFit.cover,
                            )
                          : (_uploadedAvatarUrl.isNotEmpty
                              ? Image.network(
                                  AppConstants.formatMediaUrl(_uploadedAvatarUrl),
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Color(0xFF929292),
                                  size: 34,
                                )),
                    ),
                    if (_isUploadingAvatar)
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        ),
                      )
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B98FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_a_photo_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: _isUploadingAvatar ? null : _pickAvatar,
                child: const Text(
                  'Выбрать аватарку',
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 13,
                    color: Color(0xFF3B98FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // =================================================================
            // TITLE INPUT
            // =================================================================
            const Text(
              'Название канала',
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF929292),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
              ),
              child: TextField(
                controller: _titleController,
                maxLength: 64,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: const InputDecoration(
                  hintText: 'Например: Портал Новости',
                  hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 15),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // =================================================================
            // USERNAME INPUT (@username)
            // =================================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Имя пользователя (@username)',
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF929292),
                  ),
                ),
                Text(
                  '${_usernameController.text.trim().replaceFirst('@', '').length}/12',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 12,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isUsernameAvailable == false
                      ? const Color(0x66EF4444)
                      : (_isUsernameAvailable == true ? const Color(0x6610B981) : const Color(0x1AFFFFFF)),
                  width: 1.0,
                ),
              ),
              child: TextField(
                controller: _usernameController,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                onChanged: _onUsernameChanged,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  color: Colors.white,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  prefixText: '@',
                  prefixStyle: const TextStyle(
                    color: Color(0xFF3B98FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  hintText: 'channel_username',
                  hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: _isCheckingUsername
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF929292)),
                          ),
                        )
                      : (statusIcon != null
                          ? Icon(statusIcon, color: statusColor, size: 20)
                          : null),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_usernameStatusMessage != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _usernameStatusMessage!,
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            const SizedBox(height: 22),

            // =================================================================
            // DESCRIPTION INPUT
            // =================================================================
            const Text(
              'Описание (необязательно)',
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF929292),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
              ),
              child: TextField(
                controller: _descriptionController,
                maxLength: 255,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.35,
                ),
                decoration: const InputDecoration(
                  hintText: 'О чем будет ваш канал? Расскажите подписчикам...',
                  hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 14),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 36),

            // =================================================================
            // SUBMIT BUTTON
            // =================================================================
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: canSubmit ? _createChannel : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B98FF),
                  disabledBackgroundColor: const Color(0x333B98FF),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: const Color(0x66FFFFFF),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Создать канал',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

