import 'package:flutter/material.dart';

import '../../../app.dart';
import '../presentation/call_screen.dart';

class CallManager {
  static final CallManager instance = CallManager._internal();
  CallManager._internal();

  bool isCallActive = false;
  String? currentCallId;

  /// Abre la pantalla de llamada entrante asegurando que nunca se duplique
  void showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    String? callerId,
    String? conversationId,
    String callType = 'audio',
  }) {
    if (isCallActive || currentCallId == callId) return;

    isCallActive = true;
    currentCallId = callId;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      isCallActive = false;
      return;
    }

    nav
        .push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          contactName: callerName,
          avatarUrl: callerAvatar,
          callerId: callerId,
          callId: callId,
          conversationId: conversationId,
          callType: callType == 'video' ? CallType.video : CallType.audio,
          isIncoming: true,
        ),
      ),
    )
        .then((_) {
      isCallActive = false;
      currentCallId = null;
    });
  }
}
