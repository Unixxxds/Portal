import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../services/gallery_service.dart';
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

  /// Открывает меню выбора фото с анимацией в стиле Telegram (плавный подъем снизу с пружинным замедлением)
  static Future<void> show(
    BuildContext context, {
    required Function(List<File> files, String caption) onSend,
    VoidCallback? onOpenGifts,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.55),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (ctx, anim1, anim2) => PhotoPickerBottomSheet(
          onSend: onSend,
          onOpenGifts: onOpenGifts,
        ),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.40),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
                ),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<PhotoPickerBottomSheet> createState() => _PhotoPickerBottomSheetState();
}

class _PhotoPickerBottomSheetState extends State<PhotoPickerBottomSheet> {
  final List<GalleryMediaItem> _galleryItems = [];
  final List<GalleryMediaItem> _selectedItems = [];
  final TextEditingController _captionController = TextEditingController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _permissionDenied = false;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    // 1. Моментальная инициализация из предзагруженного кэша (0 мс задержки)
    final cached = GalleryService.instance.items;
    if (cached.isNotEmpty) {
      _galleryItems.addAll(cached);
      _isLoading = false;
    } else {
      _isLoading = GalleryService.instance.isLoading;
    }
    _permissionDenied = GalleryService.instance.permissionDenied;

    GalleryService.instance.addListener(_onGalleryServiceUpdated);
    // 2. Фоновое обновление на случай новых снимков
    GalleryService.instance.refresh();
  }

  void _onGalleryServiceUpdated() {
    if (!mounted) return;
    setState(() {
      final updated = GalleryService.instance.items;
      _permissionDenied = GalleryService.instance.permissionDenied;
      if (updated.isNotEmpty) {
        _galleryItems.clear();
        _galleryItems.addAll(updated);
        _isLoading = false;
      } else {
        _isLoading = GalleryService.instance.isLoading;
      }
    });
  }

  @override
  void dispose() {
    GalleryService.instance.removeListener(_onGalleryServiceUpdated);
    _captionController.dispose();
    super.dispose();
  }

  void _toggleSelection(GalleryMediaItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      final idx = _selectedItems.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _selectedItems.removeAt(idx);
      } else {
        if (_selectedItems.length >= 5) {
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
        _selectedItems.add(item);
      }
    });
  }

  Future<void> _handlePickFromGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> picked = await picker.pickMultiImage(limit: 5);
      if (picked.isNotEmpty && mounted) {
        final List<File> files = [];
        for (final x in picked) {
          final f = File(x.path);
          if (f.existsSync()) files.add(f);
        }
        GalleryService.instance.addManualFiles(files);
        setState(() {
          for (final f in files) {
            final found = _galleryItems.where((i) => i.file?.path == f.path).firstOrNull;
            if (found != null && !_selectedItems.any((i) => i.id == found.id)) {
              if (_selectedItems.length < 5) _selectedItems.add(found);
            }
          }
        });
        return;
      }
    } catch (e) {
      debugPrint('Error picking from gallery: $e');
    }

    if (Platform.isWindows) {
      await _pickFromComputerDialog();
    }
  }

  Future<void> _handlePickFromCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null && mounted) {
        final file = File(photo.path);
        if (file.existsSync()) {
          GalleryService.instance.addManualFiles([file]);
          setState(() {
            final found = _galleryItems.where((i) => i.file?.path == file.path).firstOrNull;
            if (found != null && !_selectedItems.any((i) => i.id == found.id)) {
              if (_selectedItems.length < 5) _selectedItems.add(found);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking from camera: $e');
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
      if (raw.isNotEmpty && mounted) {
        final paths = raw
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && File(s).existsSync())
            .toList();

        final List<File> files = paths.map((p) => File(p)).toList();
        GalleryService.instance.addManualFiles(files);
        setState(() {
          for (final f in files) {
            final found = _galleryItems.where((i) => i.file?.path == f.path).firstOrNull;
            if (found != null && !_selectedItems.any((i) => i.id == found.id)) {
              if (_selectedItems.length < 5) _selectedItems.add(found);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking from PC dialog: $e');
    }
  }

  Future<void> _handleSend() async {
    if (_selectedItems.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    try {
      final List<File> filesToSend = [];
      for (final item in _selectedItems) {
        final f = await item.getFile();
        if (f != null && f.existsSync()) {
          filesToSend.add(f);
        }
      }

      if (filesToSend.isNotEmpty) {
        await widget.onSend(filesToSend, _captionController.text.trim());
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.56;
    final keyboardHeight = mediaQuery.viewInsets.bottom;

    return Stack(
      children: [
        // Затемняющий фон при нажатии закрывает меню
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox.expand(),
          ),
        ),

        // Выезжающая снизу панель в стиле Telegram
        Align(
          alignment: Alignment.bottomCenter,
          child: Transform.translate(
            offset: Offset(0, _dragOffsetY > 0 ? _dragOffsetY : 0),
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! > 0) {
                  setState(() {
                    _dragOffsetY += details.primaryDelta!;
                  });
                }
              },
              onVerticalDragEnd: (details) {
                if (_dragOffsetY > 80 || (details.primaryVelocity ?? 0) > 400) {
                  Navigator.of(context).pop();
                } else {
                  setState(() {
                    _dragOffsetY = 0.0;
                  });
                }
              },
              child: Container(
                height: sheetHeight + keyboardHeight,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF18181A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(
                    top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 24,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Верхняя полоска перетаскивания (Drag Handle)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 8),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Строка действий в стиле Telegram (Галерея, Файл, Подарок, Камера)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionPill(
                            icon: Icons.photo_library_rounded,
                            label: 'Галерея',
                            gradientColors: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                            onTap: _handlePickFromGallery,
                          ),
                          _buildActionPill(
                            icon: Icons.insert_drive_file_rounded,
                            label: 'Файл',
                            gradientColors: const [Color(0xFF0072FF), Color(0xFF00C6FF)],
                            onTap: Platform.isWindows ? _pickFromComputerDialog : _handlePickFromGallery,
                          ),
                          if (widget.onOpenGifts != null)
                            _buildActionPill(
                              icon: Icons.card_giftcard_rounded,
                              label: 'Подарок',
                              gradientColors: const [Color(0xFFFF0844), Color(0xFFFFB199)],
                              onTap: widget.onOpenGifts!,
                            ),
                          _buildActionPill(
                            icon: Icons.camera_alt_rounded,
                            label: 'Камера',
                            gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                            onTap: _handlePickFromCamera,
                          ),
                        ],
                      ),
                    ),

                    // Разделитель / Заголовок списка фото
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            _selectedItems.isEmpty
                                ? 'Недавние'
                                : 'Выбрано: ${_selectedItems.length} из 5',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedItems.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                setState(() => _selectedItems.clear());
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text(
                                  'Сбросить',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Сетка фото (быстрое отображение из памяти)
                    Expanded(
                      child: _isLoading && _galleryItems.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : (_permissionDenied && _galleryItems.isEmpty)
                              ? _buildPermissionDeniedView()
                              : GridView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 4,
                                    mainAxisSpacing: 4,
                                    childAspectRatio: 1.0,
                                  ),
                                  itemCount: _galleryItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _galleryItems[index];
                                    final selectedIdx = _selectedItems.indexWhere((i) => i.id == item.id);
                                    final isSelected = selectedIdx != -1;

                                    return GestureDetector(
                                      onTap: () => _toggleSelection(item),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // Картинка (через быстрый нативный кэш)
                                            _buildMediaThumbnail(item),

                                            // Затемнение при выборе
                                            if (isSelected)
                                              Container(
                                                color: Colors.black.withOpacity(0.25),
                                              ),

                                            // Круг выбора в правом верхнем углу (как в Telegram)
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 180),
                                                curve: Curves.easeOutBack,
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
                                                          color: Colors.white.withOpacity(0.9),
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

                    // Поле ввода подписи и кнопка отправки при выборе фото
                    if (_selectedItems.isNotEmpty)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          keyboardHeight > 0 ? keyboardHeight + 8 : (mediaQuery.padding.bottom > 0 ? mediaQuery.padding.bottom + 4 : 14),
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF18181A),
                          border: Border(
                            top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Поле ввода подписи
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                  maxHeight: 110,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF090909),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color(0x1AFFFFFF),
                                    width: 1,
                                  ),
                                ),
                                child: TextField(
                                  controller: _captionController,
                                  contextMenuBuilder: TelegramTextSelectionToolbar.buildToolbar,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization: TextCapitalization.sentences,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.newline,
                                  scrollPhysics: const BouncingScrollPhysics(),
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontText,
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    height: 1.35,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Добавить подпись...',
                                    hintStyle: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      color: Color(0xFF929292),
                                      fontSize: 14.5,
                                      height: 1.35,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 11),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            // Круглая кнопка отправки с бейджем количества
                            GestureDetector(
                              onTap: _isSending ? null : _handleSend,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: _isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.first.withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: Colors.white, size: 23),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaThumbnail(GalleryMediaItem item) {
    if (item.asset != null) {
      return _AssetThumbnailWidget(asset: item.asset!);
    }
    if (item.file != null) {
      return Image.file(
        item.file!,
        fit: BoxFit.cover,
        cacheWidth: 350,
        errorBuilder: (ctx, _, __) => Container(
          color: const Color(0xFF222222),
          child: const Icon(Icons.broken_image_rounded, color: Color(0xFF929292), size: 24),
        ),
      );
    }
    return Container(color: const Color(0xFF222222));
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 48, color: Colors.white.withOpacity(0.4)),
          const SizedBox(height: 12),
          const Text(
            'Нет доступа к галерее',
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Разрешите доступ к фото в настройках',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => PhotoManager.openSetting(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }
}

/// Виджет для мгновенного отображения нативного thumbnail из MediaStore/PHImageManager
class _AssetThumbnailWidget extends StatefulWidget {
  final AssetEntity asset;
  const _AssetThumbnailWidget({required this.asset});

  @override
  State<_AssetThumbnailWidget> createState() => _AssetThumbnailWidgetState();
}

class _AssetThumbnailWidgetState extends State<_AssetThumbnailWidget> {
  static final Map<String, Uint8List> _thumbCache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _thumbCache[widget.asset.id];
    if (_bytes == null) {
      widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(280)).then((data) {
        if (data != null && mounted) {
          _thumbCache[widget.asset.id] = data;
          setState(() {
            _bytes = data;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(color: const Color(0xFF222222));
  }
}
