import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import '../data/invite_service.dart';
import 'add_contact_dialog.dart';
import 'conversation_page.dart';

import 'dart:async';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final _chatService = ChatService();
  late Future<List<ContactProfile>> _contactsFuture;
  late Future<List<ContactRequestItem>> _requestsFuture;
  String _searchFilter = '';
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() {
          _requestsFuture = _chatService.loadContactRequests();
          _contactsFuture = _chatService.loadContacts();
        });
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _contactsFuture = _chatService.loadContacts();
      _requestsFuture = _chatService.loadContactRequests();
    });
  }

  Future<void> _showAddContactDialog() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (_) => const AddContactDialog(),
    );
    if (!mounted) return;
    if (result is ContactProfile) {
      _loadData();
      _openChat(result);
    } else if (result != null) {
      _loadData();
    }
  }

  Future<void> _acceptRequest(ContactRequestItem request) async {
    final success = await _chatService.acceptContactRequest(request.id);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ahora estás conectado con ${request.profile.displayName}.'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo aceptar la solicitud.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _rejectRequest(ContactRequestItem request) async {
    final success = await _chatService.rejectContactRequest(request.id);
    if (!mounted) return;
    if (success) {
      _loadData();
    }
  }

  Future<void> _openChat(ContactProfile contact) async {
    try {
      final conversationId = await _chatService.createDirectConversation(contact.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationPage(
            conversationId: conversationId,
            title: contact.displayName,
            avatarUrl: contact.avatarUrl,
          ),
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      final clean = e.toString().replaceAll('Exception:', '').replaceAll('PostgrestException', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(clean.isNotEmpty ? clean : 'No se pudo abrir la conversación.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmRemoveContact(ContactProfile contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar contacto'),
        content: Text('¿Deseas eliminar a ${contact.displayName} de tus contactos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _chatService.removeContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacto eliminado.'),
            backgroundColor: AppColors.surfaceRaised,
          ),
        );
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _loadData(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) => setState(() => _searchFilter = value.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: 'Buscar en mis contactos',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Agregar contacto',
                    onPressed: _showAddContactDialog,
                    icon: const Icon(Icons.person_add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2E23),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF25D366),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invitar amigos por WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Comparte tu @alias para chatear seguro',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => InviteService.inviteViaWhatsApp(),
                    child: const Text('Invitar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          // Sección de solicitudes pendientes
          SliverToBoxAdapter(
            child: FutureBuilder<List<ContactRequestItem>>(
              future: _requestsFuture,
              builder: (context, snapshot) {
                final requests = snapshot.data ?? [];
                final incoming = requests.where((r) => r.isIncoming).toList();
                final outgoing = requests.where((r) => !r.isIncoming).toList();
                if (incoming.isEmpty && outgoing.isEmpty) return const SizedBox.shrink();

                return Column(
                  children: [
                    if (incoming.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Solicitudes recibidas (${incoming.length})',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: incoming.length,
                              separatorBuilder: (_, __) => const Divider(height: 12),
                              itemBuilder: (context, idx) {
                                final req = incoming[idx];
                                return Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppColors.secondary,
                                      child: Text(req.profile.displayName.characters.first.toUpperCase()),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            req.profile.displayName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                          if (req.profile.username != null)
                                            Text(
                                              '@${req.profile.username}',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      tooltip: 'Aceptar',
                                      onPressed: () => _acceptRequest(req),
                                      icon: const Icon(Icons.check_rounded, color: AppColors.success, size: 20),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton.filledTonal(
                                      tooltip: 'Rechazar',
                                      onPressed: () => _rejectRequest(req),
                                      icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    if (outgoing.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.outbox_rounded, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Solicitudes enviadas (${outgoing.length})',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: outgoing.length,
                              separatorBuilder: (_, __) => const Divider(height: 12),
                              itemBuilder: (context, idx) {
                                final req = outgoing[idx];
                                return Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppColors.surface,
                                      child: Text(req.profile.displayName.characters.first.toUpperCase()),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            req.profile.displayName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                          if (req.profile.username != null)
                                            Text(
                                              '@${req.profile.username} • Esperando aceptación',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                            ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _openChat(req.profile),
                                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                                      label: const Text('Chatear'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // Lista de contactos
          FutureBuilder<List<ContactProfile>>(
            future: _contactsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 48),
                        const SizedBox(height: 12),
                        const Text('No se pudieron cargar tus contactos.'),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _loadData, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                );
              }

              final allContacts = snapshot.data ?? [];
              final filtered = _searchFilter.isEmpty
                  ? allContacts
                  : allContacts.where((c) =>
                      c.displayName.toLowerCase().contains(_searchFilter) ||
                      (c.username != null && c.username!.toLowerCase().contains(_searchFilter))).toList();

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              gradient: AppColors.brandGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.people_outline_rounded, size: 40, color: Colors.white),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _searchFilter.isEmpty ? 'Tu círculo está esperando' : 'Sin coincidencias',
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchFilter.isEmpty
                                ? 'Agrega personas usando su @alias único para construir tu espacio seguro.'
                                : 'No se encontraron contactos con "$_searchFilter".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          if (_searchFilter.isEmpty) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _showAddContactDialog,
                              icon: const Icon(Icons.person_add_rounded),
                              label: const Text('Agregar primer contacto'),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final contact = filtered[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
                        child: contact.avatarUrl == null
                            ? Text(
                                contact.displayName.characters.first.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                          if (contact.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
                          ],
                        ],
                      ),
                      subtitle: contact.username != null ? Text('@${contact.username}') : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Mensaje directo',
                            icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
                            onPressed: () => _openChat(contact),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'remove') _confirmRemoveContact(contact);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'remove',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_remove_outlined, color: AppColors.error),
                                    SizedBox(width: 10),
                                    Text('Eliminar contacto', style: TextStyle(color: AppColors.error)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _openChat(contact),
                    );
                  },
                  childCount: filtered.length,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
