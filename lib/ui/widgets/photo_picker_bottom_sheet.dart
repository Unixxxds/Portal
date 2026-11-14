import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../services/gallery_service.dart';
import '../theme.dart';
import 'telegram_text_selection_toolbar.dart';

class PhotoPickerBottomSheet extends StatefulWidget {
  final Function(List<File> files, String caption) onSend;
  final VoidCallback? onOpenGifts;
  final VoidCallback? onClose;
  final ValueChanged<double>? onProgressChanged;
  final double btnLeft;
  final double? btnBottom;
  final double btnSize;
  final double btnRadius;

  const PhotoPickerBottomSheet({
    super.key,
    required this.onSend,
    this.onOpenGifts,
    this.onClose,
    this.onProgressChanged,
    this.btnLeft = 10.0,
    this.btnBottom,
    this.btnSize = 40.0,
    this.btnRadius = 20.0,
  });

  /// Открывает меню выбора фото с анимацией «True Circle Morph» (1:1 как в референсе)
  static Future<void> show(
    BuildContext context, {
    required Function(List<File> files, String caption) onSend,
    VoidCallback? onOpenGifts,
    ValueChanged<double>? onProgressChanged,
    double btnLeft = 10.0,
    double? btnBottom,
    double btnSize = 40.0,
    double btnRadius = 20.0,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, anim1, anim2) => PhotoPickerBottomSheet(
          onSend: onSend,
          onOpenGifts: onOpenGifts,
          onProgressChanged: onProgressChanged,
          btnLeft: btnLeft,
          btnBottom: btnBottom,
          btnSize: btnSize,
          btnRadius: btnRadius,
        ),
      ),
    );
  }

  @override
  State<PhotoPickerBottomSheet> createState() => PhotoPickerBottomSheetState();
}

class PhotoPickerBottomSheetState extends State<PhotoPickerBottomSheet>
    with SingleTickerProviderStateMixin {
  // Параметры пружины (Spring physics 1:1 из HTML: stiffness 360, damping 32)
  static const double springStiffness = 360.0;
  static const double springDamping = 32.0;

  /*
    progress:
    0.0 -> Круг 44x44px строго на месте кнопки со скрепкой
    1.0 -> Half-Expanded (меню выросло из круга на 61% высоты экрана)
    2.0 -> Full-Screen (меню растянуто до 93.5% высоты экрана)
  */
  double _progress = 0.0;
  double _targetProgress = 0.0;
  double _velocity = 0.0;

  late final Ticker _ticker;
  Duration _lastTickTime = Duration.zero;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _captionController = TextEditingController();

  final List<GalleryMediaItem> _galleryItems = [];
  final List<GalleryMediaItem> _selectedItems = [];

  bool _isSending = false;
  double _dragLastY = 0.0;
  DateTime _dragLastTime = DateTime.now();
  double _dragVelocityPx = 0.0;

  String _currentMonthYear = '';

  @override
  void initState() {
    super.initState();
    try {
      _currentMonthYear = DateFormat('LLLL yyyy', 'ru').format(DateTime.now());
      if (_currentMonthYear.isNotEmpty) {
        _currentMonthYear = _currentMonthYear[0].toUpperCase() + _currentMonthYear.substring(1);
      }
    } catch (_) {
      _currentMonthYear = 'Медиа';
    }

    // Предзагруженные данные из GalleryService (0 мс задержки)
    final cached = GalleryService.instance.items;
    if (cached.isNotEmpty) {
      _galleryItems.addAll(cached);
    }
    GalleryService.instance.addListener(_onGalleryUpdated);
    GalleryService.instance.refresh();

    // Создаем Ticker для физики пружины
    _ticker = createTicker(_onTick);

    // Запускаем анимацию открытия сразу после монтирования
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateTo(1.0, initialVelocity: 2.4);
    });
  }

  void _onGalleryUpdated() {
    if (!mounted) return;
    setState(() {
      final updated = GalleryService.instance.items;
      if (updated.isNotEmpty) {
        _galleryItems.clear();
        _galleryItems.addAll(updated);
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    _captionController.dispose();
    GalleryService.instance.removeListener(_onGalleryUpdated);
    super.dispose();
  }

  // =========================================================================
  // ПРУЖИННАЯ АНИМАЦИЯ (ИСТИННАЯ СИМУЛЯЦИЯ 1:1 ИЗ РЕФЕРЕНСА)
  // =========================================================================
  void _animateTo(double newTarget, {double initialVelocity = 0.0}) {
    _targetProgress = newTarget.clamp(0.0, 2.0);
    _velocity = initialVelocity;
    _lastTickTime = Duration.zero;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTickTime == Duration.zero) {
      _lastTickTime = elapsed;
      return;
    }

    final double dt = math.min((elapsed - _lastTickTime).inMicroseconds / 1000000.0, 0.032);
    _lastTickTime = elapsed;

    final double displacement = _progress - _targetProgress;
    final double springForce = -springStiffness * displacement;
    final double dampingForce = -springDamping * _velocity;
    final double acceleration = springForce + dampingForce;

    _velocity += acceleration * dt;
    _progress += _velocity * dt;

    if (_targetProgress == 0.0 && _progress < 0.0) {
      _progress = 0.0;
      _velocity = 0.0;
    }

    widget.onProgressChanged?.call(_progress);

    if (displacement.abs() < 0.0012 && _velocity.abs() < 0.008) {
      _progress = _targetProgress;
      _velocity = 0.0;
      _ticker.stop();
      if (_progress == 0.0) {
        widget.onProgressChanged?.call(0.0);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _closeSheet() {
    _animateTo(0.0, initialVelocity: -1.6);
  }

  // =========================================================================
  // ВЫБОР ФОТО
  // =========================================================================
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

  Future<void> _pickFromGallery() async {
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
      }
    } catch (_) {}
  }

  Future<void> _pickFromComputer() async {
    if (!Platform.isWindows) {
      await _pickFromGallery();
      return;
    }
    try {
      const script = r"""
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Выберите файлы'
$dialog.Filter = 'Все файлы (*.*)|*.*'
$dialog.Multiselect = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Output ($dialog.FileNames -join '|')
}
""";
      final result = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      final raw = result.stdout.toString().trim();
      if (raw.isNotEmpty && mounted) {
        final paths = raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty && File(s).existsSync()).toList();
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
    } catch (_) {}
  }

  // =========================================================================
  // РАСЧЕТ МОРФИНГА (ФОРМУЛЫ 1:1 ИЗ РЕФЕРЕНСА)
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double vw = media.size.width;
    final double vh = media.size.height;
    final double bottomInset = media.padding.bottom;

    final double halfHeight = vh * 0.61;
    final double fullHeight = vh * 0.935;

    final double p = _progress;

    final double btnLeft = widget.btnLeft;
    final double btnBottom = widget.btnBottom ?? (bottomInset > 0 ? bottomInset : 10.0);
    final double btnSize = widget.btnSize;
    final double btnRadius = widget.btnRadius;

    // 1. Scrim (затемнение заднего фона)
    final double scrimOpacity = p <= 1.0
        ? (p * 0.35).clamp(0.0, 0.35)
        : (0.35 + (p - 1.0) * 0.30).clamp(0.35, 0.65);

    // 2. Вычисление размеров и положения морфирующейся шторки и дока
    double curLeft, curBottom, curWidth, curHeight, topRadius, bottomRadius;
    double innerScale, innerOpacity;
    double dockLeft, dockBottom, dockWidth, dockHeight, dockRadius;
    double dockItemsOpacity, dockItemsScale;

    if (p <= 1.0) {
      final double cp = p.clamp(0.0, 1.0);

      final double easeWidth = math.pow(cp, 0.78).toDouble();
      final double easeHeight = math.pow(cp, 0.72).toDouble();
      final double easePos = math.pow(cp, 0.85).toDouble();

      curLeft = ui.lerpDouble(btnLeft, 0.0, easePos)!;
      curBottom = ui.lerpDouble(btnBottom, 0.0, easePos)!;
      curWidth = ui.lerpDouble(btnSize, vw, easeWidth)!;
      curHeight = ui.lerpDouble(btnSize, halfHeight, easeHeight)!;

      final double midCapsuleBump = math.sin(cp * math.pi) * 48.0;
      topRadius = ui.lerpDouble(btnRadius, 36.0, cp)! + midCapsuleBump;
      bottomRadius = ui.lerpDouble(btnRadius, 0.0, math.pow(cp, 1.4).toDouble())! + midCapsuleBump * (1.0 - cp);

      innerScale = ui.lerpDouble(0.32, 1.0, easeWidth)!;
      innerOpacity = ((cp - 0.04) * 2.2).clamp(0.0, 1.0);

      // Нижний док вырастает из того же круга кнопки
      final double dockEase = math.pow(cp, 0.76).toDouble();
      dockLeft = ui.lerpDouble(btnLeft, 12.0, dockEase)!;
      dockBottom = ui.lerpDouble(btnBottom, 16.0 + bottomInset, dockEase)!;
      dockWidth = ui.lerpDouble(btnSize, vw - 24.0, dockEase)!;
      dockHeight = ui.lerpDouble(btnSize, 64.0, dockEase)!;
      dockRadius = ui.lerpDouble(btnRadius, 32.0, dockEase)!;

      dockItemsOpacity = ((cp - 0.18) / 0.65).clamp(0.0, 1.0);
      dockItemsScale = ui.lerpDouble(0.60, 1.0, dockEase)!;
    } else {
      final double expandT = (p - 1.0).clamp(0.0, 1.0);
      curLeft = 0.0;
      curBottom = 0.0;
      curWidth = vw;
      curHeight = ui.lerpDouble(halfHeight, fullHeight, expandT)!;
      topRadius = ui.lerpDouble(36.0, 26.0, expandT)!;
      bottomRadius = 0.0;

      innerScale = 1.0;
      innerOpacity = 1.0;

      dockLeft = 12.0;
      dockBottom = 16.0 + bottomInset;
      dockWidth = vw - 24.0;
      dockHeight = 64.0;
      dockRadius = 32.0;

      dockItemsOpacity = 1.0;
      dockItemsScale = 1.0;
    }

    final double sheetAlpha = (p * 12.0).clamp(0.0, 1.0);
    final bool showDateBadge = p > 1.35 || (_scrollController.hasClients && _scrollController.offset > 10);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeSheet();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 1. Scrim затемнение
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSheet,
                child: Container(
                  color: Colors.black.withOpacity(scrimOpacity),
                ),
              ),
            ),

            // 2. Главная шторка (морф из круга кнопки)
            if (sheetAlpha > 0.01)
              Positioned(
                left: curLeft,
              bottom: curBottom,
              width: curWidth,
              height: curHeight,
              child: Opacity(
                opacity: sheetAlpha,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(topRadius),
                      topRight: Radius.circular(topRadius),
                      bottomLeft: Radius.circular(bottomRadius),
                      bottomRight: Radius.circular(bottomRadius),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x52000000),
                        blurRadius: 42,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GestureDetector(
                    onVerticalDragStart: (details) {
                      _dragLastY = details.globalPosition.dy;
                      _dragLastTime = DateTime.now();
                      _dragVelocityPx = 0.0;
                      if (_ticker.isActive) _ticker.stop();
                    },
                    onVerticalDragUpdate: (details) {
                      final now = DateTime.now();
                      final double dt = math.max((now.difference(_dragLastTime).inMicroseconds / 1000000.0), 0.001);
                      final double dy = details.globalPosition.dy - _dragLastY;
                      _dragLastY = details.globalPosition.dy;
                      _dragLastTime = now;
                      _dragVelocityPx = dy / dt;

                      final bool canDragSheet = (_progress < 1.98) ||
                          (!_scrollController.hasClients || (_scrollController.offset <= 0 && dy > 0));

                      if (canDragSheet) {
                        if (_scrollController.hasClients && _scrollController.offset > 0) {
                          _scrollController.jumpTo(0);
                        }
                        if (_progress >= 1.0) {
                          final double expandRange = vh * 0.325;
                          _progress = (_progress - dy / expandRange).clamp(0.0, 2.0);
                        } else {
                          final double morphRange = vh * 0.55;
                          _progress = (_progress - dy / morphRange).clamp(0.0, 2.0);
                        }
                        widget.onProgressChanged?.call(_progress);
                        setState(() {});
                      }
                    },
                    onVerticalDragEnd: (details) {
                      final double normVel = -_dragVelocityPx / 700.0;

                      if (_progress < 0.75 || (_progress < 1.15 && _dragVelocityPx > 400)) {
                        _animateTo(0.0, initialVelocity: normVel);
                      } else if (_progress > 1.35 || _dragVelocityPx < -350) {
                        _animateTo(2.0, initialVelocity: normVel);
                      } else {
                        _animateTo(1.0, initialVelocity: normVel);
                      }
                    },
                    child: Stack(
                      children: [
                        // Внутренний контейнер фиксированной ширины вьюпорта (чтобы сетка не сжималась)
                        Positioned(
                          left: 0,
                          top: 0,
                          width: vw,
                          height: fullHeight,
                          child: Transform(
                            transform: Matrix4.identity()..scale(innerScale, innerScale),
                            alignment: Alignment.bottomLeft,
                            child: Opacity(
                              opacity: innerOpacity,
                              child: Stack(
                                children: [
                                  // Сетка медиа
                                  NotificationListener<ScrollNotification>(
                                    onNotification: (scrollInfo) {
                                      setState(() {});
                                      return false;
                                    },
                                    child: SingleChildScrollView(
                                      controller: _scrollController,
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.only(top: 60, bottom: 120),
                                      child: _buildMediaGrid(vw),
                                    ),
                                  ),

                                  // Верхняя градиентная вуаль
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: 82,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xAD000000),
                                              Color(0x40000000),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Шапка Liquid Glass (Кнопка закрытия, Альбом, Дата)
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    right: 14,
                                    height: 42,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Кнопка закрытия (слева)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: GestureDetector(
                                            onTap: _closeSheet,
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: const Color(0x9426262A),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: const Color(0x38FFFFFF),
                                                  width: 0.5,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x59000000),
                                                    blurRadius: 20,
                                                    offset: Offset(0, 6),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(20),
                                                child: BackdropFilter(
                                                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Выбор альбома (по центру)
                                        GestureDetector(
                                          onTap: _pickFromGallery,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Недавние',
                                                  style: TextStyle(
                                                    fontFamily: AppTheme.fontDisplay,
                                                    fontSize: 16.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                    letterSpacing: -0.2,
                                                    shadows: [
                                                      Shadow(
                                                        color: Colors.black87,
                                                        blurRadius: 8,
                                                        offset: Offset(0, 1),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(width: 4),
                                                Icon(
                                                  Icons.keyboard_arrow_down_rounded,
                                                  color: Color(0xBFFFFFFF),
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Бейдж даты (справа, появляется при прокрутке/раскрытии)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 220),
                                            opacity: showDateBadge ? 1.0 : 0.0,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                              decoration: BoxDecoration(
                                                color: const Color(0x9426262A),
                                                borderRadius: BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: const Color(0x38FFFFFF),
                                                  width: 0.5,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x59000000),
                                                    blurRadius: 20,
                                                    offset: Offset(0, 6),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(999),
                                                child: BackdropFilter(
                                                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                                  child: Text(
                                                    _currentMonthYear,
                                                    style: const TextStyle(
                                                      fontFamily: AppTheme.fontDisplay,
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                      letterSpacing: -0.15,
                                                    ),
                                                  ),
                                                ),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. Плавающий бар подписи (появляется при выборе хотя бы 1 фото)
          if (_selectedItems.isNotEmpty && p > 0.5)
            Positioned(
              left: 12,
              right: 12,
              bottom: 88 + bottomInset,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: (p > 0.8) ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A1A1E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x2EFFFFFF), width: 0.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 4)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Row(
                        children: [
                          Expanded(
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
                                  color: Color(0xFF8E8E93),
                                  fontSize: 14.5,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _isSending ? null : _handleSend,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2AABEE),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: _isSending
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 5. Нижний парящий док (вырастает из того же круга кнопки со скрепкой)
          if (sheetAlpha > 0.01)
            Positioned(
              left: dockLeft,
              bottom: dockBottom,
              width: dockWidth,
              height: dockHeight,
              child: Opacity(
                opacity: sheetAlpha,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xA61C1C20),
                    borderRadius: BorderRadius.circular(dockRadius),
                    border: Border.all(color: const Color(0x38FFFFFF), width: 0.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x80000000),
                        blurRadius: 32,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(dockRadius),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Opacity(
                        opacity: dockItemsOpacity,
                        child: Transform.scale(
                          scale: dockItemsScale,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // 1. Галерея (активная)
                              _buildDockItem(
                                isSelected: true,
                                label: 'Галерея',
                                customIcon: Container(
                                  width: 23,
                                  height: 23,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF38B6FF), Color(0xFF1D6FA3)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(color: const Color(0xFF40A7E3), width: 1.5),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.photo_rounded, color: Colors.white, size: 14),
                                  ),
                                ),
                                onTap: _selectedItems.isNotEmpty ? _handleSend : _pickFromGallery,
                              ),

                              // 2. Подарок
                              _buildDockItem(
                                label: 'Подарок',
                                icon: Icons.card_giftcard_rounded,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onOpenGifts?.call();
                                },
                              ),

                              // 3. Файл
                              _buildDockItem(
                                label: 'Файл',
                                icon: Icons.insert_drive_file_rounded,
                                onTap: _pickFromComputer,
                              ),

                              // 4. Геолокация
                              _buildDockItem(
                                label: 'Геолокация',
                                icon: Icons.location_on_rounded,
                                onTap: () {},
                              ),

                              // 5. Ответ
                              _buildDockItem(
                                label: 'Ответ',
                                icon: Icons.reply_rounded,
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  // =========================================================================
  // СЕТКА ФОТО (ASPECT RATIO 1 / 1.18, GAP 1.5px, СТЕКЛО И БЕЙДЖИ)
  // =========================================================================
  Widget _buildMediaGrid(double screenWidth) {
    if (_galleryItems.isEmpty) {
      return Container(
        height: 260,
        alignment: Alignment.center,
        child: const Text(
          'Нет доступных фотографий',
          style: TextStyle(fontFamily: AppTheme.fontText, color: Colors.white54, fontSize: 14),
        ),
      );
    }

    final double itemWidth = (screenWidth - 3.0) / 3.0;
    final double itemHeight = itemWidth * 1.18;

    return Wrap(
      spacing: 1.5,
      runSpacing: 1.5,
      children: List.generate(_galleryItems.length, (index) {
        final item = _galleryItems[index];
        final selectedOrderIndex = _selectedItems.indexWhere((i) => i.id == item.id);
        final bool isSelected = selectedOrderIndex != -1;

        return SizedBox(
          width: itemWidth,
          height: itemHeight,
          child: GestureDetector(
            onTap: () => _toggleSelection(item),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Картинка: при выборе сжимается до scale 0.92 и получает borderRadius 10 (1:1 как в HTML)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.all(isSelected ? 4.0 : 0.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141416),
                    borderRadius: BorderRadius.circular(isSelected ? 10.0 : 0.0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildThumbnailWidget(item),
                ),

                // Затемнение при выборе
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                // Кружок выбора (23x23px, #2AABEE при выборе, blur 4px при невыбранном)
                Positioned(
                  top: 7,
                  right: 7,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? const Color(0xFF2AABEE) : const Color(0x3D000000),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.92),
                        width: 1.6,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: isSelected
                          ? Center(
                              child: Text(
                                '${selectedOrderIndex + 1}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                              child: const SizedBox.expand(),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildThumbnailWidget(GalleryMediaItem item) {
    if (item.asset != null) {
      return _AssetThumbnailWidget(asset: item.asset!);
    }
    if (item.file != null) {
      return Image.file(
        item.file!,
        fit: BoxFit.cover,
        cacheWidth: 350,
        errorBuilder: (ctx, _, __) => Container(
          color: const Color(0xFF141416),
          child: const Icon(Icons.broken_image_rounded, color: Colors.white30, size: 24),
        ),
      );
    }
    return Container(color: const Color(0xFF141416));
  }

  Widget _buildDockItem({
    required String label,
    IconData? icon,
    Widget? customIcon,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: isSelected ? Colors.white.withOpacity(0.08) : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            customIcon ??
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? const Color(0xFF40A7E3) : const Color(0xD9FFFFFF),
                ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: isSelected ? const Color(0xFF40A7E3) : const Color(0xD9FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нативный thumbnail из памяти
class _AssetThumbnailWidget extends StatefulWidget {
  final AssetEntity asset;
  const _AssetThumbnailWidget({required this.asset});

  @override
  State<_AssetThumbnailWidget> createState() => _AssetThumbnailWidgetState();
}

class _AssetThumbnailWidgetState extends State<_AssetThumbnailWidget> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _cache[widget.asset.id];
    if (_bytes == null) {
      widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(280)).then((data) {
        if (data != null && mounted) {
          _cache[widget.asset.id] = data;
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
    return Container(color: const Color(0xFF141416));
  }
}
