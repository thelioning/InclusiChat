import 'package:flutter/services.dart';

class CallAudioService {
  static const MethodChannel _channel = MethodChannel('com.inclusichat/ringtone');

  /// Inicia el timbre oficial del sistema y la vibración del hardware para llamada entrante
  static Future<void> startIncomingRinging() async {
    try {
      await _channel.invokeMethod('startIncomingRinging');
    } catch (_) {}
  }

  /// Detiene el timbre y la vibración de llamada entrante
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
}
