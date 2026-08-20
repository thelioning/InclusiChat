import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../chat/data/chat_service.dart';

class CallRecord {
  const CallRecord({
    required this.id,
    required this.callerId,
    required this.receiverId,
    this.conversationId,
    required this.callType,
    required this.status,
    required this.durationSeconds,
    required this.startedAt,
    required this.isOutgoing,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.otherUserId,
  });

  final String id;
  final String callerId;
  final String receiverId;
  final String? conversationId;
  final String callType; // 'audio' or 'video'
  final String status; // 'completed', 'missed', 'rejected'
  final int durationSeconds;
  final DateTime startedAt;
  final bool isOutgoing;
  final String otherUserName;
  final String? otherUserAvatar;
  final String otherUserId;

  String get formattedDuration {
    if (durationSeconds <= 0) return '0 seg';
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    if (m == 0) return '$s seg';
    return '$m min $s seg';
  }
}

class CallService {
  CallService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Inicia una llamada enviando un mensaje de señal 'start' en la conversación
  Future<String> startCall({
    required String conversationId,
    required String receiverId,
    required String callType,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('No autenticado');

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Obtener nombre del usuario actual
    String callerName = 'Usuario';
    String? callerAvatar;
    try {
      final myProfile = await ChatService().loadUserProfile();
      callerName = myProfile.displayName;
      callerAvatar = myProfile.avatarUrl;
    } catch (_) {}

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'system',
      'content': '📞 Llamando...',
      'metadata': {
        'call_signal': true,
        'action': 'start',
        'call_id': callId,
        'caller_id': uid,
        'caller_name': callerName,
        'caller_avatar': callerAvatar,
        'receiver_id': receiverId,
        'call_type': callType,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });

    try {
      await _client.from('conversations').update({
        'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}

    return callId;
  }

  /// Acepta la llamada enviando la señal 'accept'
  Future<void> acceptCall({
    required String conversationId,
    required String callId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'system',
      'content': '📞 Llamada aceptada',
      'metadata': {
        'call_signal': true,
        'action': 'accept',
        'call_id': callId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Rechaza la llamada enviando la señal 'reject'
  Future<void> rejectCall({
    required String conversationId,
    required String callId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'system',
      'content': '📞 Llamada rechazada',
      'metadata': {
        'call_signal': true,
        'action': 'reject',
        'call_id': callId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Finaliza la llamada enviando la señal 'end' con resumen
  Future<void> endCall({
    required String conversationId,
    required String callId,
    required int durationSeconds,
    required bool wasConnected,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final durationText = durationSeconds > 0
        ? '${durationSeconds ~/ 60}:${(durationSeconds % 60).toString().padLeft(2, '0')}'
        : '';
    final statusDesc = wasConnected
        ? '📞 Llamada de voz finalizada ($durationText)'
        : '📞 Llamada perdida';

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': 'system',
      'content': statusDesc,
      'metadata': {
        'call_signal': true,
        'action': 'end',
        'call_id': callId,
        'duration': durationSeconds,
        'status': wasConnected ? 'completed' : 'missed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// Consulta el último estado de una llamada en su conversación
  Future<String?> getCallSignalState({
    required String conversationId,
    required String callId,
  }) async {
    try {
      final rows = await _client
          .from('messages')
          .select('metadata,created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(10);

      for (final row in rows as List) {
        final meta = row['metadata'];
        if (meta is Map && meta['call_signal'] == true && meta['call_id'] == callId) {
          final action = meta['action'] as String?;
          if (action != null) return action; // 'start', 'accept', 'reject', 'end'
        }
      }
    } catch (_) {}
    return null;
  }

  /// Busca llamadas entrantes pendientes en todas las conversaciones del usuario
  Future<Map<String, dynamic>?> checkForIncomingCall() async {
    try {
      final uid = currentUserId;
      if (uid == null) return null;

      // Cargar mis conversaciones activas
      final myParts = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', uid)
          .isFilter('left_at', null);

      final myConvIds = (myParts as List)
          .map<String>((r) => r['conversation_id'] as String)
          .toList();

      if (myConvIds.isEmpty) return null;

      // Buscar mensajes de llamada tipo 'start' de otro emisor en los últimos 35 segundos
      final rows = await _client
          .from('messages')
          .select('id, conversation_id, sender_id, metadata, created_at')
          .inFilter('conversation_id', myConvIds)
          .neq('sender_id', uid)
          .eq('type', 'system')
          .order('created_at', ascending: false)
          .limit(15);

      final now = DateTime.now();

      for (final row in rows as List) {
        final meta = row['metadata'];
        if (meta is Map && meta['call_signal'] == true && meta['action'] == 'start') {
          final callId = meta['call_id'] as String?;
          final createdAt = DateTime.tryParse(row['created_at'].toString());
          if (callId != null && createdAt != null) {
            final diffSeconds = now.toUtc().difference(createdAt.toUtc()).inSeconds;
            if (diffSeconds >= 0 && diffSeconds <= 35) {
              // Verificar si ya fue aceptada, rechazada o terminada
              final hasEndedOrAnswered = await _isCallAlreadyHandled(row['conversation_id'] as String, callId);
              if (!hasEndedOrAnswered) {
                return {
                  'call_id': callId,
                  'conversation_id': row['conversation_id'],
                  'caller_id': row['sender_id'],
                  'caller_name': meta['caller_name'] ?? 'Contacto',
                  'caller_avatar': meta['caller_avatar'],
                  'call_type': meta['call_type'] ?? 'audio',
                };
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking incoming call: $e');
    }
    return null;
  }

  Future<bool> _isCallAlreadyHandled(String conversationId, String callId) async {
    try {
      final rows = await _client
          .from('messages')
          .select('metadata')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(8);

      for (final row in rows as List) {
        final meta = row['metadata'];
        if (meta is Map && meta['call_id'] == callId) {
          final action = meta['action'] as String?;
          if (action == 'accept' || action == 'reject' || action == 'end') {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Carga el historial de llamadas a partir de los mensajes de resumen en conversaciones
  Future<List<CallRecord>> loadCallHistory() async {
    try {
      final uid = currentUserId;
      if (uid == null) return [];

      final myParts = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', uid)
          .isFilter('left_at', null);

      final myConvIds = (myParts as List)
          .map<String>((r) => r['conversation_id'] as String)
          .toList();

      if (myConvIds.isEmpty) return [];

      final rows = await _client
          .from('messages')
          .select('''
            id,
            conversation_id,
            sender_id,
            type,
            content,
            metadata,
            created_at,
            sender:profiles!messages_sender_id_fkey(id, display_name, username, avatar_url)
          ''')
          .inFilter('conversation_id', myConvIds)
          .eq('type', 'system')
          .order('created_at', ascending: false)
          .limit(40);

      final List<CallRecord> history = [];

      for (final row in rows as List) {
        final meta = row['metadata'];
        if (meta is Map && meta['call_signal'] == true && meta['action'] == 'end') {
          final isOut = row['sender_id'] == uid;
          final senderProfile = row['sender'] as Map?;
          final senderName = (senderProfile?['display_name'] as String?) ?? 'Contacto';
          final senderAvatar = senderProfile?['avatar_url'] as String?;
          final senderId = row['sender_id'].toString();

          history.add(CallRecord(
            id: row['id'].toString(),
            callerId: senderId,
            receiverId: uid,
            conversationId: row['conversation_id']?.toString(),
            callType: meta['call_type'] as String? ?? 'audio',
            status: meta['status'] as String? ?? 'completed',
            durationSeconds: meta['duration'] as int? ?? 0,
            startedAt: DateTime.tryParse(row['created_at'].toString()) ?? DateTime.now(),
            isOutgoing: isOut,
            otherUserName: senderName,
            otherUserAvatar: senderAvatar,
            otherUserId: senderId,
          ));
        }
      }

      return history;
    } catch (e) {
      debugPrint('Error loading call history from messages: $e');
      return [];
    }
  }
}
