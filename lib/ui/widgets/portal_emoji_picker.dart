import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

enum _PickerTab { stickers, emojis }

class PortalEmojiPicker extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspacePressed;
  final ValueChanged<String>? onStickerSelected;
  final bool showStickersTab;
  final double bottomPadding;

  const PortalEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspacePressed,
    this.onStickerSelected,
    this.showStickersTab = true,
    this.bottomPadding = 0.0,
  });

  @override
  State<PortalEmojiPicker> createState() => _PortalEmojiPickerState();
}

class _PortalEmojiPickerState extends State<PortalEmojiPicker>
    with SingleTickerProviderStateMixin {
  static const String _recentsKey = 'portal_recent_emojis_v1';

  late _PickerTab _currentTab;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _tabBarAnimCtrl;
  late final Animation<Offset> _tabBarSlideAnim;
  late final Animation<double> _tabBarFadeAnim;

  bool _isTabBarHidden = false;
  String _searchQuery = '';
  OverlayEntry? _stickerPreviewOverlay;

  // Available stickers in lib/assets/sticker/
  static const List<_StickerItem> _allStickers = [
    _StickerItem(
      path: 'lib/assets/sticker/class.png',
      keywords: ['класс', 'отлично', 'огонь', 'палец вверх', 'class', 'like', 'cool'],
    ),
    _StickerItem(
      path: 'lib/assets/sticker/in_love.png',
      keywords: ['любовь', 'влюблен', 'сердце', 'сердечко', 'love', 'in love', 'heart'],
    ),
    _StickerItem(
      path: 'lib/assets/sticker/sad.png',
      keywords: ['грусть', 'грустно', 'печаль', 'слезы', 'плач', 'sad', 'cry'],
    ),
    _StickerItem(
      path: 'lib/assets/sticker/sadness.png',
      keywords: ['тоска', 'печаль', 'депрессия', 'слезы', 'плач', 'sadness'],
    ),
    _StickerItem(
      path: 'lib/assets/sticker/sticker.gif',
      keywords: ['стикер', 'портал', 'привет', 'мишка', 'portal', 'wave', 'hi'],
    ),
  ];

  List<String> _recentEmojis = [
    '👍', '❤️', '🔥', '😂', '🥰', '😍', '👏', '🎉',
    '😊', '🙏', '😎', '✨', '🥺', '🚀', '💯', '🤣',
  ];

  static const List<_EmojiCategory> _categories = [
    _EmojiCategory(
      name: 'Смайлики',
      headerTitle: 'СМАЙЛИКИ И ЭМОЦИИ',
      icon: Icons.sentiment_satisfied_rounded,
      emojis: [
        '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
        '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
        '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
        '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
        '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮',
        '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓',
        '🧐', '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '😦',
        '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
        '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿',
        '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖',
      ],
    ),
    _EmojiCategory(
      name: 'Жесты',
      headerTitle: 'ЖЕСТЫ И ЛЮДИ',
      icon: Icons.waving_hand_rounded,
      emojis: [
        '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤏', '✌️', '🤞', '🤟',
        '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎',
        '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏',
        '✍️', '💅', '🤳', '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻',
        '👃', '🧠', '🫀', '🫁', '🦷', '🦴', '👀', '👁️', '👅', '👄',
        '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👩', '🧓',
        '👴', '👵', '🙍', '🙎', '🙅', '🙆', '💁', '🙋', '🙇', '🤦',
        '🤷', '👨‍💻', '👩‍💻', '👮', '🕵️', '💂', '🥷', '👷', '🤴', '👸',
      ],
    ),
    _EmojiCategory(
      name: 'Сердца',
      headerTitle: 'СЕРДЦА И ЭМОЦИИ',
      icon: Icons.favorite_rounded,
      emojis: [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
        '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝',
        '💟', '💋', '💌', '💐', '🌹', '🥀', '🌺', '🌸', '🌼', '🌻',
        '✨', '⭐', '🌟', '💫', '💥', '🔥', '⚡', '🎉', '🎊', '🎈',
        '🎀', '🎁', '🏆', '🥇', '🥈', '🥉', '👑', '💎', '💍', '💯',
      ],
    ),
    _EmojiCategory(
      name: 'Животные',
      headerTitle: 'ЖИВОТНЫЕ И ПРИРОДА',
      icon: Icons.pets_rounded,
      emojis: [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
        '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒',
        '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇',
        '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜',
        '🦟', '🦗', '🕷️', '🦂', '🐢', '🐍', '🦎', '🦖', '🦕', '🐙',
        '🦑', '🦐', '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🐋',
        '🦈', '🐊', '🐅', '🐆', '🦓', '🦍', '🦧', '🐘', '🦛', '🦏',
        '🐪', '🐫', '🦒', '🦘', '🌲', '🌳', '🌴', '🌱', '🌿', '☘️',
        '🍀', '🍁', '🍂', '🍃', '🍄', '🌞', '🌝', '🌛', '🌜', '🌙',
      ],
    ),
    _EmojiCategory(
      name: 'Еда',
      headerTitle: 'ЕДА И НАПИТКИ',
      icon: Icons.fastfood_rounded,
      emojis: [
        '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
        '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑',
        '🥦', '🥬', '🥒', '🌶️', '🌽', '🥕', '🥔', '🥐', '🍞', '🥖',
        '🥨', '🧀', '🥚', '🍳', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖',
        '🌭', '🍔', '🍟', '🍕', '🥪', '🥙', '🌮', '🌯', '🥗', '🍝',
        '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🦪', '🍤', '🍙', '🍚',
        '🍘', '🍥', '🍧', '🍨', '🍦', '🥧', '🧁', '🍰', '🎂', '🍮',
        '🍭', '🍬', '🍫', '🍿', '🍩', '🍪', '☕', '🍵', '🧃', '🥤',
        '🧋', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸', '🍹', '🍾', '🧊',
      ],
    ),
    _EmojiCategory(
      name: 'Спорт',
      headerTitle: 'АКТИВНОСТИ И СПОРТ',
      icon: Icons.sports_basketball_rounded,
      emojis: [
        '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
        '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🥊', '🥋', '🛹', '🛼',
        '⛸️', '🎿', '🏂', '🪂', '🏋️', '🤼', '🤸', '⛹️', '🤺', '🏄',
        '🏊', '🚴', '🚵', '🏇', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️',
        '🎮', '🕹️', '🎲', '♟️', '🎯', '🎳', '🎰', '🧩', '🎭', '🎨',
      ],
    ),
    _EmojiCategory(
      name: 'Места',
      headerTitle: 'ПУТЕШЕСТВИЯ И ТРАНСПОРТ',
      icon: Icons.flight_takeoff_rounded,
      emojis: [
        '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
        '🚚', '🚛', '🚜', '🛵', '🏍️', '🛺', '🚲', '🛴', '🚨', '🚔',
        '✈️', '🛫', '🛬', '🛩️', '🚀', '🛸', '🚁', '🛶', '⛵', '🚤',
        '🛳️', '⛴️', '🚢', '⚓', '⛽', '🚦', '🚥', '🗺️', '🗿', '🗽',
        '🗼', '🏰', '🏯', '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🏕️',
        '🏠', '🏡', '🏢', '🏬', '🏦', '🏨', '🏪', '🏫', '💒', '🏛️',
      ],
    ),
    _EmojiCategory(
      name: 'Символы',
      headerTitle: 'ПРЕДМЕТЫ И СИМВОЛЫ',
      icon: Icons.lightbulb_rounded,
      emojis: [
        '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '📷', '📸', '📹', '🎥',
        '📺', '📻', '🎙️', '🎧', '⏰', '⏱️', '⏲️', '🕰️', '⌛', '⏳',
        '💰', '🪙', '💵', '💸', '💳', '🧾', '✉️', '📧', '📦', '🏷️',
        '📌', '📍', '📎', '✏️', '✒️', '🖊️', '🖌️', '🖍️', '📝', '🔒',
        '🔓', '🔏', '🔐', '🔑', '🗝️', '🔔', '🔕', '💡', '🔦', '🕯️',
        '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪', '🟤', '🛑',
        '⛔', '🚫', '⚠️', '❗', '❕', '❓', '❔', '‼️', '⁉️', '✅',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentTab = widget.showStickersTab ? _PickerTab.stickers : _PickerTab.emojis;

    _tabBarAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _tabBarSlideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.8),
    ).animate(CurvedAnimation(
      parent: _tabBarAnimCtrl,
      curve: Curves.easeOutCubic,
    ));

    _tabBarFadeAnim = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _tabBarAnimCtrl,
      curve: Curves.easeOutCubic,
    ));

    _loadRecents();
  }

  @override
  void dispose() {
    _hideStickerPreview();
    _searchCtrl.dispose();
    _scrollController.dispose();
    _tabBarAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_recentsKey);
      if (saved != null && saved.isNotEmpty) {
        setState(() {
          _recentEmojis = saved;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRecentEmoji(String emoji) async {
    setState(() {
      _recentEmojis.remove(emoji);
      _recentEmojis.insert(0, emoji);
      if (_recentEmojis.length > 32) {
        _recentEmojis = _recentEmojis.sublist(0, 32);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentsKey, _recentEmojis);
    } catch (_) {}
  }

  void _onEmojiTap(String emoji) {
    HapticFeedback.lightImpact();
    _saveRecentEmoji(emoji);
    widget.onEmojiSelected(emoji);
  }

  void _onStickerTap(String stickerPath) {
    HapticFeedback.lightImpact();
    widget.onStickerSelected?.call(stickerPath);
  }

  // Long press sticker preview overlay
  void _showStickerPreview(String stickerPath) {
    _hideStickerPreview();
    final overlay = Overlay.of(context);
    _stickerPreviewOverlay = OverlayEntry(
      builder: (ctx) => _StickerPreviewModal(stickerPath: stickerPath),
    );
    overlay.insert(_stickerPreviewOverlay!);
  }

  void _hideStickerPreview() {
    _stickerPreviewOverlay?.remove();
    _stickerPreviewOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: Container(
        height: 330 + widget.bottomPadding,
        decoration: const BoxDecoration(
          color: Color(0xFF161618), // Deep dark matching Telegram reference
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 1. TOP HEADER: Sticker add button + Fully rounded Search bar
                _buildTopSearchBar(),

                // 2. CONTENT (Stickers or Emojis)
                Expanded(
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction == ScrollDirection.reverse) {
                        // Scrolling down: hide tab bar
                        if (!_isTabBarHidden) {
                          setState(() => _isTabBarHidden = true);
                          _tabBarAnimCtrl.forward();
                        }
                      } else if (notification.direction == ScrollDirection.forward) {
                        // Scrolling up: show tab bar
                        if (_isTabBarHidden) {
                          setState(() => _isTabBarHidden = false);
                          _tabBarAnimCtrl.reverse();
                        }
                      }
                      return false;
                    },
                    child: _currentTab == _PickerTab.stickers
                        ? _buildStickersView()
                        : _buildEmojisView(),
                  ),
                ),
              ],
            ),

            // 3. FLOATING TRANSLUCENT TAB BAR AT BOTTOM CENTER
            if (widget.showStickersTab)
              Positioned(
                bottom: 12 + widget.bottomPadding,
                left: 0,
                right: 0,
                child: Center(
                  child: SlideTransition(
                    position: _tabBarSlideAnim,
                    child: FadeTransition(
                      opacity: _tabBarFadeAnim,
                      child: _buildFloatingTabBar(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP SEARCH BAR (Fully rounded, Telegram iOS styling)
  // ===========================================================================
  Widget _buildTopSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF242428), // Telegram search pill color
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF8E8E93),
              size: 19,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim().toLowerCase());
                },
                style: const TextStyle(
                  fontFamily: AppTheme.fontText,
                  fontSize: 14.5,
                  color: Colors.white,
                ),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.fontText,
                    fontSize: 14.5,
                    color: Color(0xFF8E8E93),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.cancel_rounded,
                    size: 16,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FLOATING TRANSLUCENT TAB BAR (Стикеры & Эмодзи)
  // ===========================================================================
  Widget _buildFloatingTabBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            color: const Color(0xCC26262E), // Translucent dark frosted glass
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x28FFFFFF), width: 0.85),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Стикеры Tab
              _buildTabButton(
                title: 'Стикеры',
                isSelected: _currentTab == _PickerTab.stickers,
                onTap: () {
                  if (_currentTab != _PickerTab.stickers) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentTab = _PickerTab.stickers);
                  }
                },
              ),

              // 2. Эмодзи Tab
              _buildTabButton(
                title: 'Эмодзи',
                isSelected: _currentTab == _PickerTab.emojis,
                onTap: () {
                  if (_currentTab != _PickerTab.emojis) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentTab = _PickerTab.emojis);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x38FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : const Color(0x99FFFFFF),
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // STICKERS VIEW (Grid with Long Press preview)
  // ===========================================================================
  Widget _buildStickersView() {
    final filtered = _searchQuery.isEmpty
        ? _allStickers
        : _allStickers.where((s) => s.matches(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'Стикеры не найдены',
          style: TextStyle(
            fontFamily: AppTheme.fontText,
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 56 + widget.bottomPadding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.0,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final sticker = filtered[index];
        return GestureDetector(
          onTap: () => _onStickerTap(sticker.path),
          onLongPressStart: (_) {
            HapticFeedback.mediumImpact();
            _showStickerPreview(sticker.path);
          },
          onLongPressEnd: (_) => _hideStickerPreview(),
          onLongPressCancel: () => _hideStickerPreview(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              sticker.path,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_rounded,
                color: Colors.white24,
                size: 30,
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // EMOJIS VIEW
  // ===========================================================================
  Widget _buildEmojisView() {
    if (_searchQuery.isNotEmpty) {
      final matching = <String>[];
      for (final cat in _categories) {
        for (final em in cat.emojis) {
          if (!matching.contains(em)) {
            matching.add(em);
          }
        }
      }
      return GridView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(8, 4, 8, 56 + widget.bottomPadding),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1.0,
        ),
        itemCount: matching.length,
        itemBuilder: (context, i) => _buildEmojiButton(matching[i]),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 1. Recents
        if (_recentEmojis.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader('НЕДАВНИЕ'),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 1.0,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildEmojiButton(_recentEmojis[i]),
                childCount: _recentEmojis.length,
              ),
            ),
          ),
        ],

        // 2. Categories
        for (int catIdx = 0; catIdx < _categories.length; catIdx++) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(_categories[catIdx].headerTitle),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 1.0,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildEmojiButton(_categories[catIdx].emojis[i]),
                childCount: _categories[catIdx].emojis.length,
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: 56 + widget.bottomPadding),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontText,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onEmojiTap(emoji),
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(
              fontSize: 27,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// STICKER PREVIEW OVERLAY (Fullscreen backdrop blur & enlarged sticker popup)
// =============================================================================
class _StickerPreviewModal extends StatelessWidget {
  final String stickerPath;

  const _StickerPreviewModal({required this.stickerPath});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Colors.black.withOpacity(0.55),
              ),
            ),
          ),

          // Enlarged Sticker in center with soft drop shadow
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.5, end: 1.0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 36,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      stickerPath,
                      width: 190,
                      height: 190,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerItem {
  final String path;
  final List<String> keywords;

  const _StickerItem({required this.path, required this.keywords});

  bool matches(String query) {
    if (path.toLowerCase().contains(query)) return true;
    for (final kw in keywords) {
      if (kw.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}

class _EmojiCategory {
  final String name;
  final String headerTitle;
  final IconData icon;
  final List<String> emojis;

  const _EmojiCategory({
    required this.name,
    required this.headerTitle,
    required this.icon,
    required this.emojis,
  });
}
