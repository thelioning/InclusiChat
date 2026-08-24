import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingCallEvent {
  const IncomingCallEvent({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.callType,
    this.conversationId,
  });

  final String callId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String callType;
  final String? conversationId;
}

class CallSignalingService {
  static final CallSignalingService _instance =
      CallSignalingService._internal();
  factory CallSignalingService() => _instance;
  CallSignalingService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _userCallChannel;
  RealtimeChannel? _activeRoomChannel;

  Function(IncomingCallEvent)? onIncomingCall;
  Function(String callId)? onCallAccepted;
  Function(String callId)? onCallRejected;
  Function(String callId)? onCallEnded;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Inicializa la escucha global de llamadas entrantes para el usuario actual
  void initializeUserChannel({
    required Function(IncomingCallEvent) incomingCallHandler,
  }) {
    onIncomingCall = incomingCallHandler;
    final uid = currentUserId;
    if (uid == null) return;

    if (_userCallChannel != null) {
      _client.removeChannel(_userCallChannel!);
    }

    final channelName = 'user_call_$uid';
    _userCallChannel = _client.channel(
      channelName,
      opts: const RealtimeChannelConfig(self: false),
    );

    _userCallChannel!
        .onBroadcast(
      event: 'incoming_call',
      callback: (payload) {
        debugPrint('📞 [Realtime Broadcast] Incoming call signal: $payload');
        final event = IncomingCallEvent(
          callId: payload['call_id']?.toString() ?? '',
          callerId: payload['caller_id']?.toString() ?? '',
          callerName: payload['caller_name']?.toString() ?? 'Contacto',
          callerAvatar: payload['caller_avatar']?.toString(),
          callType: payload['call_type']?.toString() ?? 'audio',
          conversationId: payload['conversation_id']?.toString(),
        );
        onIncomingCall?.call(event);
      },
    )
        .subscribe((status, error) {
      debugPrint(
          '📡 User call channel ($channelName) status: $status, error: $error');
    });
  }

  /// Conecta a la sala específica de la llamada activa para intercambiar eventos en tiempo real
  void joinCallRoom({
    required String callId,
    Function(String callId)? callAcceptedHandler,
    Function(String callId)? callRejectedHandler,
    Function(String callId)? callEndedHandler,
  }) {
    onCallAccepted = callAcceptedHandler;
    onCallRejected = callRejectedHandler;
    onCallEnded = callEndedHandler;

    if (_activeRoomChannel != null) {
      _client.removeChannel(_activeRoomChannel!);
    }

    final roomName = 'room_call_$callId';
    _activeRoomChannel = _client.channel(
      roomName,
      opts: const RealtimeChannelConfig(self: false),
    );

    _activeRoomChannel!
        .onBroadcast(
          event: 'accept',
          callback: (payload) {
            debugPrint('✅ [Call Room] Accept event: $payload');
            onCallAccepted?.call(payload['call_id']?.toString() ?? callId);
          },
        )
        .onBroadcast(
          event: 'reject',
          callback: (payload) {
            debugPrint('❌ [Call Room] Reject event: $payload');
            onCallRejected?.call(payload['call_id']?.toString() ?? callId);
          },
        )
        .onBroadcast(
          event: 'end',
          callback: (payload) {
            debugPrint('🛑 [Call Room] End event: $payload');
            onCallEnded?.call(payload['call_id']?.toString() ?? callId);
          },
        )
        .subscribe((status, error) {
      debugPrint(
          '📡 Active Call Room ($roomName) status: $status, error: $error');
    });
  }

  /// Envía la señal de llamada entrante al canal personal del destinatario
  Future<void> sendIncomingCallSignal({
    required String receiverId,
    required String callId,
    required String callerName,
    String? callerAvatar,
    required String callType,
    String? conversationId,
  }) async {
    try {
      final targetChannel = _client.channel(
        'user_call_$receiverId',
        opts: const RealtimeChannelConfig(self: true),
      );

      targetChannel.subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await targetChannel.sendBroadcastMessage(
            event: 'incoming_call',
            payload: {
              'call_id': callId,
              'caller_id': currentUserId,
              'caller_name': callerName,
              'caller_avatar': callerAvatar,
              'call_type': callType,
              'conversation_id': conversationId,
            },
          );
          debugPrint(
              '🚀 [Broadcast sent] incoming_call to user_call_$receiverId');
        }
      });
    } catch (e) {
      debugPrint('Error sending incoming call signal: $e');
    }
  }

  /// Envía señal de aceptación dentro de la sala de llamada
  Future<void> sendAcceptSignal(String callId) async {
    try {
      if (_activeRoomChannel != null) {
        await _activeRoomChannel!.sendBroadcastMessage(
          event: 'accept',
          payload: {'call_id': callId},
        );
      }
    } catch (e) {
      debugPrint('Error sending accept signal: $e');
    }
  }

  /// Envía señal de rechazo dentro de la sala de llamada
  Future<void> sendRejectSignal(String callId) async {
    try {
      if (_activeRoomChannel != null) {
        await _activeRoomChannel!.sendBroadcastMessage(
          event: 'reject',
          payload: {'call_id': callId},
        );
      }
    } catch (e) {
      debugPrint('Error sending reject signal: $e');
    }
  }

  /// Envía señal de colgar dentro de la sala de llamada
  Future<void> sendEndSignal(String callId) async {
    try {
      if (_activeRoomChannel != null) {
        await _activeRoomChannel!.sendBroadcastMessage(
          event: 'end',
          payload: {'call_id': callId},
        );
      }
    } catch (e) {
      debugPrint('Error sending end signal: $e');
    }
  }

  void leaveCallRoom() {
    if (_activeRoomChannel != null) {
      _client.removeChannel(_activeRoomChannel!);
      _activeRoomChannel = null;
    }
  }
}
