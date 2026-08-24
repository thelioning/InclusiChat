import 'dart:io';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';

class QuickShareContactPickerPage extends StatefulWidget {
  const QuickShareContactPickerPage({
    super.key,
    required this.imagePath,
    this.initialCaption = '',
  });

  final String imagePath;
  final String initialCaption;

  @override
  State<QuickShareContactPickerPage> createState() =>
      _QuickShareContactPickerPageState();
}

class _QuickShareContactPickerPageState
    extends State<QuickShareContactPickerPage> {
  final _chatService = ChatService();
  late final TextEditingController _captionController;
  final _searchController = TextEditingController();

  List<ContactProfile> _contacts = [];
  List<ConversationSummary> _conversations = [];
  bool _loading = true;
  bool _sending = false;

  final Set<String> _selectedContactUserIds = {};
  final Set<String> _selectedConversationIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _loadData();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _chatService.loadContacts(),
        _chatService.loadConversations(),
      ]);
      if (mounted) {
        setState(() {
          _contacts = results[0] as List<ContactProfile>;
          _conversations = results[1] as List<ConversationSummary>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _selectedCount =>
      _selectedContactUserIds.length + _selectedConversationIds.length;

  void _toggleContact(String userId) {
    setState(() {
      if (_selectedContactUserIds.contains(userId)) {
        _selectedContactUserIds.remove(userId);
      } else {
        _selectedContactUserIds.add(userId);
      }
    });
  }

  void _toggleConversation(String conversationId) {
    setState(() {
      if (_selectedConversationIds.contains(conversationId)) {
        _selectedConversationIds.remove(conversationId);
      } else {
        _selectedConversationIds.add(conversationId);
      }
    });
  }

  Future<void> _sendPhoto() async {
    if (_selectedCount == 0 || _sending) return;
    setState(() => _sending = true);

    try {
      final caption = _captionController.text.trim();

      await _chatService.sendImageToMultipleDestinations(
        contactUserIds: _selectedContactUserIds.toList(),
        conversationIds: _selectedConversationIds.toList(),
        imagePath: widget.imagePath,
        caption: caption.isNotEmpty ? caption : null,
      );

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedCount == 1
                  ? 'Foto enviada al contacto.'
                  : 'Foto enviada a $_selectedCount contactos.',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error sending photo: $e\n$stack');
      if (mounted) {
        setState(() => _sending = false);
        final cleanMsg = e
            .toString()
            .replaceAll('Exception:', '')
            .replaceAll('PostgrestException', '')
            .trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cleanMsg.isNotEmpty
                ? cleanMsg
                : 'No se pudo enviar la foto. Intenta de nuevo.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredConversations = _conversations.where((c) {
      if (query.isEmpty) return true;
      return c.title.toLowerCase().contains(query);
    }).toList();

    final knownPartnerNames =
        _conversations.map((c) => c.title.toLowerCase()).toSet();
    final filteredContacts = _contacts.where((c) {
      if (query.isEmpty) return true;
      final name = c.displayName.toLowerCase();
      final user = (c.username ?? '').toLowerCase();
      return name.contains(query) || user.contains(query);
    }).where((c) {
      // Evitar duplicar en la lista si ya aparece en conversaciones recientes
      return !knownPartnerNames.contains(c.displayName.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCount == 0
              ? 'Enviar a...'
              : '$_selectedCount seleccionado${_selectedCount > 1 ? 's' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Buscar contacto o chat...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceRaised,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Listado de destinatarios
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      if (filteredConversations.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: Text(
                            'Chats recientes',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ...filteredConversations.map((conv) {
                          final isSelected =
                              _selectedConversationIds.contains(conv.id);
                          return ListTile(
                            onTap: () => _toggleConversation(conv.id),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.surfaceRaised,
                              backgroundImage: conv.avatarUrl != null &&
                                      conv.avatarUrl!.isNotEmpty
                                  ? NetworkImage(conv.avatarUrl!)
                                  : null,
                              child: conv.avatarUrl == null ||
                                      conv.avatarUrl!.isEmpty
                                  ? Text(
                                      conv.title.characters.first.toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Text(
                              conv.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              conv.lastMessage ?? 'Conversación activa',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 13),
                            ),
                            trailing:
                                _SelectionCheckCircle(isSelected: isSelected),
                          );
                        }),
                      ],
                      if (filteredContacts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                          child: Text(
                            'Otros contactos',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ...filteredContacts.map((contact) {
                          final isSelected =
                              _selectedContactUserIds.contains(contact.id);
                          return ListTile(
                            onTap: () => _toggleContact(contact.id),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.surfaceRaised,
                              backgroundImage: contact.avatarUrl != null &&
                                      contact.avatarUrl!.isNotEmpty
                                  ? NetworkImage(contact.avatarUrl!)
                                  : null,
                              child: contact.avatarUrl == null ||
                                      contact.avatarUrl!.isEmpty
                                  ? Text(
                                      contact.displayName.characters.first
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Text(
                              contact.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: contact.username != null
                                ? Text(
                                    '@${contact.username}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  )
                                : null,
                            trailing:
                                _SelectionCheckCircle(isSelected: isSelected),
                          );
                        }),
                      ],
                      if (filteredConversations.isEmpty &&
                          filteredContacts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No se encontraron contactos para enviar la foto.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      // Barra inferior persistente de envío con miniatura y botón
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Miniatura de la foto
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(widget.imagePath),
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              // Campo de comentario
              Expanded(
                child: TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Añade un comentario...',
                    hintStyle:
                        TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Botón circular de envío
              InkWell(
                onTap: _selectedCount > 0 && !_sending ? _sendPhoto : null,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient:
                        _selectedCount > 0 ? AppColors.brandGradient : null,
                    color: _selectedCount == 0 ? AppColors.surfaceRaised : null,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _selectedCount > 0
                                ? Colors.white
                                : AppColors.textSecondary,
                            size: 22,
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

class _SelectionCheckCircle extends StatelessWidget {
  const _SelectionCheckCircle({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isSelected ? AppColors.brandGradient : null,
        border: Border.all(
          color: isSelected
              ? Colors.transparent
              : AppColors.textSecondary.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(
              Icons.check,
              size: 16,
              color: Colors.white,
            )
          : null,
    );
  }
}
