import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CamouflageService extends ChangeNotifier {
  CamouflageService._internal() {
    _loadFromPrefs();
  }
  static final CamouflageService instance = CamouflageService._internal();

  bool _isCamouflaged = false;
  bool _isCamouflageFeatureActive = false;
  String _camouflageType = 'calculator';
  String _pin = '';
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  static const _secureStorage = FlutterSecureStorage();
  static const _securePinKey = 'camouflage_pin_v2';

  bool get isCamouflaged => _isCamouflaged;
  bool get isCamouflageFeatureActive => _isCamouflageFeatureActive;
  String get camouflageType => _camouflageType;
  bool get hasSecurePin => _pin.isNotEmpty;
  int get pinLength => _pin.length;
  bool get isDefaultPin => !hasSecurePin;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyPin = prefs.getString('camouflage_pin');
      final securePin = await _secureStorage.read(key: _securePinKey);
      if (securePin != null && securePin.isNotEmpty) {
        _pin = securePin;
      } else if (legacyPin != null &&
          legacyPin != '1234' &&
          RegExp(r'^\d{4,6}$').hasMatch(legacyPin)) {
        _pin = legacyPin;
        await _secureStorage.write(key: _securePinKey, value: legacyPin);
      }
      await prefs.remove('camouflage_pin');
      _isCamouflageFeatureActive =
          (prefs.getBool('camouflage_active') ?? false) && hasSecurePin;
      _camouflageType = prefs.getString('camouflage_type') ?? 'calculator';
      notifyListeners();
    } catch (_) {}
  }

  void triggerCamouflage() {
    if (!_isCamouflageFeatureActive || !hasSecurePin) return;
    _isCamouflaged = true;
    notifyListeners();
  }

  bool unlock(String enteredPin) {
    final now = DateTime.now();
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) return false;
    if (enteredPin.trim() == _pin.trim()) {
      _failedAttempts = 0;
      _lockedUntil = null;
      _isCamouflaged = false;
      notifyListeners();
      return true;
    }
    _failedAttempts += 1;
    if (_failedAttempts >= 5) {
      _failedAttempts = 0;
      _lockedUntil = now.add(const Duration(minutes: 1));
    }
    return false;
  }

  Future<void> configure({
    required bool active,
    required String type,
    required String newPin,
  }) async {
    if (newPin.trim().isNotEmpty &&
        !RegExp(r'^\d{4,6}$').hasMatch(newPin.trim())) {
      throw const FormatException('El PIN debe contener entre 4 y 6 dígitos.');
    }
    _camouflageType = type;
    if (newPin.trim().isNotEmpty) {
      _pin = newPin.trim();
      await _secureStorage.write(key: _securePinKey, value: _pin);
    }
    _isCamouflageFeatureActive = active && hasSecurePin;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('camouflage_active', _isCamouflageFeatureActive);
      await prefs.remove('camouflage_pin');
      await prefs.setString('camouflage_type', _camouflageType);
    } catch (_) {}
  }
}
