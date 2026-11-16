import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../../data/database_helper.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../widgets/avatar_widget.dart';

class EditChannelScreen extends StatefulWidget {
  final Chat chat;

  const EditChannelScreen({super.key, required this.chat});

  @override
  State<EditChannelScreen> createState() => _EditChannelScreenState();
}

class _EditChannelScreenState extends State<EditChannelScreen> {
  late TextEditingController _titleController;
  late TextEditingController _usernameController;
  late TextEditingController _descriptionController;

  String? _localAvatarPath;
  String? _uploadedAvatarUrl;
  bool _isUploadingAvatar = false;

  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameStatusMessage;
  Timer? _debounceTimer;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.chat.title);
    final initialUname = (widget.chat.username ?? '').replaceFirst(RegExp(r'^@+'), '');
    _usernameController = TextEditingController(text: initialUname);
    _descriptionController = TextEditingController(text: widget.chat.description ?? '');
    _uploadedAvatarUrl = widget.chat.avatar;
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
    final initialUname = (widget.chat.username ?? '').replaceFirst(RegExp(r'^@+'), '');

    if (clean.toLowerCase() == initialUname.toLowerCase()) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = true;
        _usernameStatusMessage = 'Текущее имя пользователя канала';
      });
      return;
    }

    if (clean.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameStatusMessage = 'Имя пользователя не может быть пустым';
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
        _usernameStatusMessage = 'Только латинские буквы, цифры и _';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
      _usernameStatusMessage = 'Проверка доступности...';
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
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
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
          _usernameStatusMessage = 'Ошибка проверки имени пользователя';
        });
      }
    });
  }

  Future<void> _pickAvatar() async {
    String? pickedPath;
    if (Platform.isWindows) {
      try {
        const script = r"""
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
      debugPrint('Error uploading channel avatar: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить фотографию')),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название канала не может быть пустым')),
      );
      return;
    }

    final username = _usernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');
    final initialUname = (widget.chat.username ?? '').replaceFirst(RegExp(r'^@+'), '');
    final isUsernameChanged = username.toLowerCase() != initialUname.toLowerCase();

    if (isUsernameChanged) {
      if (username.length < 5 || username.length > 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Имя пользователя должно быть от 5 до 12 символов')),
        );
        return;
      }
      if (_isUsernameAvailable == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_usernameStatusMessage ?? 'Имя пользователя занято')),
        );
        return;
      }
      if (_isCheckingUsername) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подождите завершения проверки юзернейма')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final desc = _descriptionController.text.trim();
      final avatarUrl = _uploadedAvatarUrl ?? widget.chat.avatar;

      await ApiService.instance.updateChannel(
        chatId: widget.chat.id,
        title: title,
        username: username,
        description: desc,
        avatar: avatarUrl,
      );

      await DatabaseHelper.instance.updateChatDetails(
        chatId: widget.chat.id,
        title: title,
        username: username,
        description: desc,
        avatar: avatarUrl,
      );

      final updatedChat = widget.chat.copyWith(
        title: title,
        username: username,
        description: desc,
        avatar: avatarUrl,
      );

      if (mounted) {
        final chatProv = context.read<ChatProvider>();
        chatProv.addOrUpdateChat(updatedChat);
        Navigator.of(context).pop(updatedChat);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = 88.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Отмена',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        leadingWidth: 80,
        title: const Text(
          'Канал',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            fontFamily: AppTheme.fontDisplay,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: (_isSaving || _isCheckingUsername) ? null : _saveChanges,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A84FF)),
                  )
                : const Text(
                    'Готово',
                    style: TextStyle(
                      color: Color(0xFF0A84FF),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Avatar picker
            Center(
              child: GestureDetector(
                onTap: _isUploadingAvatar ? null : _pickAvatar,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_localAvatarPath != null)
                      ClipOval(
                        child: Image.file(
                          File(_localAvatarPath!),
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      AvatarWidget(
                        avatarUrl: _uploadedAvatarUrl ?? widget.chat.avatar,
                        title: _titleController.text.isNotEmpty ? _titleController.text : widget.chat.title,
                        size: avatarSize,
                        isChannel: true,
                      ),
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.35),
                      ),
                      child: Center(
                        child: _isUploadingAvatar
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _isUploadingAvatar ? null : _pickAvatar,
              child: const Text(
                'Выбрать фото',
                style: TextStyle(
                  color: Color(0xFF0A84FF),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Card 1: Title and Description
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Название канала',
                      hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const Divider(height: 1, color: Color(0xFF2C2C2E), indent: 16, endIndent: 16),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    maxLines: 4,
                    minLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Описание (необязательно)',
                      hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Card 2: Link / Username
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ССЫЛКА НА КАНАЛ',
                  style: TextStyle(
                    color: const Color(0xFF8E8E93).withOpacity(0.8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'https://portalmsg.ru/',
                        style: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 15,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'username',
                            hintStyle: TextStyle(color: Color(0xFF636366)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: _onUsernameChanged,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                            LengthLimitingTextInputFormatter(12),
                          ],
                        ),
                      ),
                      if (_isCheckingUsername)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A84FF)),
                        )
                      else if (_isUsernameAvailable == true)
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 18)
                      else if (_isUsernameAvailable == false)
                        const Icon(Icons.cancel_rounded, color: Color(0xFFFF3B30), size: 18),
                    ],
                  ),
                  if (_usernameStatusMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _usernameStatusMessage!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _isUsernameAvailable == true
                            ? const Color(0xFF34C759)
                            : (_isUsernameAvailable == false
                                ? const Color(0xFFFF3B30)
                                : const Color(0xFF8E8E93)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'По этой ссылке другие пользователи смогут найти и открыть ваш канал. Имя пользователя может содержать от 5 до 12 символов (буквы a-z, цифры и _).',
                style: TextStyle(
                  color: const Color(0xFF8E8E93).withOpacity(0.8),
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
