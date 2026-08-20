import 'package:flutter/services.dart';
import 'call_manager.dart';

class CallAudioService {
  static const MethodChannel _channel = MethodChannel('com.inclusichat/ringtone');
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingCallFromNotification') {
        final args = call.arguments;
        if (args is Map) {
          final callId = args['call_id']?.toString() ?? '';
          final callerName = args['caller_name']?.toString() ?? 'Contacto';
          final callerId = args['caller_id']?.toString();
          final conversationId = args['conversation_id']?.toString();

          CallManager.instance.showIncomingCall(
            callId: callId,
            callerName: callerName,
            callerId: callerId,
            conversationId: conversationId,
            callType: 'audio',
          );
        }
      }
    });
  }

  /// Inicia el servicio persistente nativo en segundo plano
  static Future<void> startBackgroundCallService({
    required String userId,
    required String? authToken,
    required String supabaseUrl,
    required String apiKey,
  }) async {
    try {
      initialize();
      await _channel.invokeMethod('startBackgroundCallService', {
        'userId': userId,
        'authToken': authToken,
        'supabaseUrl': supabaseUrl,
        'apiKey': apiKey,
      });
    } catch (_) {}
  }

  /// Detiene el servicio en segundo plano
  static Future<void> stopBackgroundCallService() async {
    try {
      await _channel.invokeMethod('stopBackgroundCallService');
    } catch (_) {}
  }

  /// Inicia el timbre oficial, vibración del hardware y notificación prioritaria con despertar de pantalla
  static Future<void> startIncomingRinging({String callerName = 'Contacto'}) async {
    try {
      await _channel.invokeMethod('startIncomingRinging', {'callerName': callerName});
    } catch (_) {}
  }

  /// Detiene el timbre, vibración y cancela la notificación de llamada
  static Future<void> stopIncomingRinging() async {
    try {
      await _channel.invokeMethod('stopIncomingRinging');
    } catch (_) {}
  }

  /// Inicia el tono de repique saliente ("Tuuu... tuuu...")
  static Future<void> startOutgoingDialTone() async {
    try {
      await _channel.invokeMethod('startOutgoingDialTone');
    } catch (_) {}
  }

  /// Detiene el tono de repique saliente
  static Future<void> stopOutgoingDialTone() async {
    try {
      await _channel.invokeMethod('stopOutgoingDialTone');
    } catch (_) {}
  }

  /// Trae la aplicación al frente si está en segundo plano
  static Future<void> bringAppToFront() async {
    try {
      await _channel.invokeMethod('bringAppToFront');
    } catch (_) {}
  }
}
