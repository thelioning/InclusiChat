import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'call_manager.dart';
import 'call_service.dart';

Future<void> showNativeIncomingCall(Map<String, dynamic> data) async {
  final callId = data['call_id']?.toString();
  final conversationId = data['conversation_id']?.toString();
  if (callId == null || callId.isEmpty || conversationId == null) return;

  final callerName = data['caller_name']?.toString() ?? 'Contacto';
  final callerAvatar = data['caller_avatar']?.toString();
  final isVideo = data['call_type'] == 'video';

  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'InclusiChat',
      avatar: callerAvatar,
      handle: isVideo ? 'Videollamada segura' : 'Llamada de voz segura',
      type: isVideo ? 1 : 0,
      duration: 35000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Llamada perdida',
      ),
      extra: Map<String, dynamic>.from(data),
      android: const AndroidParams(
        isCustomNotification: true,
        isCustomSmallExNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#17121D',
        actionColor: '#D218E6',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Llamadas de InclusiChat',
        missedCallNotificationChannelName: 'Llamadas perdidas',
        isShowFullLockedScreen: true,
        isImportant: true,
        isBot: false,
        // Android must first post a high-priority CALL notification. Its
        // full-screen intent can then open the incoming-call activity even
        // when OEM firmware blocks direct background activity launches.
        isFullScreen: false,
        textAccept: 'Contestar',
        textDecline: 'Rechazar',
      ),
    ),
  );
}

class NativeCallNotificationService {
  NativeCallNotificationService._();

  static StreamSubscription<CallEvent?>? _eventSubscription;
  static final Set<String> _programmaticEndIds = <String>{};
  static final Set<String> _acceptedNativeCallIds = <String>{};

  static Future<void> initialize() async {
    if (Platform.isAndroid) {
      try {
        final allowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!allowed) {
          await FlutterCallkitIncoming.requestFullIntentPermission();
        }
      } catch (error) {
        debugPrint('Full-screen call permission check failed: $error');
      }
    }

    _eventSubscription ??=
        FlutterCallkitIncoming.onEvent.listen(_handleCallEvent);
  }

  static Future<void> _handleCallEvent(CallEvent? event) async {
    if (event == null) return;

    if (event is CallEventActionCallAccept) {
      final params = event.callKitParams;
      final extra = params.extra ?? const <String, dynamic>{};
      final conversationId = extra['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) return;

      _acceptedNativeCallIds.add(params.id);
      await CallService().acceptCall(
        conversationId: conversationId,
        callId: params.id,
      );
      await _endNativeCall(params.id, force: true);
      CallManager.instance.showIncomingCall(
        callId: params.id,
        callerName: params.nameCaller ?? 'Contacto',
        callerAvatar: extra['caller_avatar']?.toString(),
        callerId: extra['caller_id']?.toString(),
        conversationId: conversationId,
        callType: extra['call_type'] == 'video' ? 'video' : 'audio',
        acceptedFromSystem: true,
      );
    } else if (event is CallEventActionCallDecline) {
      final params = event.callKitParams;
      if (_programmaticEndIds.remove(params.id)) return;

      _acceptedNativeCallIds.remove(params.id);
      final conversationId = params.extra?['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) return;
      await CallService().rejectCall(
        conversationId: conversationId,
        callId: params.id,
      );
    } else if (event is CallEventActionCallEnded) {
      final params = event.callKitParams;
      if (_programmaticEndIds.remove(params.id)) return;

      final extra = params.extra ?? const <String, dynamic>{};
      final conversationId = extra['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) return;

      final wasConnected = _acceptedNativeCallIds.remove(params.id);
      if (wasConnected) {
        await CallService().endCall(
          conversationId: conversationId,
          callId: params.id,
          durationSeconds: 0,
          wasConnected: true,
          callType: extra['call_type'] == 'video' ? 'video' : 'audio',
        );
      } else {
        await CallService().rejectCall(
          conversationId: conversationId,
          callId: params.id,
        );
      }
    } else if (event is CallEventActionCallTimeout) {
      _acceptedNativeCallIds.remove(event.id);
      await _endNativeCall(event.id, force: true);
    }
  }

  static Future<void> end(String callId) async {
    await _endNativeCall(callId);
  }

  static Future<void> _endNativeCall(
    String callId, {
    bool force = false,
  }) async {
    if (!force &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    _programmaticEndIds.add(callId);
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      debugPrint('Native call cleanup failed: $error');
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _programmaticEndIds.remove(callId);
      });
    }
  }

  static Future<void> reset() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _programmaticEndIds.clear();
    _acceptedNativeCallIds.clear();
  }
}
