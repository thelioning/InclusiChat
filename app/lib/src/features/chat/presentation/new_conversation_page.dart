import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import 'conversation_page.dart';

class NewConversationPage extends StatefulWidget {
  const NewConversationPage({super.key});

  @override
  State<NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<NewConversationPage> {
  final _service = ChatService();
  late final Future<List<ContactProfile>> _contacts = _service.loadContacts();
  String? _openingContactId;

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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la conversación.'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _openingContactId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva conversación')),
      body: FutureBuilder<List<ContactProfile>>(
        future: _contacts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar tus contactos.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no tienes contactos aceptados.\nPrimero deberás agregar uno.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final contact = snapshot.data![index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.secondary,
                  child: Text(
                    contact.displayName.characters.first.toUpperCase(),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(contact.displayName)),
                    if (contact.isVerified) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
                subtitle: contact.username == null
                    ? null
                    : Text('@${contact.username}'),
                trailing: _openingContactId == contact.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chat_bubble_outline_rounded),
                onTap: _openingContactId == null ? () => _open(contact) : null,
              );
            },
          );
        },
      ),
    );
  }
}
