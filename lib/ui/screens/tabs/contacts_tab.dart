import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/chat_provider.dart';
import '../../theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/badges.dart';
import '../chat_screen.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final directChats = chatProvider.chats.where((c) => c.isDirect).toList();

    final filteredContacts = directChats.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.appBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Контакты',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.borderHairline, width: 0.8),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.textSecondary, size: 18),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Добавление контакта по номеру или email')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderHairline, width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14.5),
                        decoration: const InputDecoration(
                          hintText: 'Поиск контактов',
                          hintStyle: TextStyle(color: AppTheme.textPlaceholder, fontSize: 14.5),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Contacts List
            Expanded(
              child: filteredContacts.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty ? 'Контакты не найдены' : 'Список контактов пуст',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filteredContacts.length,
                      separatorBuilder: (context, index) => const Divider(
                        color: AppTheme.borderHairline,
                        thickness: 0.5,
                        indent: 72,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: AvatarWidget(
                            avatarUrl: contact.avatar,
                            title: contact.title,
                            size: 46,
                            isOnline: contact.isOnline,
                          ),
                          title: Row(
                            children: [
                              if (contact.isVerified) ...[
                                VerificationBadge(
                                  verification: contact.effectiveVerification,
                                  size: 18.0,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  contact.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                              if (contact.isPremium) ...[
                                const SizedBox(width: 5),
                                const PremiumBadge(size: 18.0),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            contact.isOnline ? 'в сети' : 'был(а) недавно',
                            style: TextStyle(
                              color: contact.isOnline ? AppTheme.statusOnline : AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ChatScreen(chat: contact)),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

