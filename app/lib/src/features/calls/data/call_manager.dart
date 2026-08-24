import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../chat/presentation/call_screen.dart';

class CallManager {
  static final CallManager instance = CallManager._internal();
  CallManager._internal();

  bool isCallActive = false;
  String? currentCallId;

  /// Abre la pantalla de llamada entrante asegurando que nunca se duplique.
  /// Mientras la app está en segundo plano se conserva la interfaz nativa;
  /// la pantalla Flutter solo se abre al estar visible o al aceptar desde
  /// el sistema.
  void showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    String? callerId,
    String? conversationId,
    String callType = 'audio',
    bool acceptedFromSystem = false,
  }) {
    if (!acceptedFromSystem &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (isCallActive || currentCallId == callId) return;

    isCallActive = true;
    currentCallId = callId;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) {
      isCallActive = false;
      currentCallId = null;
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
          acceptedFromSystem: acceptedFromSystem,
        ),
      ),
    )
        .then((_) {
      isCallActive = false;
      currentCallId = null;
    });
  }
}
