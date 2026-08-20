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
  static final CallSignalingService _instance = CallSignalingService._internal();
  factory CallSignalingService() => _instance;
  CallSignalingService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _myChannel;
  Function(IncomingCallEvent)? onIncomingCall;
  Function(String callId)? onCallAccepted;
  Function(String callId)? onCallRejected;
  Function(String callId)? onCallEnded;

  String? get currentUserId => _client.auth.currentUser?.id;

  void initialize({
    Function(IncomingCallEvent)? incomingCallHandler,
    Function(String callId)? callAcceptedHandler,
    Function(String callId)? callRejectedHandler,
    Function(String callId)? callEndedHandler,
  }) {
    if (incomingCallHandler != null) onIncomingCall = incomingCallHandler;
    if (callAcceptedHandler != null) onCallAccepted = callAcceptedHandler;
    if (callRejectedHandler != null) onCallRejected = callRejectedHandler;
    if (callEndedHandler != null) onCallEnded = callEndedHandler;

    final uid = currentUserId;
    if (uid == null) return;

    if (_myChannel != null) {
      _client.removeChannel(_myChannel!);
    }

    final channelName = 'call_signal_$uid';
    _myChannel = _client.channel(channelName);

    _myChannel!
        .onBroadcast(
          event: 'incoming_call',
          callback: (payload) {
            debugPrint('📞 Incoming call signal received: $payload');
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
        .onBroadcast(
          event: 'call_accepted',
          callback: (payload) {
            debugPrint('✅ Call accepted signal received: $payload');
            final callId = payload['call_id']?.toString() ?? '';
            onCallAccepted?.call(callId);
          },
        )
        .onBroadcast(
          event: 'call_rejected',
          callback: (payload) {
            debugPrint('❌ Call rejected signal received: $payload');
            final callId = payload['call_id']?.toString() ?? '';
            onCallRejected?.call(callId);
          },
        )
        .onBroadcast(
          event: 'call_ended',
          callback: (payload) {
            debugPrint('🛑 Call ended signal received: $payload');
            final callId = payload['call_id']?.toString() ?? '';
            onCallEnded?.call(callId);
          },
        )
        .subscribe();
  }

  Future<void> sendIncomingCall({
    required String receiverId,
    required String callId,
    required String callerName,
    String? callerAvatar,
    required String callType,
    String? conversationId,
  }) async {
    try {
      final targetChannel = _client.channel('call_signal_$receiverId');
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
    } catch (e) {
      debugPrint('Error sending incoming_call signal: $e');
    }
  }

  Future<void> sendCallAccepted({
    required String callerId,
    required String callId,
  }) async {
    try {
      final targetChannel = _client.channel('call_signal_$callerId');
      await targetChannel.sendBroadcastMessage(
        event: 'call_accepted',
        payload: {'call_id': callId},
      );
    } catch (e) {
      debugPrint('Error sending call_accepted signal: $e');
    }
  }

  Future<void> sendCallRejected({
    required String callerId,
    required String callId,
  }) async {
    try {
      final targetChannel = _client.channel('call_signal_$callerId');
      await targetChannel.sendBroadcastMessage(
        event: 'call_rejected',
        payload: {'call_id': callId},
      );
    } catch (e) {
      debugPrint('Error sending call_rejected signal: $e');
    }
  }

  Future<void> sendCallEnded({
    required String targetUserId,
    required String callId,
  }) async {
    try {
      final targetChannel = _client.channel('call_signal_$targetUserId');
      await targetChannel.sendBroadcastMessage(
        event: 'call_ended',
        payload: {'call_id': callId},
      );
    } catch (e) {
      debugPrint('Error sending call_ended signal: $e');
    }
  }

  void dispose() {
    if (_myChannel != null) {
      _client.removeChannel(_myChannel!);
      _myChannel = null;
    }
  }
}
