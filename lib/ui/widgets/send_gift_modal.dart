import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../data/database_helper.dart';
import '../../models/chat.dart';
import '../../models/user_gift.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../theme.dart';
import 'gift_visuals.dart';

class CatalogGiftItem {
  final String id;
  final String collection;
  final String name;
  final String assetPath;
  final int price;
  final String description;

  const CatalogGiftItem({
    required this.id,
    required this.collection,
    required this.name,
    required this.assetPath,
    this.price = 50,
    required this.description,
  });

  bool get isImage =>
      assetPath.toLowerCase().endsWith('.png') ||
      assetPath.toLowerCase().endsWith('.jpg') ||
      assetPath.toLowerCase().endsWith('.webp');
}

class SendGiftModal extends StatefulWidget {
  final Chat chat;
  final String? recipientUsername;
  final int? recipientId;
  final Function(UserGift)? onGiftSent;

  const SendGiftModal({
    super.key,
    required this.chat,
    this.recipientUsername,
    this.recipientId,
    this.onGiftSent,
  });

  static Future<UserGift?> show(
    BuildContext context, {
    required Chat chat,
    String? recipientUsername,
    int? recipientId,
    Function(UserGift)? onGiftSent,
  }) {
    return showModalBottomSheet<UserGift>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SendGiftModal(
        chat: chat,
        recipientUsername: recipientUsername,
        recipientId: recipientId,
        onGiftSent: onGiftSent,
      ),
    );
  }

  @override
  State<SendGiftModal> createState() => _SendGiftModalState();
}

class _SendGiftModalState extends State<SendGiftModal> {
  static const List<CatalogGiftItem> _catalog = [
    CatalogGiftItem(
      id: 'cars',
      collection: 'CARS',
      name: 'Lada Priora',
      assetPath: 'lib/assets/gifts/cars/lada-model-priora.png',
      price: 50,
      description: 'Эксклюзивная коллекция CARS: Lada Priora',
    ),
    CatalogGiftItem(
      id: 'gargona',
      collection: 'GARGONA',
      name: 'Chrome Gorgon',
      assetPath: 'lib/assets/gifts/gargona/Chrome-Gorgon.json',
      price: 50,
      description: 'Легендарный анимированный подарок Chrome Gorgon',
    ),
    CatalogGiftItem(
      id: 'girl',
      collection: 'GIRL',
      name: 'Anime Girl',
      assetPath: 'lib/assets/gifts/girl/animegirl.json',
      price: 50,
      description: 'Очаровательный анимированный подарок Anime Girl',
    ),
    CatalogGiftItem(
      id: 'theel',
      collection: 'THEEL',
      name: 'Bumblebee',
      assetPath: 'lib/assets/gifts/theel/Bumblebee.json',
      price: 50,
      description: 'Энергичный анимированный подарок Bumblebee',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            // Opens high, almost to the top (92% of screen height)
            height: screenHeight * 0.92,
            decoration: BoxDecoration(
              color: const Color(0xFA111113),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: const Color(0x1FFFFFFF),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.65),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top Grabber Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Top Header Bar
                _buildHeader(),

                // Catalog Grid
                Expanded(
                  child: _buildCatalogStep(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Header: circular close button on LEFT, Sparks balance on RIGHT
  Widget _buildHeader() {
    final auth = context.watch<AuthProvider>();
    final balance = auth.currentUser?.sparks ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          // Left: circular close button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF242426),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0x1AFFFFFF),
                  width: 1,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const Spacer(),

          // Right: Sparks Balance Pill with lib/assets/premium.svg and white number
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF242426),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0x1AFFFFFF),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'lib/assets/premium.svg',
                  width: 15,
                  height: 15,
                  colorFilter: const ColorFilter.mode(Color(0xFF38BDF8), BlendMode.srcIn),
                ),
                const SizedBox(width: 7),
                Text(
                  '$balance Sparks',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Text(
              'Выберите подарок для отправки ${widget.chat.title.isNotEmpty ? widget.chat.title : ''}:',
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13.5,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),

          // 2x2 Grid of pure grey gift cards
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _catalog.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (context, index) {
              final item = _catalog[index];
              return _buildCollectionCard(item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(CatalogGiftItem item) {
    return GestureDetector(
      onTap: () async {
        // Opens the confirmation modal OVER the first modal
        final sentGift = await showModalBottomSheet<UserGift>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withOpacity(0.65),
          builder: (confirmCtx) => _GiftConfirmModal(
            chat: widget.chat,
            gift: item,
            recipientUsername: widget.recipientUsername,
            recipientId: widget.recipientId,
          ),
        );

        if (sentGift != null && mounted) {
          if (widget.onGiftSent != null) {
            widget.onGiftSent!(sentGift);
          }
          Navigator.pop(context, sentGift);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF242426), // Pure grey color
          borderRadius: BorderRadius.circular(24), // Well-rounded corners
          border: Border.all(
            color: const Color(0x1AFFFFFF),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Center: Gift model / image / animation WITHOUT ANY GLOW
            Expanded(
              child: Center(
                child: item.isImage
                    ? Image.asset(
                        item.assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.card_giftcard_rounded,
                          size: 52,
                          color: Colors.white70,
                        ),
                      )
                    : Lottie.asset(
                        item.assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.card_giftcard_rounded,
                          size: 52,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),

            // Bottom Center: Maximally rounded white pill with BLACK Sparks logo & price
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Black Sparks logo
                  SvgPicture.asset(
                    'lib/assets/premium.svg',
                    width: 14,
                    height: 14,
                    colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${item.price} Sparks',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      letterSpacing: -0.2,
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

// ===========================================================================
// GIFT CONFIRMATION MODAL (OPENS OVER THE FIRST MODAL, NO GLOW)
// ===========================================================================
class _GiftConfirmModal extends StatefulWidget {
  final Chat chat;
  final CatalogGiftItem gift;
  final String? recipientUsername;
  final int? recipientId;

  const _GiftConfirmModal({
    required this.chat,
    required this.gift,
    this.recipientUsername,
    this.recipientId,
  });

  @override
  State<_GiftConfirmModal> createState() => _GiftConfirmModalState();
}

class _GiftConfirmModalState extends State<_GiftConfirmModal> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_isSending) return;

    final auth = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final currentUser = auth.currentUser;

    final userBalance = currentUser?.sparks ?? 0;
    if (userBalance < widget.gift.price) {
      setState(() {
        _errorMessage = 'Недостаточно Sparks на балансе (нужно ${widget.gift.price})';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final recipientName = widget.chat.title.isNotEmpty ? widget.chat.title : 'Пользователь';
    final recipientUsername = widget.recipientUsername ?? widget.chat.username;
    final recipientId = widget.recipientId ?? widget.chat.participantId ?? widget.chat.id;
    final comment = _commentController.text.trim();

    try {
      // 1. Send gift through API
      Map<String, dynamic> apiRes = {};
      try {
        apiRes = await ApiService.instance.sendGift(
          giftId: widget.gift.id,
          recipientUsername: recipientUsername,
          recipientId: recipientId,
          comment: comment.isNotEmpty ? comment : null,
        );
      } catch (err) {
        debugPrint('ApiService.sendGift network note: $err');
        if (mounted) {
          setState(() {
            _errorMessage = err.toString().replaceAll('Exception: ', '');
            _isSending = false;
          });
        }
        return;
      }

      // 2. Deduct Sparks locally and update balance with database
      if (apiRes['sparks'] != null) {
        final serverSparks = int.tryParse(apiRes['sparks'].toString()) ?? (userBalance - widget.gift.price);
        auth.setSparks(serverSparks);
      } else {
        auth.deductSparks(widget.gift.price);
      }
      auth.refreshCurrentUser();

      // 3. Build Portal Gift message JSON payload
      final giftDbId = apiRes['gift'] is Map && apiRes['gift']['id'] != null
          ? apiRes['gift']['id']
          : DateTime.now().millisecondsSinceEpoch;

      final nowIso = DateTime.now().toIso8601String();
      final giftData = {
        'giftDbId': giftDbId,
        'giftId': widget.gift.id,
        'giftName': widget.gift.name,
        'modelName': widget.gift.name,
        'modelFile': widget.gift.assetPath,
        'price': widget.gift.price,
        'comment': comment,
        'senderId': currentUser?.id ?? 0,
        'senderName': currentUser?.fullName.isNotEmpty == true ? currentUser!.fullName : 'Пользователь',
        'senderUsername': currentUser?.username ?? '',
        'senderAvatar': currentUser?.avatar ?? '',
        'recipientId': recipientId,
        'recipientName': recipientName,
        'createdAt': nowIso,
        'isUpgraded': false,
        'backdropName': 'Fire Engine',
        'backdropGradient': 'radial-gradient(circle, #FF334B 0%, #C00C2C 60%, #4A000E 100%)',
        'patternName': 'Ace Of Hearts',
        'patternSvg': '',
      };

      final messageText = '[PORTAL_GIFT]:${jsonEncode(giftData)}';

      // 4. Send message to the chat
      await chatProvider.sendMessage(widget.chat.id, messageText);

      // 5. Instantly save the gifted gift into the recipient user's local gifts
      UserGift createdUserGift;
      if (apiRes['gift'] is Map) {
        createdUserGift = UserGift.fromJson(
          Map<String, dynamic>.from(apiRes['gift'] as Map),
          fallbackUserId: recipientId,
        );
      } else {
        createdUserGift = UserGift(
          id: giftDbId is int ? giftDbId : (int.tryParse(giftDbId.toString()) ?? 0),
          userId: recipientId,
          giftId: widget.gift.id,
          giftName: widget.gift.name,
          modelName: widget.gift.name,
          modelFile: widget.gift.assetPath,
          backdropName: 'Fire Engine',
          backdropGradient: 'radial-gradient(circle, #FF334B 0%, #C00C2C 60%, #4A000E 100%)',
          patternName: 'Ace Of Hearts',
          patternSvg: '',
          senderId: currentUser?.id ?? 0,
          senderFirstName: currentUser?.firstName ?? '',
          senderLastName: currentUser?.lastName ?? '',
          senderUsername: currentUser?.username ?? '',
          senderAvatar: currentUser?.avatar ?? '',
          createdAt: nowIso,
          isUpgraded: false,
          comment: comment.isNotEmpty ? comment : null,
        );
      }

      await DatabaseHelper.instance.insertUserGift(createdUserGift);

      if (mounted) {
        Navigator.pop(context, createdUserGift);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E222D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF30D158), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Подарок "${widget.gift.name}" успешно отправлен!',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final recipientName = widget.chat.title.isNotEmpty ? widget.chat.title : 'Пользователю';
    final auth = context.watch<AuthProvider>();
    final balance = auth.currentUser?.sparks ?? 0;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.85,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFA111113),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: const Color(0x1FFFFFFF),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.7),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Grabber Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Top Header Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Row(
                    children: [
                      // Circular Back button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF242426),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x1AFFFFFF),
                              width: 1,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Sparks Balance Pill with SvgPicture and white number
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF242426),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0x1AFFFFFF),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'lib/assets/premium.svg',
                              width: 15,
                              height: 15,
                              colorFilter: const ColorFilter.mode(Color(0xFF38BDF8), BlendMode.srcIn),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '$balance Sparks',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontDisplay,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Error Notice if any
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x33FF3B30),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x55FF3B30)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFFF453A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              color: Color(0xFFFFB4AB),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Main confirmation body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Centered Gift WITHOUT ANY GLOW
                        SizedBox(
                          height: 150,
                          child: Center(
                            child: widget.gift.isImage
                                ? Image.asset(
                                    widget.gift.assetPath,
                                    width: 160,
                                    height: 140,
                                    fit: BoxFit.contain,
                                  )
                                : Lottie.asset(
                                    widget.gift.assetPath,
                                    width: 160,
                                    height: 140,
                                    fit: BoxFit.contain,
                                  ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Gift Title
                        Text(
                          widget.gift.name,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Recipient indicator pill in pure grey
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242426),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0x1AFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            'Кому: $recipientName',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontDisplay,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Caption Input Field in pure grey
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF242426),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0x1AFFFFFF),
                              width: 1.0,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: TextField(
                            controller: _commentController,
                            enabled: !_isSending,
                            maxLines: 2,
                            maxLength: 140,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontText,
                              fontSize: 14.5,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Подпись к подарку (необязательно)...',
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.fontText,
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.35),
                              ),
                              counterStyle: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 11,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Long white button with BLACK Sparks logo
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSending ? null : _handleSend,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            child: _isSending
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.black,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Black Sparks logo
                                      SvgPicture.asset(
                                        'lib/assets/premium.svg',
                                        width: 16,
                                        height: 16,
                                        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Отправить за ${widget.gift.price} Sparks',
                                        style: const TextStyle(
                                          fontFamily: AppTheme.fontDisplay,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
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
}

