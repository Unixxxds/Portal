import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _usernameController;
  late TextEditingController _descriptionController;

  String _currentAvatar = '';
  String _currentBanner = '';
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingBanner = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _descriptionController = TextEditingController(text: user?.description ?? '');
    _currentAvatar = user?.avatar ?? '';
    _currentBanner = user?.bannerUrl ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Opens native Windows file dialog to choose an image from PC
  Future<String?> _pickImageFromPC({
    required String title,
    String filter = 'Изображения и анимации (*.gif;*.webp;*.png;*.jpg;*.jpeg)|*.gif;*.webp;*.png;*.jpg;*.jpeg|Анимированные GIF (*.gif)|*.gif|Анимированные WebP (*.webp)|*.webp|Все файлы (*.*)|*.*',
  }) async {
    if (Platform.isWindows) {
      try {
        final script = r"""
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = '""" + title + r"""'
$dialog.Filter = '""" + filter + r"""'
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output $dialog.FileName
}
""";
        final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      } catch (e) {
        debugPrint('File picker error: $e');
      }
    }
    return null;
  }

  Future<void> _uploadAvatarFromPC() async {
    final filePath = await _pickImageFromPC(title: 'Выберите аватарку');
    if (filePath == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final file = File(filePath);
      final uploadedUrl = await ApiService.instance.uploadAvatar(file);
      if (mounted && uploadedUrl.isNotEmpty) {
        setState(() {
          _currentAvatar = uploadedUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Аватарка успешно загружена', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF191919),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: const Color(0xFF191919),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _uploadBannerFromPC() async {
    final filePath = await _pickImageFromPC(
      title: 'Выберите баннер профиля (поддерживаются анимированные GIF, WebP)',
      filter: 'Баннеры и анимации (*.gif;*.webp;*.png;*.jpg;*.jpeg)|*.gif;*.webp;*.png;*.jpg;*.jpeg|Анимированные GIF (*.gif)|*.gif|Анимированные WebP (*.webp)|*.webp|Все файлы (*.*)|*.*',
    );
    if (filePath == null) return;

    setState(() => _isUploadingBanner = true);
    try {
      final file = File(filePath);
      final uploadedUrl = await ApiService.instance.uploadBanner(file);
      if (mounted && uploadedUrl.isNotEmpty) {
        setState(() {
          _currentBanner = uploadedUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Баннер успешно загружен', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF191919),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: const Color(0xFF191919),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingBanner = false);
      }
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Загрузить фото с устройства',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Открыть проводник файлов и выбрать изображение',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _uploadAvatarFromPC();
                  },
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.link_rounded, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Указать ссылку на фото',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showUrlDialog(
                      title: 'Ссылка на аватарку',
                      hint: 'https://... или /uploads/...',
                      currentVal: _currentAvatar,
                      onSave: (val) => setState(() => _currentAvatar = val),
                    );
                  },
                ),
                if (_currentAvatar.isNotEmpty) ...[
                  const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0x26EF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    ),
                    title: const Text(
                      'Удалить аватарку',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Color(0xFFEF4444),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _currentAvatar = '');
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBannerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Загрузить баннер с устройства',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'GIF, WebP, PNG, JPG (поддерживаются анимации)',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _uploadBannerFromPC();
                  },
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFF242424),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.link_rounded, color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    'Указать ссылку на баннер',
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showUrlDialog(
                      title: 'Ссылка на баннер',
                      hint: 'https://... или /uploads/...',
                      currentVal: _currentBanner,
                      onSave: (val) => setState(() => _currentBanner = val),
                    );
                  },
                ),
                if (_currentBanner.isNotEmpty) ...[
                  const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0x26EF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    ),
                    title: const Text(
                      'Удалить баннер',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Color(0xFFEF4444),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() => _currentBanner = '');
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUrlDialog({
    required String title,
    required String hint,
    required String currentVal,
    required ValueChanged<String> onSave,
  }) {
    final controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191919),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
        title: Text(
          title,
          style: const TextStyle(fontFamily: AppTheme.fontDisplay, color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontFamily: AppTheme.fontText, color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 14),
              border: InputBorder.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF929292))),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    final firstName = _firstNameController.text.trim();
    if (firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Имя обязательно для заполнения'),
          backgroundColor: const Color(0xFF191919),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final rawUsername = _usernameController.text.trim().replaceAll(RegExp(r'^@+'), '');
    if (rawUsername.isNotEmpty) {
      if (rawUsername.length < 5 || rawUsername.length > 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Имя пользователя должно содержать от 5 до 12 символов',
              style: TextStyle(fontFamily: AppTheme.fontText, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF191919),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
            ),
          ),
        );
        return;
      }
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(rawUsername)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Имя пользователя может содержать только латинские буквы, цифры и _',
              style: TextStyle(fontFamily: AppTheme.fontText, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF191919),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();

    try {
      await auth.updateProfile(
        firstName: firstName,
        lastName: _lastNameController.text.trim(),
        username: rawUsername,
        description: _descriptionController.text.trim(),
        avatar: _currentAvatar,
        bannerUrl: _currentBanner,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Профиль успешно сохранен и обновлен в базе',
              style: TextStyle(fontFamily: AppTheme.fontText, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF191919),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: const Color(0xFF191919),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedBanner = AppConstants.formatMediaUrl(_currentBanner);

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // =================================================================
            // TOP BAR: Отмена | Редактирование | Готово
            // =================================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF191919),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Редактирование',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _isSaving ? null : _handleSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF090909),
                              ),
                            )
                          : const Text(
                              'Готово',
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF090909),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // =================================================================
            // SCROLLABLE FORM
            // =================================================================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  // HERO BANNER & AVATAR PREVIEW
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Banner background
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 130,
                          child: formattedBanner.isNotEmpty
                              ? Image.network(
                                  formattedBanner,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF242424), Color(0xFF191919)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.landscape_outlined, color: Color(0xFF929292), size: 36),
                                    ),
                                  ),
                                )
                              : Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF242424), Color(0xFF191919)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.landscape_outlined, color: Color(0xFF929292), size: 36),
                                  ),
                                ),
                        ),

                        // Bottom smooth fade into graphite card background
                        Positioned(
                          top: 75,
                          left: 0,
                          right: 0,
                          height: 55,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0x33191919),
                                  Color(0x80191919),
                                  Color(0xD9191919),
                                  Color(0xFF191919),
                                ],
                                stops: [0.0, 0.25, 0.55, 0.8, 1.0],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),

                        // Edit Banner Button
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: _isUploadingBanner ? null : _showBannerOptions,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isUploadingBanner)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white),
                                    )
                                  else
                                    const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 14),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isUploadingBanner ? 'Загрузка...' : 'Загрузить баннер',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Avatar positioned overlapping banner
                        Positioned(
                          left: 16,
                          bottom: 12,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF191919), width: 3),
                                ),
                                child: AvatarWidget(
                                  avatarUrl: _currentAvatar,
                                  title: _firstNameController.text.isNotEmpty
                                      ? _firstNameController.text
                                      : 'U',
                                  size: 74,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: _isUploadingAvatar ? null : _showAvatarOptions,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF090909),
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: _isUploadingAvatar
                                          ? const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFF090909)),
                                            )
                                          : const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Color(0xFF090909),
                                              size: 13,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Hint text next to avatar
                        Positioned(
                          left: 104,
                          bottom: 22,
                          right: 16,
                          child: GestureDetector(
                            onTap: _isUploadingAvatar ? null : _showAvatarOptions,
                            child: Row(
                              children: [
                                const Icon(Icons.file_upload_outlined, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  _isUploadingAvatar ? 'Загрузка файла...' : 'Загрузить фото профиля',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ===========================================================
                  // GROUPED CARD 1: ИМЯ И ФАМИЛИЯ
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // First Name
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ИМЯ',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF929292),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _firstNameController,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Ваше имя',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Color(0xFF6B7280),
                                    fontSize: 15,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0x14FFFFFF), indent: 16),

                        // Last Name
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ФАМИЛИЯ (НЕОБЯЗАТЕЛЬНО)',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF929292),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _lastNameController,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Ваша фамилия',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Color(0xFF6B7280),
                                    fontSize: 15,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ===========================================================
                  // GROUPED CARD 2: ЮЗЕРНЕЙМ (@username)
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'ИМЯ ПОЛЬЗОВАТЕЛЯ',
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF929292),
                                letterSpacing: 0.5,
                              ),
                            ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _usernameController,
                              builder: (context, val, _) {
                                final len = val.text.trim().replaceAll(RegExp(r'^@+'), '').length;
                                return Text(
                                  '$len/12',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: (len > 0 && len < 5) ? const Color(0xFFEF4444) : const Color(0xFF929292),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text(
                              '@',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF929292),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _usernameController,
                                maxLength: 12,
                                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                                  LengthLimitingTextInputFormatter(12),
                                ],
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'username',
                                  hintStyle: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Color(0xFF6B7280),
                                    fontSize: 15,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 16),
                    child: Text(
                      'От 5 до 12 символов (только латинские буквы a-z, цифры и символ _). Другие люди смогут находить вас по этому имени.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12,
                        color: Color(0xFF929292),
                        height: 1.35,
                      ),
                    ),
                  ),

                  // ===========================================================
                  // GROUPED CARD 3: О СЕБЕ / БИО
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'О СЕБЕ',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF929292),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _descriptionController,
                          maxLines: 4,
                          maxLength: 140,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontText,
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.35,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Расскажите немного о себе...',
                            hintStyle: TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Color(0xFF6B7280),
                              fontSize: 14.5,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            counterStyle: TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Color(0xFF6B7280),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 24),
                    child: Text(
                      'Любые подробности о вас, ссылки или интересы. Описание отображается в вашем профиле.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
