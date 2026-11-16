import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/qr_matrix.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import '../widgets/telegram_chat_route.dart';
import '../widgets/telegram_profile_route.dart';
import 'chat_screen.dart';
import 'user_profile_screen.dart';

// =============================================================================
// PROFILE QR SCREEN (1:1 with Screenshot 2)
// =============================================================================
class ProfileQrScreen extends StatefulWidget {
  const ProfileQrScreen({super.key});

  @override
  State<ProfileQrScreen> createState() => _ProfileQrScreenState();
}

class _ProfileQrScreenState extends State<ProfileQrScreen> {
  final GlobalKey _qrPosterKey = GlobalKey();
  bool _isSaving = false;

  Future<void> _saveQrCardToGallery(BuildContext context, String cleanUname) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary = _qrPosterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Не удалось захватить изображение');
      }

      final cardImage = await boundary.toImage(pixelRatio: 3.0);

      // Compositing onto full dark background poster for gallery
      const posterW = 1080.0;
      const posterH = 1440.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, posterW, posterH));

      final bgPaint = Paint()
        ..shader = ui.Gradient.radial(
          const Offset(posterW / 2, posterH * 0.45),
          posterW * 0.85,
          const [
            Color(0xFF282828),
            Color(0xFF141414),
            Color(0xFF070707),
          ],
        );
      canvas.drawRect(const Rect.fromLTWH(0, 0, posterW, posterH), bgPaint);

      final cardDx = (posterW - cardImage.width) / 2.0;
      final cardDy = (posterH - cardImage.height) / 2.0;
      canvas.drawImage(cardImage, Offset(cardDx, cardDy), Paint());

      final finalPicture = recorder.endRecording();
      final finalImage = await finalPicture.toImage(posterW.toInt(), posterH.toInt());
      final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Ошибка конвертации изображения');
      }
      final pngBytes = byteData.buffer.asUint8List();

      final dirPath = await _getGalleryDirectory();
      if (dirPath == null || dirPath.isEmpty) {
        throw Exception('Папка для сохранения не найдена');
      }

      final cleanName = cleanUname.isNotEmpty ? cleanUname : 'user';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$dirPath/portal_qr_${cleanName}_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes, flush: true);

      if (mounted) {
        final folderName = Platform.isWindows ? 'в папку «Изображения»' : 'в галерею';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR-код с фоном успешно сохранен $folderName'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF262626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить QR-код: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<String?> _getGalleryDirectory() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final pictures = Directory('$userProfile\\Pictures');
        if (await pictures.exists()) return pictures.path;
        final downloads = Directory('$userProfile\\Downloads');
        if (await downloads.exists()) return downloads.path;
      }
    } else if (Platform.isAndroid) {
      final picturesDir = Directory('/storage/emulated/0/Pictures');
      if (await picturesDir.exists()) {
        final portalDir = Directory('${picturesDir.path}/Portal');
        if (!await portalDir.exists()) {
          try {
            await portalDir.create(recursive: true);
            return portalDir.path;
          } catch (_) {}
        } else {
          return portalDir.path;
        }
        return picturesDir.path;
      }
      final dcimDir = Directory('/storage/emulated/0/DCIM/Camera');
      if (await dcimDir.exists()) return dcimDir.path;
    }

    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final rawUname = user?.username ?? '';
    final cleanUname = rawUname.replaceFirst(RegExp(r'^@+'), '');
    final displayUsername = cleanUname.isNotEmpty ? cleanUname.toUpperCase() : 'USER';
    final qrPayload = 'https://portalmsg.ru/$cleanUname';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.15),
            radius: 1.15,
            colors: [
              Color(0xFF282828),
              Color(0xFF141414),
              Color(0xFF070707),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 1. TOP BAR: [X] Circle Button  <--->  [Сканировать QR-код] Pill
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close circular button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    // "Сканировать QR-код" pill button
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          TelegramProfileRoute(
                            builder: (_) => const QrScannerScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 7),
                            Text(
                              'Сканировать QR-код',
                              style: TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 13.5,
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

              const Spacer(flex: 2),

              // 2. CENTER: WHITE ROUNDED SQUIRCLE CARD
              Center(
                child: RepaintBoundary(
                  key: _qrPosterKey,
                  child: Container(
                    width: 295,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.45),
                            blurRadius: 36,
                            spreadRadius: 4,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // QR Code with Portal Logo in central black circle
                          SizedBox(
                            width: 245,
                            height: 245,
                            child: CustomPaint(
                              painter: PortalQrPainter(
                                data: qrPayload,
                              ),
                              child: Center(
                                child: Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: Image.asset(
                                    'lib/assets/logo.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.door_sliding_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Username below QR in bold black text
                          Text(
                            '@$displayUsername',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const Spacer(flex: 3),

              // 3. BOTTOM ACTIONS: ONLY DOWNLOAD BUTTON
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: GestureDetector(
                  onTap: _isSaving ? null : () => _saveQrCardToGallery(context, cleanUname),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 0.8,
                      ),
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_downward_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CUSTOM QR PAINTER (Rounded squircle modules, rounded finder eyes)
// =============================================================================
class PortalQrPainter extends CustomPainter {
  final String data;
  late final QrCode _qr;

  PortalQrPainter({required this.data}) {
    _qr = QrCode.encodeText(data, ecLevel: 0); // EC Level M
  }

  @override
  void paint(Canvas canvas, Size size) {
    final moduleCount = _qr.moduleCount;
    final moduleSize = size.width / moduleCount;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    final centerModule = moduleCount / 2.0;
    const centerCutoutRadiusModules = 4.3; // Clear central circle for Portal logo

    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        // Skip modules inside central logo circle
        final distFromCenter = sqrt(pow(r + 0.5 - centerModule, 2) + pow(c + 0.5 - centerModule, 2));
        if (distFromCenter < centerCutoutRadiusModules) {
          continue;
        }

        // Check if inside finder patterns (top-left, top-right, bottom-left)
        final isTopLeft = (r < 7 && c < 7);
        final isTopRight = (r < 7 && c >= moduleCount - 7);
        final isBottomLeft = (r >= moduleCount - 7 && c < 7);

        if (isTopLeft || isTopRight || isBottomLeft) {
          // Handled separately with smooth rounded finder corners below
          continue;
        }

        if (_qr.isDark(r, c)) {
          final rect = Rect.fromLTWH(
            c * moduleSize,
            r * moduleSize,
            moduleSize,
            moduleSize,
          );
          final rrect = RRect.fromRectAndRadius(
            rect.deflate(moduleSize * 0.08),
            Radius.circular(moduleSize * 0.35),
          );
          canvas.drawRRect(rrect, paint);
        }
      }
    }

    // Draw stylish rounded finder patterns in the 3 corners
    _drawFinderPattern(canvas, 0, 0, moduleSize, paint);
    _drawFinderPattern(canvas, moduleCount - 7, 0, moduleSize, paint);
    _drawFinderPattern(canvas, 0, moduleCount - 7, moduleSize, paint);
  }

  void _drawFinderPattern(Canvas canvas, int row, int col, double moduleSize, Paint paint) {
    final outerRect = Rect.fromLTWH(
      col * moduleSize,
      row * moduleSize,
      7 * moduleSize,
      7 * moduleSize,
    );

    // Outer rounded stroke
    final strokePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = moduleSize
      ..isAntiAlias = true;

    final outerStrokeRect = outerRect.deflate(moduleSize * 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outerStrokeRect, Radius.circular(moduleSize * 1.6)),
      strokePaint,
    );

    // Inner solid rounded core
    final innerRect = Rect.fromLTWH(
      (col + 2) * moduleSize,
      (row + 2) * moduleSize,
      3 * moduleSize,
      3 * moduleSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, Radius.circular(moduleSize * 0.8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant PortalQrPainter oldDelegate) => oldDelegate.data != data;
}

// =============================================================================
// QR SCANNER SCREEN
// =============================================================================
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _laserController;
  final TextEditingController _inputController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _processScannedCode(String rawCode) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // 1. Extract clean username from URL or text
      String username = rawCode.trim();
      if (username.contains('portalmsg.ru/')) {
        username = username.split('portalmsg.ru/').last;
      } else if (username.contains('t.me/')) {
        username = username.split('t.me/').last;
      }
      username = username.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

      if (username.isEmpty) {
        if (mounted) {
          _showNotFoundDialog(context, 'Не удалось распознать QR-код');
        }
        return;
      }

      final chatProv = context.read<ChatProvider>();

      // 2. Check local loaded chats
      final localMatch = chatProv.chats.where((c) {
        final u = (c.username ?? '').replaceFirst(RegExp(r'^@+'), '').toLowerCase();
        return u == username.toLowerCase();
      }).firstOrNull;

      if (localMatch != null && mounted) {
        Navigator.pop(context); // Close scanner
        if (localMatch.isChannel) {
          Navigator.of(context).push(
            TelegramChatRoute(builder: (_) => ChatScreen(chat: localMatch)),
          );
        } else {
          Navigator.of(context).push(
            TelegramProfileRoute(builder: (_) => UserProfileScreen(chat: localMatch)),
          );
        }
        return;
      }

      // 3. Search via server
      final results = await ApiService.instance.searchUsers(username);
      final exactMatch = results.where((item) {
        final u = (item['username']?.toString() ?? '').replaceFirst(RegExp(r'^@+'), '').toLowerCase();
        return u == username.toLowerCase();
      }).firstOrNull ?? (results.isNotEmpty ? results.first : null);

      if (exactMatch != null && mounted) {
        final isChan = exactMatch['is_channel'] == 1 || exactMatch['is_channel'] == true || exactMatch['type'] == 'channel';
        final chat = Chat.fromJson(exactMatch);
        chatProv.addOrUpdateChat(chat);

        Navigator.pop(context); // Close scanner
        if (isChan) {
          Navigator.of(context).push(
            TelegramChatRoute(builder: (_) => ChatScreen(chat: chat)),
          );
        } else {
          Navigator.of(context).push(
            TelegramProfileRoute(builder: (_) => UserProfileScreen(chat: chat)),
          );
        }
        return;
      }

      if (mounted) {
        _showNotFoundDialog(context, 'Пользователь @$username не найден в Portal');
      }
    } catch (e) {
      if (mounted) {
        _showNotFoundDialog(context, 'Ошибка при поиске профиля');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showNotFoundDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) {
        return Center(
          child: Container(
            width: 290,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            decoration: BoxDecoration(
              color: const Color(0xE61E1E1E),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFEF4444),
                  size: 38,
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ОК',
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null && image.path.isNotEmpty) {
        // If image selected, prompt user to confirm or scan username
        _showManualInputDialog(initialText: '');
      }
    } catch (_) {
      _showManualInputDialog(initialText: '');
    }
  }

  void _showManualInputDialog({String initialText = ''}) {
    _inputController.text = initialText;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) {
        return Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Поиск по QR / Username',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '@username или ссылка',
                      hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                      filled: true,
                      fillColor: const Color(0xFF282828),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Отмена', style: TextStyle(color: Color(0xFF929292))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final text = _inputController.text.trim();
                          Navigator.pop(ctx);
                          if (text.isNotEmpty) {
                            _processScannedCode(text);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Открыть'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Сканирование QR-кода',
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ],
              ),
            ),

            const Spacer(),

            // Viewfinder Frame with Animated Laser
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // Corner Brackets
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ScannerCornerPainter(),
                      ),
                    ),

                    // Animated Laser line
                    AnimatedBuilder(
                      animation: _laserController,
                      builder: (context, _) {
                        return Positioned(
                          top: _laserController.value * 230 + 10,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 2.5,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xFF38BDF8),
                                  Colors.white,
                                  Color(0xFF38BDF8),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF38BDF8).withOpacity(0.8),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black.withOpacity(0.65),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),
            Text(
              'Наведите камеру на QR-код профиля Portal',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),

            const Spacer(),

            // Bottom Buttons: "Выбрать из галереи" and "Ввести вручную"
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickFromGallery,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, color: Colors.white, size: 19),
                            SizedBox(width: 8),
                            Text(
                              'Из галереи',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showManualInputDialog(),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined, color: Colors.white, size: 19),
                            SizedBox(width: 8),
                            Text(
                              'Ввести ник',
                              style: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
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
          ],
        ),
      ),
    );
  }
}

class ScannerCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 24.0;
    const r = 20.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, r + len)
        ..lineTo(0, r)
        ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
        ..lineTo(r + len, 0),
      paint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - r - len, 0)
        ..lineTo(size.width - r, 0)
        ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
        ..lineTo(size.width, r + len),
      paint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - r - len)
        ..lineTo(0, size.height - r)
        ..arcToPoint(Offset(r, size.height), radius: const Radius.circular(r))
        ..lineTo(r + len, size.height),
      paint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - r - len, size.height)
        ..lineTo(size.width - r, size.height)
        ..arcToPoint(Offset(size.width, size.height - r), radius: const Radius.circular(r))
        ..lineTo(size.width, size.height - r - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

