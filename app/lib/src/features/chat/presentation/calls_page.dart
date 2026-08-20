import 'dart:async';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../calls/data/call_service.dart';
import '../data/chat_service.dart';
import 'call_screen.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final _chatService = ChatService();
  final _callService = CallService();
  List<ContactProfile> _contacts = [];
  List<CallRecord> _callHistory = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData(initial: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadData(initial: false));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool initial = false}) async {
    if (initial && mounted) setState(() => _isLoading = true);
    try {
      final contactsFuture = _chatService.loadContacts();
      final historyFuture = _callService.loadCallHistory();
      final results = await Future.wait([contactsFuture, historyFuture]);

      if (mounted) {
        setState(() {
          _contacts = results[0] as List<ContactProfile>;
          _callHistory = results[1] as List<CallRecord>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && initial) setState(() => _isLoading = false);
    }
  }

  void _startCall({
    required String contactName,
    String? avatarUrl,
    required String receiverUserId,
    String? conversationId,
    required CallType type,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          contactName: contactName,
          avatarUrl: avatarUrl,
          receiverUserId: receiverUserId,
          conversationId: conversationId,
          callType: type,
        ),
      ),
    ).then((_) => _loadData(initial: false));
  }

  void _openNewCallSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (_contacts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline_rounded, size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                const Text(
                  'No tienes contactos agregados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Agrega contactos en la pestaña "Contactos" para iniciar llamadas seguras.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  'Nueva llamada segura',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.secondary,
                        backgroundImage: contact.avatarUrl != null && contact.avatarUrl!.isNotEmpty
                            ? NetworkImage(contact.avatarUrl!)
                            : null,
                        child: contact.avatarUrl == null || contact.avatarUrl!.isEmpty
                            ? Text(
                                contact.displayName.isNotEmpty
                                    ? contact.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              )
                            : null,
                      ),
                      title: Text(contact.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('@${contact.username}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call_rounded, color: AppColors.primary),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _startCall(
                                contactName: contact.displayName,
                                avatarUrl: contact.avatarUrl,
                                receiverUserId: contact.id,
                                type: CallType.audio,
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _startCall(
                                contactName: contact.displayName,
                                avatarUrl: contact.avatarUrl,
                                receiverUserId: contact.id,
                                type: CallType.video,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCallDate(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (isToday) return 'Hoy, $hour:$minute';
    return '${local.day}/${local.month}, $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _loadData(initial: false),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Banner de Cifrado E2EE
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tus llamadas y videollamadas están protegidas con cifrado de extremo a extremo.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade300,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Historial de llamadas recientes (si hay)
            if (_callHistory.isNotEmpty) ...[
              const Text(
                'Llamadas recientes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              ..._callHistory.map((call) {
                final isMissed = call.status == 'missed' || call.status == 'rejected';
                final iconColor = isMissed
                    ? AppColors.error
                    : (call.isOutgoing ? AppColors.primary : AppColors.success);

                final statusIcon = isMissed
                    ? Icons.call_missed_rounded
                    : (call.isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.surfaceRaised,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.secondary,
                      backgroundImage: call.otherUserAvatar != null && call.otherUserAvatar!.isNotEmpty
                          ? NetworkImage(call.otherUserAvatar!)
                          : null,
                      child: call.otherUserAvatar == null || call.otherUserAvatar!.isEmpty
                          ? Text(
                              call.otherUserName.isNotEmpty ? call.otherUserName[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                            )
                          : null,
                    ),
                    title: Text(
                      call.otherUserName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isMissed ? AppColors.error : Colors.white,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(statusIcon, color: iconColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatCallDate(call.startedAt)} • ${call.formattedDuration}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: 'Llamar de nuevo',
                      icon: Icon(
                        call.callType == 'video' ? Icons.videocam_rounded : Icons.call_rounded,
                        color: AppColors.primary,
                      ),
                      onPressed: () => _startCall(
                        contactName: call.otherUserName,
                        avatarUrl: call.otherUserAvatar,
                        receiverUserId: call.otherUserId,
                        conversationId: call.conversationId,
                        type: call.callType == 'video' ? CallType.video : CallType.audio,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],

            const Text(
              'Contactos para llamar',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),

            if (_contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.phone_missed_rounded, size: 54, color: Colors.grey.shade600),
                      const SizedBox(height: 14),
                      const Text(
                        'Aún no tienes contactos para llamar',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Conéctate con otros usuarios mediante su @alias para realizar llamadas de audio y video seguras.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._contacts.map((contact) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.surfaceRaised,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.secondary,
                      backgroundImage: contact.avatarUrl != null && contact.avatarUrl!.isNotEmpty
                          ? NetworkImage(contact.avatarUrl!)
                          : null,
                      child: contact.avatarUrl == null || contact.avatarUrl!.isEmpty
                          ? Text(
                              contact.displayName.isNotEmpty ? contact.displayName[0].toUpperCase() : '?',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                            )
                          : null,
                    ),
                    title: Text(
                      contact.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '@${contact.username}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Llamada de voz',
                          icon: const Icon(Icons.call_rounded, color: AppColors.primary),
                          onPressed: () => _startCall(
                            contactName: contact.displayName,
                            avatarUrl: contact.avatarUrl,
                            receiverUserId: contact.id,
                            type: CallType.audio,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Videollamada',
                          icon: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                          onPressed: () => _startCall(
                            contactName: contact.displayName,
                            avatarUrl: contact.avatarUrl,
                            receiverUserId: contact.id,
                            type: CallType.video,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _openNewCallSheet,
        tooltip: 'Nueva llamada',
        child: const Icon(Icons.add_call, color: Colors.white),
      ),
    );
  }
}
