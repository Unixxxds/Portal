import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/media_cache_service.dart';
import '../theme.dart';

class DataAndStorageScreen extends StatefulWidget {
  const DataAndStorageScreen({super.key});

  @override
  State<DataAndStorageScreen> createState() => _DataAndStorageScreenState();
}

class _DataAndStorageScreenState extends State<DataAndStorageScreen> {
  bool _isLoading = true;
  bool _isClearing = false;
  double _clearProgress = 0.0;
  StorageUsage _usage = const StorageUsage();

  // Settings
  bool _autoDownloadWifi = true;
  bool _autoDownloadMobile = true;
  bool _saveToGallery = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final usage = await MediaCacheService.instance.calculateStorageUsage();

    if (mounted) {
      setState(() {
        _autoDownloadWifi = prefs.getBool('portal_auto_dl_wifi') ?? true;
        _autoDownloadMobile = prefs.getBool('portal_auto_dl_mobile') ?? true;
        _saveToGallery = prefs.getBool('portal_save_gallery') ?? false;
        _usage = usage;
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePref(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  Future<void> _animateProgressTo(double target, {int durationMs = 280}) async {
    final start = _clearProgress;
    final diff = target - start;
    const steps = 14;
    final stepDelay = (durationMs / steps).round().clamp(10, 40);
    for (int i = 1; i <= steps; i++) {
      if (!mounted) return;
      setState(() {
        _clearProgress = (start + diff * (i / steps)).clamp(0.0, 1.0);
      });
      await Future.delayed(Duration(milliseconds: stepDelay));
    }
  }

  Future<void> _performClear(bool photos, bool voices, bool other) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isClearing = true;
      _clearProgress = 0.05;
    });

    // Step 1: Initialize clearing
    await _animateProgressTo(0.22, durationMs: 250);

    // Step 2: Clear Photos Cache
    if (photos) {
      await MediaCacheService.instance.clearPhotosCache();
    }
    await _animateProgressTo(0.52, durationMs: 300);

    // Step 3: Clear Voices Cache
    if (voices) {
      await MediaCacheService.instance.clearVoicesCache();
    }
    await _animateProgressTo(0.78, durationMs: 300);

    // Step 4: Clear Temporary & Other Cache
    if (other) {
      await MediaCacheService.instance.clearAllCache();
    }
    await _animateProgressTo(0.92, durationMs: 220);

    // Step 5: Recalculate usage and hit 100%
    final newUsage = await MediaCacheService.instance.calculateStorageUsage();
    await _animateProgressTo(1.0, durationMs: 200);

    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 380));

    if (mounted) {
      setState(() {
        _usage = newUsage;
        _isClearing = false;
        _clearProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 20),
              SizedBox(width: 10),
              Text('Кэш успешно очищен'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _optimizeDb() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isClearing = true;
      _clearProgress = 0.12;
    });

    await _animateProgressTo(0.65, durationMs: 350);
    await MediaCacheService.instance.optimizeDatabase();
    final newUsage = await MediaCacheService.instance.calculateStorageUsage();
    await _animateProgressTo(1.0, durationMs: 250);

    await Future.delayed(const Duration(milliseconds: 350));

    if (mounted) {
      setState(() {
        _usage = newUsage;
        _isClearing = false;
        _clearProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF34C759), size: 20),
              SizedBox(width: 10),
              Text('База данных оптимизирована и сжата'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showClearCacheBottomSheet() {
    bool clearPhotos = true;
    bool clearVoices = true;
    bool clearOther = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          int selectedBytes = 0;
          if (clearPhotos) selectedBytes += _usage.photosBytes;
          if (clearVoices) selectedBytes += _usage.voicesBytes;
          if (clearOther) selectedBytes += _usage.otherBytes;

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 34),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Очистить кэш Portal',
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Выберите данные для удаления. Фотографии будут повторно загружены из сети при следующем открытии чата.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),

                // Checkboxes
                _buildCheckboxTile(
                  title: 'Фотографии и медиа',
                  sizeStr: MediaCacheService.formatBytes(_usage.photosBytes),
                  color: const Color(0xFF007AFF),
                  icon: Icons.photo_library_rounded,
                  value: clearPhotos,
                  onChanged: (val) {
                    setModalState(() => clearPhotos = val ?? false);
                  },
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1, indent: 44),
                _buildCheckboxTile(
                  title: 'Голосовые сообщения',
                  sizeStr: MediaCacheService.formatBytes(_usage.voicesBytes),
                  color: const Color(0xFFFF9500),
                  icon: Icons.mic_rounded,
                  value: clearVoices,
                  onChanged: (val) {
                    setModalState(() => clearVoices = val ?? false);
                  },
                ),
                const Divider(color: Color(0x1AFFFFFF), height: 1, indent: 44),
                _buildCheckboxTile(
                  title: 'Временные файлы и эскизы',
                  sizeStr: MediaCacheService.formatBytes(_usage.otherBytes),
                  color: const Color(0xFF8E8E93),
                  icon: Icons.folder_zip_rounded,
                  value: clearOther,
                  onChanged: (val) {
                    setModalState(() => clearOther = val ?? false);
                  },
                ),

                const SizedBox(height: 24),

                // Clear button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selectedBytes == 0
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _performClear(clearPhotos, clearVoices, clearOther);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      disabledBackgroundColor: const Color(0x33FF3B30),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Очистить (${MediaCacheService.formatBytes(selectedBytes)})',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Отмена',
                      style: TextStyle(
                        color: Color(0xFF007AFF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String sizeStr,
    required Color color,
    required IconData icon,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              sizeStr,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 10),
            CupertinoCheckbox(
              value: value,
              activeColor: const Color(0xFF007AFF),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isClearing,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF007AFF), size: 20),
                onPressed: _isClearing ? null : () => Navigator.pop(context),
              ),
              title: const Text(
                'Данные и память',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            body: _isLoading
                ? const Center(
                    child: CupertinoActivityIndicator(radius: 14, color: Colors.white70),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 60),
                    children: [
                      const SizedBox(height: 12),

                      // =============================================================
                      // 1. STORAGE DASHBOARD
                      // =============================================================
                      _buildStorageDashboard(),

                      const SizedBox(height: 24),

                      // =============================================================
                      // 2. CATEGORIES BREAKDOWN
                      // =============================================================
                      _buildSectionHeader('ИСПОЛЬЗОВАНИЕ ПАМЯТИ'),
                      _buildGroupedCard([
                        _buildDetailTile(
                          icon: Icons.photo_library_rounded,
                          iconBg: const Color(0xFF007AFF),
                          title: 'Фотографии и медиа',
                          subtitle: 'Сохранённые фото из чатов',
                          sizeText: MediaCacheService.formatBytes(_usage.photosBytes),
                          onClear: () => _performClear(true, false, false),
                        ),
                        _buildDetailTile(
                          icon: Icons.mic_rounded,
                          iconBg: const Color(0xFFFF9500),
                          title: 'Голосовые сообщения',
                          subtitle: 'Аудиозаписи и голосовые',
                          sizeText: MediaCacheService.formatBytes(_usage.voicesBytes),
                          onClear: () => _performClear(false, true, false),
                        ),
                        _buildDetailTile(
                          icon: Icons.storage_rounded,
                          iconBg: const Color(0xFF8B5CF6),
                          title: 'База данных сообщений',
                          subtitle: 'Локальный архив чатов SQLite',
                          sizeText: MediaCacheService.formatBytes(_usage.databaseBytes),
                          actionLabel: 'Сжать',
                          onClear: _optimizeDb,
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // =============================================================
                      // 3. AUTO-DOWNLOAD MEDIA
                      // =============================================================
                      _buildSectionHeader('АВТОЗАГРУЗКА МЕДИА'),
                      _buildGroupedCard([
                        _buildSwitchTile(
                          icon: Icons.wifi_rounded,
                          iconBg: const Color(0xFF34C759),
                          title: 'Через Wi-Fi',
                          value: _autoDownloadWifi,
                          onChanged: (val) {
                            setState(() => _autoDownloadWifi = val);
                            _updatePref('portal_auto_dl_wifi', val);
                          },
                        ),
                        _buildSwitchTile(
                          icon: Icons.signal_cellular_alt_rounded,
                          iconBg: const Color(0xFF5AC8FA),
                          title: 'Через мобильную сеть',
                          value: _autoDownloadMobile,
                          onChanged: (val) {
                            setState(() => _autoDownloadMobile = val);
                            _updatePref('portal_auto_dl_mobile', val);
                          },
                        ),
                        _buildSwitchTile(
                          icon: Icons.save_alt_rounded,
                          iconBg: const Color(0xFFAF52DE),
                          title: 'Сохранять в галерею',
                          value: _saveToGallery,
                          onChanged: (val) {
                            setState(() => _saveToGallery = val);
                            _updatePref('portal_save_gallery', val);
                          },
                        ),
                      ]),

                      const SizedBox(height: 18),

                      // iOS Explanatory Footer Text
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Все полученные фотографии автоматически кэшируются на устройстве и доступны без подключения к интернету. При очистке кэша они освобождают память и при необходимости скачаются снова из облака.',
                          style: TextStyle(
                            fontFamily: AppTheme.fontText,
                            fontSize: 12.5,
                            color: Color(0xFF8E8E93),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // ===================================================================
          // BLUR & PROGRESS OVERLAY (Appears while clearing cache)
          // ===================================================================
          if (_isClearing)
            Positioned.fill(
              child: _buildClearingOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _buildClearingOverlay() {
    final percent = (_clearProgress * 100).toInt().clamp(0, 100);

    return PopScope(
      canPop: false,
      child: Material(
        type: MaterialType.transparency,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.65),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Над линией: Проценты завершения очистки (без жёлтых линий)
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Линия заполнения (скруглённая по всем углам)
                SizedBox(
                  width: 250,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 7,
                      width: double.infinity,
                      color: const Color(0x33FFFFFF),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _clearProgress.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Под линией: надпись (без подложки и без жёлтых линий)
                const SizedBox(
                  width: 270,
                  child: Text(
                    'пожалуйста, не закрывайте это окно до завершения отчистки кэша.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF8E8E93),
                      decoration: TextDecoration.none,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorageDashboard() {
    final total = _usage.totalCacheBytes;
    final totalAll = _usage.totalAllBytes > 0 ? _usage.totalAllBytes.toDouble() : 1.0;

    final photoFraction = (_usage.photosBytes / totalAll).clamp(0.0, 1.0);
    final voiceFraction = (_usage.voicesBytes / totalAll).clamp(0.0, 1.0);
    final dbFraction = (_usage.databaseBytes / totalAll).clamp(0.0, 1.0);
    final otherFraction = (_usage.otherBytes / totalAll).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
      ),
      child: Column(
        children: [
          // Total cache indicator
          Text(
            MediaCacheService.formatBytes(total),
            style: const TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Занято кэшем Portal',
            style: TextStyle(
              fontFamily: AppTheme.fontText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 20),

          // Segmented Progress Bar (iOS style)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (_usage.photosBytes > 0)
                    Expanded(
                      flex: (photoFraction * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF007AFF)),
                    ),
                  if (_usage.voicesBytes > 0)
                    Expanded(
                      flex: (voiceFraction * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFFFF9500)),
                    ),
                  if (_usage.databaseBytes > 0)
                    Expanded(
                      flex: (dbFraction * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF8B5CF6)),
                    ),
                  if (_usage.otherBytes > 0)
                    Expanded(
                      flex: (otherFraction * 100).round().clamp(1, 100),
                      child: Container(color: const Color(0xFF636366)),
                    ),
                  if (total == 0 && _usage.databaseBytes == 0)
                    Expanded(
                      child: Container(color: const Color(0xFF3A3A3C)),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Legend row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLegendItem('Фото', const Color(0xFF007AFF)),
              _buildLegendItem('Голосовые', const Color(0xFFFF9500)),
              _buildLegendItem('База', const Color(0xFF8B5CF6)),
              _buildLegendItem('Другое', const Color(0xFF636366)),
            ],
          ),

          const SizedBox(height: 20),

          // Primary Clear Cache Button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: total == 0 ? null : _showClearCacheBottomSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C2C2E),
                disabledBackgroundColor: const Color(0x1AFFFFFF),
                foregroundColor: total > 0 ? const Color(0xFFFF3B30) : const Color(0xFF636366),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                total > 0 ? 'Очистить кэш (${MediaCacheService.formatBytes(total)})' : 'Кэш чист',
                style: const TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 11.5,
            color: Color(0xFF8E8E93),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontDisplay,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupedCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                const Divider(
                  color: Color(0x1AFFFFFF),
                  thickness: 0.5,
                  indent: 58,
                  height: 1,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildDetailTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String sizeText,
    String? actionLabel,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            sizeText,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                actionLabel ?? 'Очистить',
                style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconBg,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: const Color(0xFF34C759),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
