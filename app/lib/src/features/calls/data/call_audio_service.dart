import 'package:flutter/services.dart';

class CallAudioService {
  static const MethodChannel _channel =
      MethodChannel('com.inclusichat/ringtone');

  /// Inicia el timbre oficial, vibración del hardware y notificación prioritaria con despertar de pantalla
  static Future<void> startIncomingRinging(
      {String callerName = 'Contacto'}) async {
    try {
      await _channel
          .invokeMethod('startIncomingRinging', {'callerName': callerName});
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
