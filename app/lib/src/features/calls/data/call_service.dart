import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final String status; // 'ringing', 'accepted', 'completed', 'missed', 'rejected'
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

  /// Crea una nueva sesión de llamada en estado 'ringing'
  Future<String?> createCallSession({
    required String receiverId,
    String? conversationId,
    required String callType,
  }) async {
    try {
      final uid = currentUserId;
      if (uid == null) return null;

      final res = await _client.from('call_records').insert({
        'caller_id': uid,
        'receiver_id': receiverId,
        'conversation_id': conversationId,
        'call_type': callType,
        'status': 'ringing',
        'duration_seconds': 0,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id').single();

      return res['id']?.toString();
    } catch (e) {
      debugPrint('Error creating call session: $e');
      return null;
    }
  }

  /// Acepta una llamada entrante cambiando su estado a 'accepted'
  Future<void> acceptCall(String callId) async {
    try {
      await _client
          .from('call_records')
          .update({'status': 'accepted'})
          .eq('id', callId);
    } catch (e) {
      debugPrint('Error accepting call: $e');
    }
  }

  /// Rechaza una llamada cambiando su estado a 'rejected'
  Future<void> rejectCall(String callId) async {
    try {
      await _client
          .from('call_records')
          .update({'status': 'rejected', 'ended_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', callId);
    } catch (e) {
      debugPrint('Error rejecting call: $e');
    }
  }

  /// Finaliza una llamada activa registrando la duración y mensaje de resumen
  Future<void> endCall({
    required String callId,
    String? conversationId,
    required String callType,
    required int durationSeconds,
    required bool wasConnected,
  }) async {
    try {
      final status = wasConnected ? 'completed' : 'missed';
      await _client.from('call_records').update({
        'status': status,
        'duration_seconds': durationSeconds,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callId);

      if (conversationId != null && conversationId.isNotEmpty) {
        final durationText = durationSeconds > 0
            ? '${durationSeconds ~/ 60}:${(durationSeconds % 60).toString().padLeft(2, '0')}'
            : '';
        final statusDesc = wasConnected
            ? '📞 Llamada de voz finalizada ($durationText)'
            : '📞 Llamada perdida';

        final uid = currentUserId;
        if (uid != null) {
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
      }
    } catch (e) {
      debugPrint('Error ending call session: $e');
    }
  }

  /// Consulta el estado actual de una llamada por su ID
  Future<String?> getCallStatus(String callId) async {
    try {
      final res = await _client
          .from('call_records')
          .select('status')
          .eq('id', callId)
          .maybeSingle();
      return res?['status'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Escucha llamadas entrantes dirigidas al usuario actual en estado 'ringing'
  Stream<List<Map<String, dynamic>>> incomingCallsStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    return _client
        .from('call_records')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', uid)
        .order('started_at', ascending: false);
  }

  /// Carga el historial de llamadas del usuario autenticado
  Future<List<CallRecord>> loadCallHistory() async {
    try {
      final uid = currentUserId;
      if (uid == null) return [];

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

  /// Consulta el perfil de un usuario por su ID
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      return await _client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }
}
