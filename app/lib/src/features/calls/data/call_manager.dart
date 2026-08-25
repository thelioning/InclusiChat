import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../chat/presentation/call_screen.dart';

class _PendingIncomingCall {
  const _PendingIncomingCall({
    required this.callId,
    required this.callerName,
    this.callerAvatar,
    this.callerId,
    this.conversationId,
    required this.callType,
    required this.acceptedFromSystem,
  });

  final String callId;
  final String callerName;
  final String? callerAvatar;
  final String? callerId;
  final String? conversationId;
  final String callType;
  final bool acceptedFromSystem;
}

class CallManager {
  static final CallManager instance = CallManager._internal();
  CallManager._internal();

  bool isCallActive = false;
  String? currentCallId;
  Timer? _pendingOpenTimer;
  _PendingIncomingCall? _pendingCall;

  /// Abre la pantalla de llamada entrante asegurando que nunca se duplique.
  /// Mientras la app está en segundo plano se conserva la interfaz nativa.
  /// Si el usuario acepta desde Android, la llamada se mantiene pendiente hasta
  /// que Flutter vuelva a estar visible y el Navigator se haya reconstruido.
  void showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    String? callerId,
    String? conversationId,
    String callType = 'audio',
    bool acceptedFromSystem = false,
  }) {
    if (isCallActive || currentCallId == callId) return;

    final request = _PendingIncomingCall(
      callId: callId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      callerId: callerId,
      conversationId: conversationId,
      callType: callType,
      acceptedFromSystem: acceptedFromSystem,
    );

    if (_tryOpen(request)) return;
    if (acceptedFromSystem) {
      _queueUntilFlutterReady(request);
    }
  }

  bool _tryOpen(_PendingIncomingCall request) {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    if (isCallActive || currentCallId == request.callId) return true;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) return false;

    isCallActive = true;
    currentCallId = request.callId;

    nav
        .push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          contactName: request.callerName,
          avatarUrl: request.callerAvatar,
          callerId: request.callerId,
          callId: request.callId,
          conversationId: request.conversationId,
          callType:
              request.callType == 'video' ? CallType.video : CallType.audio,
          isIncoming: true,
          acceptedFromSystem: request.acceptedFromSystem,
        ),
      ),
    )
        .then((_) {
      isCallActive = false;
      currentCallId = null;
    });
    return true;
  }

  void _queueUntilFlutterReady(_PendingIncomingCall request) {
    _pendingCall = request;
    _pendingOpenTimer?.cancel();
    final startedAt = DateTime.now();

    _pendingOpenTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (timer) {
        final pending = _pendingCall;
        if (pending == null) {
          timer.cancel();
          _pendingOpenTimer = null;
          return;
        }

        if (_tryOpen(pending)) {
          _pendingCall = null;
          timer.cancel();
          _pendingOpenTimer = null;
          return;
        }

        if (DateTime.now().difference(startedAt) > const Duration(seconds: 8)) {
          _pendingCall = null;
          timer.cancel();
          _pendingOpenTimer = null;
        }
      },
    );
  }
}
