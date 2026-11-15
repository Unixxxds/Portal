import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

class PortalEmojiPicker extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspacePressed;
  final double bottomPadding;

  const PortalEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspacePressed,
    this.bottomPadding = 0.0,
  });

  @override
  State<PortalEmojiPicker> createState() => _PortalEmojiPickerState();
}

class _PortalEmojiPickerState extends State<PortalEmojiPicker> {
  static const String _recentsKey = 'portal_recent_emojis_v1';

  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _categoryKeys = [];

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
    _categoryKeys.addAll(List.generate(_categories.length + 1, (_) => GlobalKey()));
    _loadRecents();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  void _scrollToCategory(int index) {
    setState(() => _selectedCategoryIndex = index);
    if (index >= 0 && index < _categoryKeys.length) {
      final keyContext = _categoryKeys[index].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 290 + widget.bottomPadding,
      color: const Color(0xFF161618),
      child: Column(
        children: [
          // EMOJI GRID
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 1. Recents section
                if (_recentEmojis.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    key: _categoryKeys[0],
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

                // 2. Standard categories
                for (int catIdx = 0; catIdx < _categories.length; catIdx++) ...[
                  SliverToBoxAdapter(
                    key: _categoryKeys[catIdx + 1],
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
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),

          // BOTTOM CATEGORIES & BACKSPACE BAR
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF111113),
              border: Border(
                top: BorderSide(color: Color(0x1AFFFFFF), width: 0.8),
              ),
            ),
            child: Row(
              children: [
                // Recents tab
                _buildCategoryTab(
                  index: 0,
                  icon: Icons.access_time_rounded,
                  isSelected: _selectedCategoryIndex == 0,
                ),

                // Categories tabs
                for (int i = 0; i < _categories.length; i++)
                  _buildCategoryTab(
                    index: i + 1,
                    icon: _categories[i].icon,
                    isSelected: _selectedCategoryIndex == (i + 1),
                  ),

                const Spacer(),

                // Backspace button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onBackspacePressed();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Icon(
                        Icons.backspace_outlined,
                        color: Color(0xFF8E8E93),
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Safe area bottom inset spacer
          if (widget.bottomPadding > 0)
            SizedBox(height: widget.bottomPadding),
        ],
      ),
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

  Widget _buildCategoryTab({
    required int index,
    required IconData icon,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _scrollToCategory(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? const Color(0xFF007AFF) : const Color(0xFF636366),
          ),
        ),
      ),
    );
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
