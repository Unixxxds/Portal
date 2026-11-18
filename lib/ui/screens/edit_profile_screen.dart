import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/badges.dart';
import 'create_channel_screen.dart';

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
  int? _selectedChannelId;
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
    _selectedChannelId = user?.pinnedChannelId;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Chooses an image from device gallery (mobile) or native file dialog (PC)
  Future<String?> _pickImage({
    required String title,
    ImageSource source = ImageSource.gallery,
    bool pickMedia = false,
    String filter = 'Изображения и анимации (*.gif;*.webp;*.png;*.jpg;*.jpeg;*.mp4;*.mov)|*.gif;*.webp;*.png;*.jpg;*.jpeg;*.mp4;*.mov|Анимированные GIF (*.gif)|*.gif|Анимированные WebP (*.webp)|*.webp|Все файлы (*.*)|*.*',
  }) async {
    // 1. Mobile platforms (Android / iOS)
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final picker = ImagePicker();
        XFile? picked;
        if (pickMedia) {
          try {
            picked = await picker.pickMedia();
          } catch (_) {
            picked = await picker.pickImage(source: source, imageQuality: 95);
          }
        } else {
          picked = await picker.pickImage(source: source, imageQuality: 92);
        }
        if (picked != null && picked.path.isNotEmpty) {
          final file = File(picked.path);
          if (await file.exists()) {
            return picked.path;
          }
        }
      } catch (e) {
        debugPrint('Mobile image picker error: $e');
      }
      return null;
    }

    // 2. Windows PC
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
        debugPrint('Windows file picker error: $e');
      }
      return null;
    }

    // 3. Fallback
    try {
      final picker = ImagePicker();
      final picked = pickMedia ? await picker.pickMedia() : await picker.pickImage(source: source);
      if (picked != null && picked.path.isNotEmpty) {
        return picked.path;
      }
    } catch (e) {
      debugPrint('Fallback image picker error: $e');
    }
    return null;
  }

  Future<void> _uploadAvatar({ImageSource source = ImageSource.gallery}) async {
    final filePath = await _pickImage(
      title: 'Выберите аватарку',
      source: source,
    );
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
            content: const Text('Аватарка успешно обновлена', style: TextStyle(color: Colors.white)),
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

  Future<void> _uploadBanner({
    ImageSource source = ImageSource.gallery,
    bool pickMedia = false,
  }) async {
    final isPremium = context.read<AuthProvider>().currentUser?.isPremium ?? false;
    if (!isPremium) {
      _showPremiumBannerRequiredDialog();
      return;
    }

    final filePath = await _pickImage(
      title: 'Выберите баннер профиля (поддерживаются Live-фото, анимированные GIF, WebP)',
      source: source,
      pickMedia: pickMedia,
      filter: 'Баннеры и анимации (*.gif;*.webp;*.png;*.jpg;*.jpeg;*.mp4;*.mov)|*.gif;*.webp;*.png;*.jpg;*.jpeg;*.mp4;*.mov|Анимированные GIF (*.gif)|*.gif|Анимированные WebP (*.webp)|*.webp|Все файлы (*.*)|*.*',
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

  void _showPremiumBannerRequiredDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0x40FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B98FF).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: PremiumBadge(size: 32),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Баннер только с Premium',
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Установка кастомных и анимированных баннеров профиля доступна исключительно с подпиской Portal Premium.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 14,
                    color: Color(0xFF929292),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B98FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        'Понятно',
                        style: TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAvatarOptions() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
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
                    child: Icon(
                      isMobile ? Icons.photo_library_outlined : Icons.file_upload_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    isMobile ? 'Выбрать из галереи' : 'Загрузить фото с устройства',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    isMobile ? 'Открыть медиатеку и выбрать снимок' : 'Открыть проводник файлов и выбрать изображение',
                    style: const TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _uploadAvatar(source: ImageSource.gallery);
                  },
                ),
                if (isMobile) ...[
                  const Divider(height: 1, color: Color(0x14FFFFFF), indent: 56),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF242424),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                    ),
                    title: const Text(
                      'Сделать снимок',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Открыть камеру устройства',
                      style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _uploadAvatar(source: ImageSource.camera);
                    },
                  ),
                ],
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
    final isPremium = context.read<AuthProvider>().currentUser?.isPremium ?? false;
    if (!isPremium) {
      _showPremiumBannerRequiredDialog();
      return;
    }

    final isMobile = Platform.isAndroid || Platform.isIOS;
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
                    child: Icon(
                      isMobile ? Icons.photo_library_outlined : Icons.file_upload_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    isMobile ? 'Выбрать баннер из галереи' : 'Загрузить баннер с устройства',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'PNG, JPG, статичные изображения',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _uploadBanner(source: ImageSource.gallery);
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
                    child: const Icon(Icons.motion_photos_on_rounded, color: Color(0xFF3B98FF), size: 20),
                  ),
                  title: const Row(
                    children: [
                      Text(
                        'Live-фото / Анимация',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 6),
                      PremiumBadge(size: 14),
                    ],
                  ),
                  subtitle: const Text(
                    'Живое фото, зацикленная анимация GIF или WebP',
                    style: TextStyle(fontFamily: AppTheme.fontText, color: Color(0xFF929292), fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _uploadBanner(source: ImageSource.gallery, pickMedia: true);
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

  void _showChannelSelectionModal() {
    final chatProvider = context.read<ChatProvider>();
    final currentUserId = context.read<AuthProvider>().currentUser?.id ?? 0;

    final myChannels = chatProvider.chats.where((c) {
      if (!c.isChannel) return false;
      if (c.ownerId != null && c.ownerId == currentUserId) return true;
      if (c.ownerId == null || c.ownerId == 0) return true;
      return false;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191919),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x40FFFFFF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Title
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Канал в профиле',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Выберите ваш канал для отображения на странице профиля',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 13,
                                    color: Color(0xFF929292),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Color(0xFF242424),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Option to unbind channel if one is selected
                      if (_selectedChannelId != null) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0x26EF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.remove_circle_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Не отображать канал',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          subtitle: const Text(
                            'Убрать плашку канала из профиля',
                            style: TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 12,
                              color: Color(0xFF929292),
                            ),
                          ),
                          onTap: () {
                            setState(() => _selectedChannelId = null);
                            Navigator.pop(ctx);
                          },
                        ),
                        const Divider(height: 16, color: Color(0x14FFFFFF)),
                      ],

                      // List of channels
                      if (myChannels.isNotEmpty)
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: myChannels.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0x14FFFFFF),
                              indent: 56,
                            ),
                            itemBuilder: (_, index) {
                              final channel = myChannels[index];
                              final isSelected = _selectedChannelId == channel.id;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                leading: AvatarWidget(
                                  avatarUrl: channel.avatar,
                                  title: channel.title,
                                  size: 40,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        channel.title,
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontDisplay,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? const Color(0xFF3B98FF) : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (channel.isVerified) ...[
                                      const SizedBox(width: 4),
                                      VerificationBadge(
                                        verification: channel.effectiveVerification,
                                        size: 14,
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  channel.subscribersCount > 0
                                      ? '${channel.subscribersCount} подписчиков'
                                      : 'Новый канал',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    fontSize: 12,
                                    color: Color(0xFF929292),
                                  ),
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF3B98FF),
                                        size: 22,
                                      )
                                    : null,
                                onTap: () {
                                  setState(() => _selectedChannelId = channel.id);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                        )
                      else ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.campaign_outlined,
                                color: Color(0xFF929292),
                                size: 40,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'У вас пока нет созданных каналов',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Создайте собственный канал, чтобы закрепить его на странице своего профиля',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 12.5,
                                  color: Color(0xFF929292),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const CreateChannelScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text(
                                  'Создать канал',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
        pinnedChannelId: _selectedChannelId,
        clearPinnedChannel: _selectedChannelId == null,
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
    final isPremium = context.watch<AuthProvider>().currentUser?.isPremium ?? false;
    final formattedBanner = AppConstants.formatMediaUrl(_currentBanner);
    final chatProvider = context.watch<ChatProvider>();
    final selectedChannel = _selectedChannelId != null
        ? chatProvider.chats.where((c) => c.isChannel && c.id == _selectedChannelId).firstOrNull
        : null;

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
                      borderRadius: BorderRadius.circular(22),
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
                                  color: isPremium
                                      ? Colors.white.withOpacity(0.2)
                                      : const Color(0xFF3B98FF).withOpacity(0.5),
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
                                  else if (!isPremium) ...[
                                    const PremiumBadge(size: 13),
                                    const SizedBox(width: 5),
                                  ] else ...[
                                    const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 14),
                                    const SizedBox(width: 5),
                                  ],
                                  Text(
                                    _isUploadingBanner
                                        ? 'Загрузка...'
                                        : (isPremium ? 'Загрузить баннер' : 'Баннер (Premium)'),
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isPremium ? Colors.white : const Color(0xFF64B5F6),
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
                  if (!isPremium) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1E2838).withOpacity(0.9),
                            const Color(0xFF131A26).withOpacity(0.9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF3B98FF).withOpacity(0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B98FF).withOpacity(0.16),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: PremiumBadge(size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Баннер профиля',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontDisplay,
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Кастомный баннер доступен только с подпиской Premium',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Color(0xFF8BA5C8),
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ===========================================================
                  // GROUPED CARD 1: ИМЯ И ФАМИЛИЯ (1:1 с референсом)
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // First Name
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: TextField(
                            controller: _firstNameController,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Имя',
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Color(0xFF6B7280),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0x14FFFFFF), indent: 16),

                        // Last Name
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: TextField(
                            controller: _lastNameController,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Фамилия (необязательно)',
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.fontText,
                                color: Color(0xFF6B7280),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: Text(
                      'Укажите имя и, если хотите, добавьте фотографию для Вашего профиля.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12.5,
                        color: Color(0xFF929292),
                        height: 1.35,
                      ),
                    ),
                  ),

                  // ===========================================================
                  // GROUPED CARD 2: О СЕБЕ (перемещен под плашку имени и фамилии)
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      maxLength: 140,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontText,
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'О себе',
                        hintStyle: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Color(0xFF6B7280),
                          fontSize: 15,
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
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: Text(
                      'Раздел «О себе» виден всем.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12.5,
                        color: Color(0xFF929292),
                        height: 1.35,
                      ),
                    ),
                  ),

                  // ===========================================================
                  // GROUPED CARD 3: ИМЯ ПОЛЬЗОВАТЕЛЯ С ИКОНКОЙ @ (1:1 с референсом)
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Фиолетовая иконка @
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5E5CE6),
                            borderRadius: BorderRadius.circular(8.5),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.alternate_email_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Имя пользователя',
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Text(
                                '@',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3B98FF),
                                ),
                              ),
                              Flexible(
                                child: IntrinsicWidth(
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
                                      color: Color(0xFF3B98FF),
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'username',
                                      hintStyle: TextStyle(
                                        fontFamily: AppTheme.fontText,
                                        color: Color(0xFF6B7280),
                                        fontSize: 15.5,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                  // GROUPED CARD 4: КАНАЛ В ПРОФИЛЕ
                  // ===========================================================
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF191919),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0x1AFFFFFF), width: 1.0),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showChannelSelectionModal,
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              // Синяя иконка рупора
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF),
                                  borderRadius: BorderRadius.circular(8.5),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.campaign_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'Каналы',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontDisplay,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (selectedChannel != null) ...[
                                      Flexible(
                                        child: Text(
                                          selectedChannel.title,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF3B98FF),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (selectedChannel.isVerified) ...[
                                        const SizedBox(width: 4),
                                        VerificationBadge(
                                          verification: selectedChannel.effectiveVerification,
                                          size: 14,
                                        ),
                                      ],
                                    ] else ...[
                                      const Text(
                                        'Не выбран',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontText,
                                          fontSize: 14.5,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF6B7280),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text(
                      'Выберите канал, в котором вы являетесь создателем. Он будет закреплен и отображаться в вашем профиле.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontText,
                        fontSize: 12,
                        color: Color(0xFF929292),
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
