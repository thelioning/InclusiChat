import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'background_supabase.dart';
import 'call_manager.dart';
import 'call_service.dart';

const MethodChannel _androidBridge = MethodChannel('com.inclusichat/android_bridge');

Future<bool> _isAndroidDeviceLocked() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _androidBridge.invokeMethod<bool>('isDeviceLocked') ?? false;
  } catch (error, stack) {
    debugPrint('Android keyguard state check failed: $error\n$stack');
    return false;
  }
}

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
        isFullScreen: false,
        textAccept: 'Contestar',
        textDecline: 'Rechazar',
      ),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> nativeCallBackgroundHandler(CallEvent event) async {
  if (event is! CallEventActionCallAccept &&
      event is! CallEventActionCallDecline &&
      event is! CallEventActionCallEnded) {
    return;
  }

  if (!await ensureBackgroundSupabase()) return;

  final CallKitParams params;
  if (event is CallEventActionCallAccept) {
    params = event.callKitParams;
  } else if (event is CallEventActionCallDecline) {
    params = event.callKitParams;
  } else {
    params = (event as CallEventActionCallEnded).callKitParams;
  }

  final extra = params.extra ?? const <String, dynamic>{};
  final conversationId = extra['conversation_id']?.toString();
  if (conversationId == null || conversationId.isEmpty) return;

  try {
    if (event is CallEventActionCallAccept) {
      await CallService().acceptCall(
        conversationId: conversationId,
        callId: params.id,
      );
    } else if (event is CallEventActionCallDecline) {
      await CallService().rejectCall(
        conversationId: conversationId,
        callId: params.id,
      );
    } else {
      await CallService().endCall(
        conversationId: conversationId,
        callId: params.id,
        durationSeconds: 0,
        wasConnected: true,
        callType: extra['call_type'] == 'video' ? 'video' : 'audio',
      );
    }
  } catch (error, stack) {
    debugPrint('Background native call action failed: $error\n$stack');
  }
}

class NativeCallNotificationService {
  NativeCallNotificationService._();

  static StreamSubscription<CallEvent?>? _eventSubscription;
  static final Set<String> _programmaticEndIds = <String>{};
  static final Set<String> _acceptedNativeCallIds = <String>{};
  static bool _backgroundHandlerRegistered = false;

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

    if (!_backgroundHandlerRegistered) {
      try {
        await FlutterCallkitIncoming.onBackgroundMessage(
          nativeCallBackgroundHandler,
        );
        _backgroundHandlerRegistered = true;
      } catch (error, stack) {
        debugPrint('CallKit background handler registration failed: $error\n$stack');
      }
    }

    _eventSubscription ??=
        FlutterCallkitIncoming.onEvent.listen(_handleCallEvent);

    await _restoreAcceptedCallIfNeeded();
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

      final deviceLocked = await _isAndroidDeviceLocked();
      if (deviceLocked) {
        // Android owns the visible call surface while the keyguard is active.
        // Keep Flutter behind the PIN and only mark the native call connected.
        try {
          await FlutterCallkitIncoming.setCallConnected(params.id);
        } catch (error, stack) {
          debugPrint('Native locked-call connection update failed: $error\n$stack');
        }
        return;
      }

      try {
        await FlutterCallkitIncoming.hideCallkitIncoming(params);
        await FlutterCallkitIncoming.setCallConnected(params.id);
      } catch (error, stack) {
        debugPrint('Native accepted-call handoff failed: $error\n$stack');
      }

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

  static Future<void> _restoreAcceptedCallIfNeeded() async {
    if (!Platform.isAndroid) return;

    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      for (final params in activeCalls) {
        if (!params.isAccepted) continue;

        final extra = params.extra ?? const <String, dynamic>{};
        final conversationId = extra['conversation_id']?.toString();
        if (conversationId == null || conversationId.isEmpty) continue;

        final action = await CallService().getCallSignalState(
          conversationId: conversationId,
          callId: params.id,
        );
        if (action == 'end' || action == 'reject') {
          await endFromRemote(params.id);
          continue;
        }

        _acceptedNativeCallIds.add(params.id);
        if (await _isAndroidDeviceLocked()) {
          // The native lockscreen activity remains authoritative until Android
          // reports that the keyguard is no longer active.
          return;
        }

        CallManager.instance.showIncomingCall(
          callId: params.id,
          callerName: params.nameCaller ?? 'Contacto',
          callerAvatar: extra['caller_avatar']?.toString(),
          callerId: extra['caller_id']?.toString(),
          conversationId: conversationId,
          callType: extra['call_type'] == 'video' ? 'video' : 'audio',
          acceptedFromSystem: true,
        );
        return;
      }
    } catch (error, stack) {
      debugPrint('Accepted native call restore failed: $error\n$stack');
    }
  }

  static Future<void> end(String callId) async {
    await _endNativeCall(callId);
  }

  static Future<void> endFromRemote(String callId) async {
    try {
      await FlutterCallkitIncoming.silenceEvents();

      if (Platform.isAndroid) {
        try {
          await _androidBridge.invokeMethod<void>('finishIncomingCallUi');
        } catch (error, stack) {
          debugPrint('Android incoming-call UI close failed: $error\n$stack');
        }
      }

      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      for (final call in activeCalls) {
        if (call.id == callId) {
          await FlutterCallkitIncoming.hideCallkitIncoming(call);
        }
      }
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error, stack) {
      debugPrint('Remote native call cleanup failed: $error\n$stack');
    } finally {
      try {
        await FlutterCallkitIncoming.unsilenceEvents();
      } catch (_) {}
    }
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
