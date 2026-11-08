import 'dart:convert';
import 'package:flutter/material.dart';
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
  // 4 Collections matching user instructions:
  // cars -> lada-model-priora.png
  // gargona -> Chrome-Gorgon.json
  // girl -> animegirl.json
  // theel -> Bumblebee.json
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

  int _step = 0; // 0: Catalog selection, 1: Confirm & Caption
  CatalogGiftItem? _selectedGift;
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_selectedGift == null || _isSending) return;

    final auth = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final currentUser = auth.currentUser;

    final userBalance = currentUser?.sparks ?? 0;
    if (userBalance < _selectedGift!.price) {
      setState(() {
        _errorMessage = 'Недостаточно Sparks на балансе (нужно ${_selectedGift!.price})';
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
          giftId: _selectedGift!.id,
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
        final serverSparks = int.tryParse(apiRes['sparks'].toString()) ?? (userBalance - _selectedGift!.price);
        auth.setSparks(serverSparks);
      } else {
        auth.deductSparks(_selectedGift!.price);
      }
      auth.refreshCurrentUser();

      // 3. Build Portal Gift message JSON payload
      final giftDbId = apiRes['gift'] is Map && apiRes['gift']['id'] != null
          ? apiRes['gift']['id']
          : DateTime.now().millisecondsSinceEpoch;

      final nowIso = DateTime.now().toIso8601String();
      final giftData = {
        'giftDbId': giftDbId,
        'giftId': _selectedGift!.id,
        'giftName': _selectedGift!.name,
        'modelName': _selectedGift!.name,
        'modelFile': _selectedGift!.assetPath,
        'price': _selectedGift!.price,
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
          giftId: _selectedGift!.id,
          giftName: _selectedGift!.name,
          modelName: _selectedGift!.name,
          modelFile: _selectedGift!.assetPath,
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

      if (widget.onGiftSent != null) {
        widget.onGiftSent!(createdUserGift);
      }

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
                    'Подарок "${_selectedGift!.name}" успешно отправлен!',
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

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.86,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF191919),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 36,
              offset: Offset(0, -6),
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
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top Header Bar
            _buildHeader(),

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

            // Dynamic Step Content
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _step == 0 ? _buildCatalogStep() : _buildConfirmStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header with back button, title, sparks pill, and close
  Widget _buildHeader() {
    final auth = context.watch<AuthProvider>();
    final balance = auth.currentUser?.sparks ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          if (_step == 1)
            GestureDetector(
              onTap: () {
                setState(() {
                  _step = 0;
                  _errorMessage = null;
                });
              },
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
            ),

          Expanded(
            child: Text(
              _step == 0 ? 'Отправить подарок' : 'Оформление подарка',
              style: const TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
          ),

          // User Sparks Balance Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x26007AFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x40007AFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 14),
                const SizedBox(width: 4),
                Text(
                  '$balance Sparks',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Close button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF8E8E93)),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 0: Catalog grid showing 4 collections
  Widget _buildCatalogStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Выберите коллекцию для отправки ${widget.chat.title.isNotEmpty ? widget.chat.title : ''}:',
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 13.5,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),

          // 2x2 Grid of the 4 collections
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
      onTap: () {
        setState(() {
          _selectedGift = item;
          _step = 1;
          _errorMessage = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withOpacity(0.09),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Ambient soft glow & Gift Preview
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: GiftVisuals.getAmbientGlowColor(item.collection, item.name),
                          blurRadius: 36,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (item.isImage)
                    Image.asset(
                      item.assetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.card_giftcard_rounded,
                        size: 48,
                        color: Colors.white70,
                      ),
                    )
                  else
                    Lottie.asset(
                      item.assetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.card_giftcard_rounded,
                        size: 48,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Collection badge
            Text(
              item.collection,
              style: const TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF38BDF8),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),

            // Gift Name
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 6),

            // Price badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '${item.price} Sparks',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

  // STEP 1: Centered gift model + caption field + ultra rounded send button
  Widget _buildConfirmStep() {
    final gift = _selectedGift!;
    final recipientName = widget.chat.title.isNotEmpty ? widget.chat.title : 'Пользователю';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Centered Gift with Glow
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: GiftVisuals.getAmbientGlowColor(gift.collection, gift.name),
                        blurRadius: 52,
                        spreadRadius: 16,
                      ),
                    ],
                  ),
                ),
                if (gift.isImage)
                  Image.asset(
                    gift.assetPath,
                    width: 150,
                    height: 130,
                    fit: BoxFit.contain,
                  )
                else
                  Lottie.asset(
                    gift.assetPath,
                    width: 150,
                    height: 130,
                    fit: BoxFit.contain,
                  ),
              ],
            ),
          ),

          // Gift Title
          Text(
            gift.name,
            style: const TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 4),

          // Recipient indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Кому: $recipientName',
              style: const TextStyle(
                fontFamily: AppTheme.fontText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Caption Input Field
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF191C25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.09),
                width: 1,
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

          // Ultra-rounded Bottom Send Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSending ? null : _handleSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF090909),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999), // Ultra-rounded corners
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF090909),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.card_giftcard_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Отправить за ${gift.price} Sparks',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

