import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../core/constants.dart';
import '../../models/user_gift.dart';
import '../../services/api_service.dart';
import '../../data/database_helper.dart';
import '../theme.dart';
import 'gift_visuals.dart';
import 'badges.dart';

class GiftDetailModal extends StatefulWidget {
  final UserGift gift;
  final VoidCallback? onSenderTap;
  final VoidCallback? onOwnerTap;
  final ValueChanged<UserGift>? onGiftUpgraded;
  final String? ownerName;
  final String? ownerAvatar;

  const GiftDetailModal({
    super.key,
    required this.gift,
    this.onSenderTap,
    this.onOwnerTap,
    this.onGiftUpgraded,
    this.ownerName,
    this.ownerAvatar,
  });

  static Future<void> show(
    BuildContext context, {
    required UserGift gift,
    VoidCallback? onSenderTap,
    VoidCallback? onOwnerTap,
    ValueChanged<UserGift>? onGiftUpgraded,
    String? ownerName,
    String? ownerAvatar,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GiftDetailModal(
        gift: gift,
        onSenderTap: onSenderTap,
        onOwnerTap: onOwnerTap,
        onGiftUpgraded: onGiftUpgraded,
        ownerName: ownerName,
        ownerAvatar: ownerAvatar,
      ),
    );
  }

  @override
  State<GiftDetailModal> createState() => _GiftDetailModalState();
}

class _GiftDetailModalState extends State<GiftDetailModal> with TickerProviderStateMixin {
  late UserGift _currentGift;
  bool _isSpinning = false;
  bool _isFinished = false;

  String get _ownerDisplayName {
    if (widget.ownerName != null && widget.ownerName!.trim().isNotEmpty) {
      return widget.ownerName!.trim();
    }
    if (_currentGift.ownerDisplayName.isNotEmpty && _currentGift.ownerDisplayName != 'Пользователь') {
      return _currentGift.ownerDisplayName;
    }
    return _currentGift.ownerDisplayName;
  }

  String get _ownerAvatar {
    final raw = (widget.ownerAvatar != null && widget.ownerAvatar!.trim().isNotEmpty)
        ? widget.ownerAvatar!.trim()
        : _currentGift.ownerAvatar.trim();
    return AppConstants.formatMediaUrl(raw);
  }

  late AnimationController _spinController;
  late AnimationController _confettiController;

  // Roulette steps
  List<GiftModelOption> _modelSteps = [];
  List<BackdropOption> _bgSteps = [];
  GiftModelOption? _wonModel;
  BackdropOption? _wonBackdrop;

  // Confetti particles
  final List<_ConfettiParticle> _confettiParticles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _currentGift = widget.gift;

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5850),
    )..addListener(() {
        if (mounted) setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _onSpinCompleted();
        }
      });

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addListener(() {
        for (final p in _confettiParticles) {
          p.update();
        }
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _spinController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // Smooth slot-machine deceleration curve matching the reference (1 - (1 - t)^power)
  double _easeOutSlot(double t, double power) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    return 1.0 - math.pow(1.0 - t, power);
  }

  void _startUpgrade() {
    if (_isSpinning || _currentGift.isUpgraded) return;

    final availableModels = GiftVisuals.getModelsForGift(_currentGift);
    if (availableModels.isEmpty) return;

    // 1. Pick winner model and winner backdrop
    final wonModel = availableModels[_random.nextInt(availableModels.length)];
    final allBackdrops = GiftVisuals.allBackdropOptions;
    final wonBackdrop = allBackdrops[_random.nextInt(allBackdrops.length)];

    _wonModel = wonModel;
    _wonBackdrop = wonBackdrop;

    // 2. Build model steps (20 steps total, ending with wonModel)
    _modelSteps = [];
    // Start with current
    _modelSteps.add(GiftModelOption(
      name: _currentGift.giftName,
      file: _currentGift.modelFile,
      rarity: '12.0%',
    ));
    for (int i = 0; i < 18; i++) {
      _modelSteps.add(availableModels[_random.nextInt(availableModels.length)]);
    }
    _modelSteps.add(wonModel); // Final winner

    // 3. Build backdrop steps (10 steps total, ending with wonBackdrop)
    _bgSteps = [];
    _bgSteps.add(BackdropOption(
      name: _currentGift.backdropName.isNotEmpty ? _currentGift.backdropName : 'Midnight Blue',
      rarity: '3.0%',
      colors: const [Color(0xFF5B6884), Color(0xFF414D65)],
      gradient: 'radial-gradient(circle, #5b6884 0%, #414d65 100%)',
    ));
    for (int i = 0; i < 8; i++) {
      _bgSteps.add(allBackdrops[_random.nextInt(allBackdrops.length)]);
    }
    _bgSteps.add(wonBackdrop); // Final winner

    // 4. Send API upgrade request in background
    ApiService.instance.upgradeGift(
      giftRecordId: _currentGift.id,
      preselected: {
        'model': {
          'name': wonModel.name,
          'file': wonModel.file,
          'rarity': wonModel.rarity,
        },
        'backdrop': {
          'name': wonBackdrop.name,
          'gradient': wonBackdrop.gradient,
          'rarity': wonBackdrop.rarity,
        },
      },
    );

    // 5. Start animation
    setState(() {
      _isSpinning = true;
      _isFinished = false;
    });

    _spinController.forward(from: 0.0);
  }

  void _onSpinCompleted() {
    if (!mounted || _wonModel == null || _wonBackdrop == null) return;

    final updated = _currentGift.copyWith(
      isUpgraded: true,
      modelName: _wonModel!.name,
      modelFile: _wonModel!.file,
      backdropName: _wonBackdrop!.name,
      backdropGradient: _wonBackdrop!.gradient,
      patternName: '',
      patternSvg: '',
      nftNumber: _currentGift.nftNumber > 0 ? _currentGift.nftNumber : _currentGift.id,
    );

    setState(() {
      _currentGift = updated;
      _isSpinning = false;
      _isFinished = true;
    });

    // Save to local database
    DatabaseHelper.instance.updateUserGift(updated);

    // Notify parent listener (chat, profile)
    widget.onGiftUpgraded?.call(updated);

    // Trigger celebratory confetti burst
    _launchConfetti();
  }

  void _launchConfetti() {
    _confettiParticles.clear();
    const colors = [
      Color(0xFFFF3B30),
      Color(0xFFFF9500),
      Color(0xFFFFCC00),
      Color(0xFF34C759),
      Color(0xFF00C7BE),
      Color(0xFF32ADE6),
      Color(0xFF5856D6),
      Color(0xFFAF52DE),
      Color(0xFFFF2D55),
    ];

    for (int i = 0; i < 110; i++) {
      final fromLeft = i % 2 == 0;
      _confettiParticles.add(_ConfettiParticle(
        x: fromLeft ? 15.0 : 365.0,
        y: 190.0 + (_random.nextDouble() - 0.5) * 80.0,
        vx: (fromLeft ? 1.0 : -1.0) * (3.5 + _random.nextDouble() * 9.0),
        vy: -8.0 - _random.nextDouble() * 9.5,
        size: 5.0 + _random.nextDouble() * 6.0,
        color: colors[_random.nextInt(colors.length)],
        rot: _random.nextDouble() * 360.0,
        vRot: (_random.nextDouble() - 0.5) * 15.0,
        isRect: _random.nextDouble() > 0.35,
      ));
    }

    _confettiController.forward(from: 0.0);
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return 'Недавно';
    try {
      var s = dateStr.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}').hasMatch(s)) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(s)) {
        s = '${s}Z';
      }
      final dt = DateTime.parse(s).toLocal();
      const months = [
        'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ];
      final monthName = months[dt.month - 1];
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $monthName в $hour:$minute';
    } catch (_) {
      return dateStr;
    }
  }

  String get _ownerVerification {
    final uname = (_currentGift.recipientUsername.isNotEmpty
            ? _currentGift.recipientUsername
            : _currentGift.senderUsername)
        .toLowerCase()
        .trim();
    if (uname == 'revs') return 'dev';
    if (uname == 'botfather' || uname == 'portal') return 'verified';
    return 'none';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Animation progress calculations
    final elapsedMs = _spinController.value * 5850.0;
    final pBg = _easeOutSlot(elapsedMs / 2550.0, 2.85).clamp(0.0, 1.0);
    final pMod = _easeOutSlot(elapsedMs / 4650.0, 3.35).clamp(0.0, 1.0);

    // Current interpolated backdrop colors
    List<Color> currentBgColors;
    String currentBackdropName;
    String currentBackdropRarity;

    if (_isSpinning && _bgSteps.isNotEmpty) {
      final floatIndex = pBg * (_bgSteps.length - 1);
      final i0 = floatIndex.floor().clamp(0, _bgSteps.length - 1);
      final i1 = (i0 + 1).clamp(0, _bgSteps.length - 1);
      final frac = floatIndex - i0;

      final c1 = Color.lerp(_bgSteps[i0].colors[0], _bgSteps[i1].colors[0], frac)!;
      final c2 = Color.lerp(_bgSteps[i0].colors[1], _bgSteps[i1].colors[1], frac)!;
      currentBgColors = [c1, c2];

      final activeBgStep = _bgSteps[floatIndex.round().clamp(0, _bgSteps.length - 1)];
      currentBackdropName = activeBgStep.name;
      currentBackdropRarity = activeBgStep.rarity;
    } else if (_currentGift.backdropName.isNotEmpty &&
        GiftVisuals.officialBackdropColors.containsKey(_currentGift.backdropName.toLowerCase())) {
      currentBgColors = GiftVisuals.officialBackdropColors[_currentGift.backdropName.toLowerCase()]!;
      currentBackdropName = _currentGift.backdropName;
      currentBackdropRarity = '2.5%';
    } else {
      currentBgColors = const [Color(0xFF2C3240), Color(0xFF0F1117)];
      currentBackdropName = _currentGift.backdropName;
      currentBackdropRarity = '2.5%';
    }

    // Current model details in slot
    String currentModelName;
    String currentModelRarity;
    if (_isSpinning && _modelSteps.isNotEmpty) {
      final floatModIndex = pMod * (_modelSteps.length - 1);
      final activeModStep = _modelSteps[floatModIndex.round().clamp(0, _modelSteps.length - 1)];
      currentModelName = activeModStep.name;
      currentModelRarity = activeModStep.rarity;
    } else {
      currentModelName = _currentGift.modelName.isNotEmpty ? _currentGift.modelName : _currentGift.giftName;
      currentModelRarity = '12.0%';
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0D10),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===================================================================
              // 1. TOP SHOWCASE BANNER (Roulette Carousel + Interpolated Glow)
              // ===================================================================
              Stack(
                alignment: Alignment.center,
                children: [
                  // Dynamic Background Gradient
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    height: 255,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.15),
                        radius: 0.95,
                        colors: currentBgColors,
                      ),
                    ),
                  ),

                  // Ambient Glow Bloom behind current model
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: currentBgColors.first.withOpacity(0.55),
                          blurRadius: 55,
                          spreadRadius: 22,
                        ),
                      ],
                    ),
                  ),

                  // Carousel of models or Static Model
                  if (_isSpinning && _modelSteps.isNotEmpty)
                    _buildRouletteCarousel(screenWidth, pMod)
                  else
                    Center(
                      child: GiftModelWidget(
                        gift: _currentGift,
                        size: 165,
                        animate: true,
                      ),
                    ),

                  // Number Badge (#6) top-left
                  if (_currentGift.nftNumber > 0 || _currentGift.isUpgraded)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '#${_currentGift.nftNumber > 0 ? _currentGift.nftNumber : _currentGift.id}',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                  // Close (X) button top-right (hidden briefly at finale like in video)
                  if (!(_isSpinning && elapsedMs > 4800))
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              // ===================================================================
              // 2. GIFT TITLE & SUBTITLE
              // ===================================================================
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isSpinning ? currentModelName : (_currentGift.modelName.isNotEmpty ? _currentGift.modelName : _currentGift.giftName),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontDisplay,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isSpinning
                            ? 'Улучшение подарка...'
                            : (_currentGift.isUpgraded
                                ? 'Уникальный коллекционный подарок'
                                : 'Обычный подарок'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (_currentGift.isUpgraded || _isFinished)
                              ? const Color(0xFF30D158)
                              : (_isSpinning ? const Color(0xFF3390EC) : const Color(0xFF8E8E93)),
                        ),
                      ),

                      // Optional Comment (before upgrade)
                      if (!_isSpinning && !_isFinished && _currentGift.comment != null && _currentGift.comment!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Text(
                            '«${_currentGift.comment!}»',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                              color: Color(0xFFE4E4E7),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ===========================================================
                      // 3. ATTRIBUTES / DETAILS CARD
                      // ===========================================================
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181F),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF262933), width: 1),
                        ),
                        child: Column(
                          children: [
                            // ROW 1: Владелец
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Владелец',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontText,
                                      fontSize: 14,
                                      color: Color(0xFF8E8E93),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: widget.onOwnerTap ?? widget.onSenderTap,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_ownerAvatar.isNotEmpty) ...[
                                          ClipOval(
                                            child: Image.network(
                                              _ownerAvatar,
                                              width: 22,
                                              height: 22,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ] else ...[
                                          _buildAvatarFallback(),
                                          const SizedBox(width: 8),
                                        ],
                                        if (VerificationBadge.isVerified(_ownerVerification)) ...[
                                          VerificationBadge(
                                            verification: _ownerVerification,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Text(
                                          _ownerDisplayName,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF3B98FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Smooth Animated CrossFade for Модель and Фон rows
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 450),
                              firstCurve: Curves.easeOutCubic,
                              secondCurve: Curves.easeOutCubic,
                              sizeCurve: Curves.easeOutCubic,
                              crossFadeState: (_isSpinning || _currentGift.isUpgraded || _isFinished)
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              firstChild: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Divider(color: Color(0xFF262933), height: 1, indent: 16, endIndent: 16),
                                  // ROW 2: Дата
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Дата',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14,
                                            color: Color(0xFF8E8E93),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          _formatDate(_currentGift.createdAt),
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              secondChild: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Divider(color: Color(0xFF262933), height: 1, indent: 16, endIndent: 16),
                                  // ROW 2: Модель
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Модель',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14,
                                            color: Color(0xFF8E8E93),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              currentModelName,
                                              style: const TextStyle(
                                                fontFamily: AppTheme.fontText,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0x2E3390EC),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                currentModelRarity,
                                                style: const TextStyle(
                                                  fontFamily: AppTheme.fontText,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF4DA6FF),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Divider(color: Color(0xFF262933), height: 1, indent: 16, endIndent: 16),
                                  // ROW 3: Фон
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Фон',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontText,
                                            fontSize: 14,
                                            color: Color(0xFF8E8E93),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              currentBackdropName,
                                              style: const TextStyle(
                                                fontFamily: AppTheme.fontText,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0x2E3390EC),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                currentBackdropRarity,
                                                style: const TextStyle(
                                                  fontFamily: AppTheme.fontText,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF4DA6FF),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      const Text(
                        'Подарок виден в профиле.',
                        style: TextStyle(
                          fontFamily: AppTheme.fontText,
                          fontSize: 12.5,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ===========================================================
                      // 4. BOTTOM ACTION BUTTON ("Улучшить" or "ОК")
                      // ===========================================================
                      _buildBottomButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Celebratory Confetti Canvas overlay
          if (_confettiParticles.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ConfettiPainter(particles: _confettiParticles),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Horizontal roulette carousel track
  Widget _buildRouletteCarousel(double screenWidth, double pMod) {
    const slideWidth = 170.0;
    final totalSteps = _modelSteps.length;
    final currentFloatIndex = pMod * (totalSteps - 1);
    final centerX = (screenWidth - slideWidth) / 2.0;

    return SizedBox(
      height: 165,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(totalSteps, (i) {
          // Slide position: centered when currentFloatIndex == i
          final x = centerX + (i - currentFloatIndex) * slideWidth;

          // Render only visible slides to maintain 60 FPS
          if (x < -slideWidth || x > screenWidth + slideWidth) {
            return const SizedBox.shrink();
          }

          final dist = ((i - currentFloatIndex).abs()).clamp(0.0, 2.0);
          final scale = (1.0 - (dist * 0.12)).clamp(0.78, 1.0);
          final opacity = (1.0 - (dist * 0.28)).clamp(0.4, 1.0);

          final model = _modelSteps[i];

          return Positioned(
            left: x,
            top: 0,
            bottom: 0,
            width: slideWidth,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Center(
                  child: model.isImage
                      ? Image.asset(
                          model.assetPath,
                          width: 145,
                          height: 145,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.card_giftcard_rounded,
                            size: 64,
                            color: Colors.white70,
                          ),
                        )
                      : Lottie.asset(
                          model.assetPath,
                          width: 145,
                          height: 145,
                          fit: BoxFit.contain,
                          animate: true,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.card_giftcard_rounded,
                            size: 64,
                            color: Colors.white70,
                          ),
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // Maximally rounded pill action button with smooth expansion
  Widget _buildBottomButton() {
    final isSpinning = _isSpinning;
    final isFinished = _isFinished || _currentGift.isUpgraded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.symmetric(
        horizontal: isSpinning || isFinished ? 0 : 16,
      ),
      height: 50,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSpinning
              ? null
              : (isFinished ? () => Navigator.pop(context) : _startUpgrade),
          borderRadius: BorderRadius.circular(50),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF2481CC),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2481CC).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isSpinning
                  ? const Row(
                      key: ValueKey('spinning'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Улучшение...',
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : isFinished
                      ? const Text(
                          'ОК',
                          key: ValueKey('ok'),
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Улучшить за 1000 Sparks',
                          key: ValueKey('upgrade_sparks'),
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    final name = _ownerDisplayName;
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2A2E39),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// Particle for celebratory confetti burst
class _ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  Color color;
  double rot;
  double vRot;
  bool isRect;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rot,
    required this.vRot,
    required this.isRect,
  });

  void update() {
    x += vx;
    y += vy;
    vy += 0.32; // Gravity
    vx *= 0.985;
    rot += vRot;
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.y > size.height + 20) continue;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate((p.rot * math.pi) / 180.0);

      final paint = Paint()
        ..color = p.color
        ..style = PaintingStyle.fill;

      if (p.isRect) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.65),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2.2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
