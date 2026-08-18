import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import '../data/invite_service.dart';
import 'add_contact_dialog.dart';
import 'conversation_page.dart';

class NewConversationPage extends StatefulWidget {
  const NewConversationPage({super.key});

  @override
  State<NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<NewConversationPage> {
  final _service = ChatService();
  late Future<List<ContactProfile>> _contactsFuture;
  String? _openingContactId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _contactsFuture = _service.loadContacts();
    });
  }

  Future<void> _open(ContactProfile contact) async {
    setState(() => _openingContactId = contact.id);
    try {
      final id = await _service.createDirectConversation(contact.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ConversationPage(
            conversationId: id,
            title: contact.displayName,
            avatarUrl: contact.avatarUrl,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final clean = e.toString().replaceAll('Exception:', '').replaceAll('PostgrestException', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(clean.isNotEmpty ? clean : 'No se pudo iniciar la conversación.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _openingContactId = null);
    }
  }

  Future<void> _showAddContact() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (_) => const AddContactDialog(),
    );
    if (!mounted) return;
    if (result is ContactProfile) {
      _open(result);
    } else if (result != null) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva conversación'),
        actions: [
          IconButton(
            tooltip: 'Buscar o agregar @alias',
            onPressed: _showAddContact,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadData(),
        child: FutureBuilder<List<ContactProfile>>(
          future: _contactsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final contacts = snapshot.data ?? [];

            if (contacts.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Inicia tu primera conversación',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Busca a tus amigos por su @alias único o invítalos por WhatsApp para comenzar a chatear seguro.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _showAddContact,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Buscar usuario por @alias'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => InviteService.inviteViaWhatsApp(),
                        icon: const Icon(Icons.share_rounded, color: Color(0xFF25D366)),
                        label: const Text('Invitar amigos por WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF25D366)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: contacts.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 20),
                    ),
                    title: const Text(
                      'Buscar nuevo usuario por @alias',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    subtitle: const Text('Conectar con personas fuera de tu lista'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showAddContact,
                  );
                }

                final contact = contacts[index - 1];
                final isOpening = _openingContactId == contact.id;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.secondary,
                    backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
                    child: contact.avatarUrl == null
                        ? Text(
                            contact.displayName.characters.first.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (contact.isVerified) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                  subtitle: contact.username == null ? null : Text('@${contact.username}'),
                  trailing: isOpening
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
                  onTap: _openingContactId == null ? () => _open(contact) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
