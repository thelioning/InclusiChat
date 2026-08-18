import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import '../data/invite_service.dart';
import 'conversation_page.dart';

class AddContactDialog extends StatefulWidget {
  const AddContactDialog({super.key});

  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  final _searchController = TextEditingController();
  final _chatService = ChatService();
  bool _isSearching = false;
  bool _isSending = false;
  List<ContactProfile> _searchResults = [];
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await _chatService.searchProfiles(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          if (results.isEmpty) {
            _errorMessage = 'No se encontró ningún usuario con ese alias.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Ocurrió un error al buscar.');
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _sendRequest(ContactProfile profile) async {
    if (profile.username == null || profile.username!.isEmpty) return;
    setState(() => _isSending = true);

    try {
      final res = await _chatService.sendContactRequest(profile.username!);
      if (!mounted) return;
      final success = res['success'] as bool? ?? false;
      final message = res['message'] as String? ?? 'Solicitud enviada.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? AppColors.success : AppColors.warning,
        ),
      );

      if (success) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo enviar la solicitud.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Agregar por @alias',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Escribe el alias de usuario único (@usuario) para conectar de forma privada.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _performSearch(),
                      decoration: const InputDecoration(
                        hintText: 'Ej. mariap, alex_dev',
                        prefixText: '@',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSearching ? null : _performSearch,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      backgroundColor: AppColors.primary,
                    ),
                    child: _isSearching
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    InviteService.inviteViaWhatsApp();
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Invitar a tu amigo por WhatsApp'),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _isSearching
                              ? 'Buscando usuarios...'
                              : 'Escribe un alias para buscar o invita a tus amigos.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final profile = _searchResults[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () async {
                              Navigator.of(context).pop(true);
                              try {
                                final convId = await _chatService.createDirectConversation(profile.id);
                                if (context.mounted) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ConversationPage(
                                        conversationId: convId,
                                        title: profile.displayName,
                                        avatarUrl: profile.avatarUrl,
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {}
                            },
                            leading: CircleAvatar(
                              backgroundColor: AppColors.secondary,
                              backgroundImage: profile.avatarUrl != null
                                  ? NetworkImage(profile.avatarUrl!)
                                  : null,
                              child: profile.avatarUrl == null
                                  ? Text(profile.displayName.characters.first.toUpperCase())
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    profile.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (profile.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
                                ],
                              ],
                            ),
                            subtitle: Text('@${profile.username ?? ''} • Toca para chatear'),
                            trailing: OutlinedButton.icon(
                              onPressed: _isSending ? null : () => _sendRequest(profile),
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Conectar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
