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

  String get _currentUserId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('No authenticated user');
    return id;
  }

  /// Carga el historial de llamadas del usuario autenticado
  Future<List<CallRecord>> loadCallHistory() async {
    try {
      final uid = _currentUserId;
      final rows = await _client
          .from('call_records')
          .select('''
            id,
            caller_id,
            receiver_id,
            conversation_id,
            call_type,
            status,
            duration_seconds,
            started_at,
            caller:profiles!call_records_caller_id_fkey(id, display_name, username, avatar_url),
            receiver:profiles!call_records_receiver_id_fkey(id, display_name, username, avatar_url)
          ''')
          .or('caller_id.eq.$uid,receiver_id.eq.$uid')
          .order('started_at', ascending: false)
          .limit(50);

      return (rows as List).map<CallRecord>((row) {
        final isOut = row['caller_id'] == uid;
        final otherProfile = (isOut ? row['receiver'] : row['caller']) as Map?;
        final otherName = (otherProfile?['display_name'] as String?) ??
            (otherProfile?['username'] as String?) ??
            'Contacto';
        final otherAvatar = otherProfile?['avatar_url'] as String?;
        final otherId = (isOut ? row['receiver_id'] : row['caller_id']).toString();

        return CallRecord(
          id: row['id'].toString(),
          callerId: row['caller_id'].toString(),
          receiverId: row['receiver_id'].toString(),
          conversationId: row['conversation_id']?.toString(),
          callType: row['call_type'] as String? ?? 'audio',
          status: row['status'] as String? ?? 'completed',
          durationSeconds: row['duration_seconds'] as int? ?? 0,
          startedAt: DateTime.tryParse(row['started_at'].toString()) ?? DateTime.now(),
          isOutgoing: isOut,
          otherUserName: otherName,
          otherUserAvatar: otherAvatar,
          otherUserId: otherId,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error loading call history: $e');
      return [];
    }
  }

  /// Registra una llamada completada, perdida o rechazada en la base de datos
  Future<void> logCallRecord({
    required String receiverId,
    String? conversationId,
    required String callType,
    required String status,
    required int durationSeconds,
  }) async {
    try {
      final uid = _currentUserId;
      await _client.from('call_records').insert({
        'caller_id': uid,
        'receiver_id': receiverId,
        'conversation_id': conversationId,
        'call_type': callType,
        'status': status,
        'duration_seconds': durationSeconds,
        'started_at': DateTime.now().subtract(Duration(seconds: durationSeconds)).toUtc().toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Si hay una conversación asociada, registrar mensaje del sistema en el chat
      if (conversationId != null && conversationId.isNotEmpty) {
        final durationText = durationSeconds > 0
            ? '${durationSeconds ~/ 60}:${(durationSeconds % 60).toString().padLeft(2, '0')}'
            : '';
        final statusDesc = status == 'completed'
            ? '📞 Llamada de voz finalizada ($durationText)'
            : '📞 Llamada perdida';

        await _client.from('messages').insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'type': 'system',
          'content': statusDesc,
          'metadata': {
            'call_type': callType,
            'call_status': status,
            'duration': durationSeconds,
          },
        });
      }
    } catch (e) {
      debugPrint('Error logging call record: $e');
    }
  }
}
