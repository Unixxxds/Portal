import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path/path.dart' as p;
import '../theme.dart';
import 'telegram_text_selection_toolbar.dart';

class PhotoPickerBottomSheet extends StatefulWidget {
  final Function(List<File> files, String caption) onSend;
  final VoidCallback? onOpenGifts;

  const PhotoPickerBottomSheet({
    super.key,
    required this.onSend,
    this.onOpenGifts,
  });

  static Future<void> show(
    BuildContext context, {
    required Function(List<File> files, String caption) onSend,
    VoidCallback? onOpenGifts,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => PhotoPickerBottomSheet(
        onSend: onSend,
        onOpenGifts: onOpenGifts,
      ),
    );
  }

  @override
  State<PhotoPickerBottomSheet> createState() => _PhotoPickerBottomSheetState();
}

class _PhotoPickerBottomSheetState extends State<PhotoPickerBottomSheet> {
  final List<File> _galleryFiles = [];
  final List<File> _selectedFiles = [];
  final TextEditingController _captionController = TextEditingController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadLocalPhotos();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalPhotos() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    final List<File> discovered = [];

    // 1. Mobile (iOS & Android): Request permission and load photos from device library
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        final PermissionState ps = await PhotoManager.requestPermissionExtend();
        final hasAccess = ps.isAuth || ps.hasAccess;

        if (hasAccess) {
          final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
            type: RequestType.image,
            onlyAll: true,
          );
          if (albums.isNotEmpty) {
            final List<AssetEntity> assets = await albums.first.getAssetListPaged(
              page: 0,
              size: 50,
            );
            final loadedFiles = await Future.wait(assets.map((a) => a.file));
            for (final f in loadedFiles) {
              if (f != null && f.existsSync()) {
                discovered.add(f);
              }
            }
          }
        } else {
          _permissionDenied = true;
        }
      } catch (e) {
        debugPrint('Error loading photos with PhotoManager: $e');
      }
    }

    // 2. Desktop (Windows) scanning
    if (Platform.isWindows) {
      try {
        final userProfile = Platform.environment['USERPROFILE'];
        final List<String> searchDirs = [];

        if (userProfile != null && userProfile.isNotEmpty) {
          searchDirs.add(p.join(userProfile, 'Pictures'));
          searchDirs.add(p.join(userProfile, 'Pictures', 'Screenshots'));
          searchDirs.add(p.join(userProfile, 'Pictures', 'Saved Pictures'));
          searchDirs.add(p.join(userProfile, 'Pictures', 'Camera Roll'));
          searchDirs.add(p.join(userProfile, 'Downloads'));
          searchDirs.add(p.join(userProfile, 'Desktop'));
          searchDirs.add(p.join(userProfile, 'OneDrive', 'Pictures'));
        }

        final validExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};

        for (final dirPath in searchDirs) {
          final dir = Directory(dirPath);
          if (await dir.exists()) {
            try {
              final entities = dir.listSync(followLinks: false);
              for (final entity in entities) {
                if (entity is File) {
                  final ext = p.extension(entity.path).toLowerCase();
                  if (validExts.contains(ext)) {
                    discovered.add(entity);
                  }
                }
              }
            } catch (_) {}
          }
        }

        discovered.sort((a, b) {
          try {
            return b.lastModifiedSync().compareTo(a.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });
      } catch (e) {
        debugPrint('Error scanning Windows photos: $e');
      }
    }

    if (mounted) {
      setState(() {
        _galleryFiles.clear();
        _galleryFiles.addAll(discovered.take(80));
        _isLoading = false;
      });
    }
  }

  Future<void> _handleBrowseTap() async {
    try {
      final picker = ImagePicker();
      final List<XFile> picked = await picker.pickMultiImage(limit: 5);
      if (picked.isNotEmpty && mounted) {
        setState(() {
          for (final xFile in picked.take(5)) {
            final file = File(xFile.path);
            if (!_galleryFiles.any((f) => f.path == file.path)) {
              _galleryFiles.insert(0, file);
            }
            if (!_selectedFiles.any((f) => f.path == file.path)) {
              if (_selectedFiles.length < 5) {
                _selectedFiles.add(file);
              }
            }
          }
        });
        return;
      }
    } catch (e) {
      debugPrint('ImagePicker error: $e');
    }

    if (Platform.isWindows) {
      await _pickFromComputerDialog();
    }
  }

  Future<void> _pickFromComputerDialog() async {
    if (!Platform.isWindows) return;

    try {
      const script = r"""
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Выберите фотографии (до 5)'
$dialog.Filter = 'Изображения (*.jpg;*.jpeg;*.png;*.webp;*.gif)|*.jpg;*.jpeg;*.png;*.webp;*.gif|Все файлы (*.*)|*.*'
$dialog.Multiselect = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output ($dialog.FileNames -join '|')
}
""";
      final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      final raw = result.stdout.toString().trim();
      if (raw.isNotEmpty) {
        final paths = raw
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && File(s).existsSync())
            .toList();

        if (paths.isNotEmpty && mounted) {
          setState(() {
            for (final path in paths) {
              final file = File(path);
              if (!_galleryFiles.any((f) => f.path == file.path)) {
                _galleryFiles.insert(0, file);
              }
              if (!_selectedFiles.any((f) => f.path == file.path)) {
                if (_selectedFiles.length < 5) {
                  _selectedFiles.add(file);
                }
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking from PC dialog: $e');
    }
  }

  void _toggleSelection(File file) {
    setState(() {
      final index = _selectedFiles.indexWhere((f) => f.path == file.path);
      if (index != -1) {
        _selectedFiles.removeAt(index);
      } else {
        if (_selectedFiles.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Можно выбрать не более 5 фотографий',
                style: TextStyle(color: Colors.white, fontFamily: AppTheme.fontText),
              ),
              backgroundColor: Color(0xFF262626),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedFiles.add(file);
      }
    });
  }

  Future<void> _handleSend() async {
    if (_selectedFiles.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSend(
        List<File>.from(_selectedFiles),
        _captionController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    // Выезжает снизу до середины экрана
    final sheetHeight = mediaQuery.size.height * 0.52;
    final keyboardHeight = mediaQuery.viewInsets.bottom;

    return Container(
      height: sheetHeight + keyboardHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF191919),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  _selectedFiles.isEmpty
                      ? 'Галерея'
                      : 'Выбрано: ${_selectedFiles.length} из 5',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (widget.onOpenGifts != null)
                  IconButton(
                    icon: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 20),
                    tooltip: 'Подарок',
                    onPressed: widget.onOpenGifts,
                  ),
                if (_selectedFiles.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedFiles.clear());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Сбросить',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Photos Grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: (_permissionDenied && _galleryFiles.isEmpty)
                        ? 2
                        : _galleryFiles.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // Первой плиткой идет кнопка "Обзор" (выбор из системы / файлов)
                        return GestureDetector(
                          onTap: _handleBrowseTap,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0x1AFFFFFF),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.folder_open_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Обзор',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (_permissionDenied && _galleryFiles.isEmpty && index == 1) {
                        return GestureDetector(
                          onTap: () => PhotoManager.openSetting(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0x1AFFFFFF),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Настройки',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final file = _galleryFiles[index - 1];
                      final isSelected = _selectedFiles.any((f) => f.path == file.path);
                      final selectedIdx = _selectedFiles.indexWhere((f) => f.path == file.path);

                      return GestureDetector(
                        onTap: () => _toggleSelection(file),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Photo preview
                              Image.file(
                                file,
                                fit: BoxFit.cover,
                                cacheWidth: 350,
                                errorBuilder: (ctx, _, __) => Container(
                                  color: const Color(0xFF222222),
                                  child: const Icon(
                                    Icons.broken_image_rounded,
                                    color: Color(0xFF929292),
                                    size: 24,
                                  ),
                                ),
                              ),

                              // Dark overlay if selected
                              if (isSelected)
                                Container(
                                  color: Colors.black.withOpacity(0.2),
                                ),

                              // Круг в правом верхнем углу
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black.withOpacity(0.35),
                                    border: isSelected
                                        ? null
                                        : Border.all(
                                            color: Colors.white.withOpacity(0.85),
                                            width: 1.6,
                                          ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Text(
                                            '${selectedIdx + 1}',
                                            style: const TextStyle(
                                              fontFamily: AppTheme.fontText,
                                              color: Color(0xFF090909),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Поле ввода подписи и круглая кнопка отправки
          // Появляется после выбора хотя бы одного фото
          if (_selectedFiles.isNotEmpty)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                keyboardHeight > 0 ? keyboardHeight + 8 : 14,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF191919),
                border: Border(
                  top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Поле ввода подписи (не обязательно)
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090909),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0x1AFFFFFF),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: _captionController,
                        contextMenuBuilder: TelegramTextSelectionToolbar.buildToolbar,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontText,
                          color: Colors.white,
                          fontSize: 14.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Добавить подпись...',
                          hintStyle: TextStyle(
                            fontFamily: AppTheme.fontText,
                            color: Color(0xFF929292),
                            fontSize: 14.5,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Круглая кнопка отправки фото отдельно от поля ввода
                  GestureDetector(
                    onTap: _isSending ? null : _handleSend,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _isSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Color(0xFF090909),
                                ),
                              )
                            : const Icon(
                                Icons.arrow_upward_rounded,
                                color: Color(0xFF090909),
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

