import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/telegram_chat_route.dart';
import 'chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _localAvatarPath;
  String _uploadedAvatarUrl = '';
  bool _isUploadingAvatar = false;
  bool _isSubmitting = false;

  bool _isPublic = false; // false = Приватная, true = Публичная
  late String _generatedInviteCode;

  Timer? _debounceTimer;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameStatusMessage;

  @override
  void initState() {
    super.initState();
    _generatedInviteCode = _generateRandomCode();
    _usernameStatusMessage = 'От 3 до 16 символов (латиница, цифры, _)';
  }

  String _generateRandomCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
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
        _usernameStatusMessage = 'От 3 до 16 символов (латиница, цифры, _)';
      });
      return;
    }

    if (clean.length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Минимум 3 символа';
      });
      return;
    }

    if (clean.length > 16) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Максимум 16 символов';
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
      final available = await ApiService.instance.checkGroupUsername(clean);
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
    HapticFeedback.lightImpact();
    String? pickedPath;

    if (Platform.isWindows) {
      try {
        const script = r"""
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Выберите аватарку группы'
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

    if (pickedPath == null) {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
        if (picked != null) {
          pickedPath = picked.path;
        }
      } catch (e) {
        debugPrint('ImagePicker error: $e');
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
      debugPrint('Error uploading group avatar: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _createGroup() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final username = _usernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Введите название группы'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_isPublic) {
      if (username.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Введите имя пользователя для публичной группы (от 3 символов)'),
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
    }

    setState(() => _isSubmitting = true);

    try {
      String avatar = _uploadedAvatarUrl;
      if (avatar.isEmpty && _localAvatarPath != null) {
        try {
          avatar = await ApiService.instance.uploadPhoto(File(_localAvatarPath!));
        } catch (_) {}
      }

      final res = await ApiService.instance.createGroup(
        title: title,
        avatar: avatar,
        description: description,
        username: _isPublic ? username : null,
        isPublic: _isPublic,
        inviteCode: _isPublic ? null : _generatedInviteCode,
      );

      final groupMap = res['group'] is Map<String, dynamic> ? res['group'] as Map<String, dynamic> : null;
      final chatId = groupMap != null ? (groupMap['chat_id'] ?? groupMap['id']) : null;

      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.syncBootstrap();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Группа «$title» успешно создана!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF191919),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      if (chatId != null) {
        final parsedId = chatId is int ? chatId : int.tryParse(chatId.toString());
        final currentUserId = context.read<AuthProvider>().currentUser?.id;
        if (parsedId != null) {
          var createdChat = chatProvider.chats.where((c) => c.isGroup && c.id == parsedId).firstOrNull;
          createdChat ??= Chat(
            id: parsedId,
            title: title,
            type: 'group',
            avatar: avatar,
            ownerId: currentUserId,
            participantId: null,
            username: _isPublic ? username : _generatedInviteCode,
            inviteCode: _isPublic ? null : _generatedInviteCode,
            membersCount: 1,
            subscribersCount: 1,
            isGroupChat: true,
            isSubscribed: true,
            verification: 'none',
            isPremium: false,
          );

          Navigator.push(
            context,
            TelegramChatRoute(
              builder: (context) => ChatScreen(chat: createdChat!),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      String errorMsg = e.toString().replaceAll('Exception: ', '');
      if (errorMsg.contains('502') || errorMsg.contains('status code of 502')) {
        errorMsg = 'Сервер временно недоступен (502 Bad Gateway). Обновите и перезапустите бэкенд на сервере.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2C1515),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _copyInviteLink() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: 'https://portalmsg.ru/$_generatedInviteCode'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ссылка скопирована в буфер обмена'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF191919),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inviteLink = 'https://portalmsg.ru/$_generatedInviteCode';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Новая группа',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTheme.fontDisplay,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 18),

                    // Center Avatar Selection
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0x25FFFFFF), width: 1.5),
                              image: _localAvatarPath != null
                                  ? DecorationImage(
                                      image: FileImage(File(_localAvatarPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _localAvatarPath == null
                                ? const Center(
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      color: Color(0xFF8E8E93),
                                      size: 36,
                                    ),
                                  )
                                : null,
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
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Text(
                        _localAvatarPath == null ? 'Установить фото' : 'Изменить фото',
                        style: const TextStyle(
                          color: Color(0xFF2990FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppTheme.fontText,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Group Name Input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _titleController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: AppTheme.fontText,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Название группы',
                          hintStyle: TextStyle(
                            color: Color(0xFF636366),
                            fontSize: 16,
                            fontFamily: AppTheme.fontText,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Description Input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _descriptionController,
                        maxLines: 3,
                        minLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontFamily: AppTheme.fontText,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Описание (необязательно)',
                          hintStyle: TextStyle(
                            color: Color(0xFF636366),
                            fontSize: 15,
                            fontFamily: AppTheme.fontText,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Group Type Selector (Приватная / Публичная)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ТИП ГРУППЫ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          fontFamily: AppTheme.fontDisplay,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          // Option 1: Приватная
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _isPublic = false);
                            },
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    color: !_isPublic ? const Color(0xFF2990FF) : const Color(0xFF8E8E93),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Приватная',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: !_isPublic ? FontWeight.w600 : FontWeight.w400,
                                            fontFamily: AppTheme.fontDisplay,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Вход только по уникальной ссылке',
                                          style: TextStyle(
                                            color: Color(0xFF8E8E93),
                                            fontSize: 13,
                                            fontFamily: AppTheme.fontText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!_isPublic)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF2990FF),
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const Divider(height: 1, color: Color(0xFF2C2C2E), indent: 52),

                          // Option 2: Публичная
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _isPublic = true);
                            },
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.public_rounded,
                                    color: _isPublic ? const Color(0xFF2990FF) : const Color(0xFF8E8E93),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Публичная',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: _isPublic ? FontWeight.w600 : FontWeight.w400,
                                            fontFamily: AppTheme.fontDisplay,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Любой может найти через поиск',
                                          style: TextStyle(
                                            color: Color(0xFF8E8E93),
                                            fontSize: 13,
                                            fontFamily: AppTheme.fontText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_isPublic)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF2990FF),
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // If Private: Show Generated Link
                    if (!_isPublic) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ССЫЛКА-ПРИГЛАШЕНИЕ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            fontFamily: AppTheme.fontDisplay,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.link_rounded,
                              color: Color(0xFF2990FF),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                inviteLink,
                                style: const TextStyle(
                                  color: Color(0xFF2990FF),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: AppTheme.fontText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: _copyInviteLink,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2C2C2E),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.copy_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'По этой ссылке пользователи смогут присоединиться к вашей приватной группе.',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 13,
                            fontFamily: AppTheme.fontText,
                          ),
                        ),
                      ),
                    ],

                    // If Public: Show Username Input with live availability check
                    if (_isPublic) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ЮЗЕРНЕЙМ ГРУППЫ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            fontFamily: AppTheme.fontDisplay,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            const Text(
                              '@',
                              style: TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _usernameController,
                                onChanged: _onUsernameChanged,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily: AppTheme.fontText,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'username',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF636366),
                                    fontSize: 16,
                                    fontFamily: AppTheme.fontText,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            if (_isCheckingUsername)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E8E93)),
                                ),
                              )
                            else if (_isUsernameAvailable == true)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 18)
                            else if (_isUsernameAvailable == false)
                              const Icon(Icons.cancel_rounded, color: Color(0xFFFF3B30), size: 18),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _usernameStatusMessage ?? 'Пользователи смогут находить группу по @$_usernameController.text',
                          style: TextStyle(
                            color: _isUsernameAvailable == true
                                ? const Color(0xFF34C759)
                                : (_isUsernameAvailable == false ? const Color(0xFFFF3B30) : const Color(0xFF8E8E93)),
                            fontSize: 13,
                            fontFamily: AppTheme.fontText,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 36),

                    // Submit Button (Pill Button, White with Black Text)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _createGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF3A3A3C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          elevation: 0,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : const Text(
                                'Создать группу',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: AppTheme.fontDisplay,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

