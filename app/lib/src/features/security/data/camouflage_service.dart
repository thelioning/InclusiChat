import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CamouflageService extends ChangeNotifier {
  CamouflageService._internal() {
    _loadFromPrefs();
  }
  static final CamouflageService instance = CamouflageService._internal();

  bool _isCamouflaged = false;
  bool _isCamouflageFeatureActive = true;
  String _camouflageType = 'calculator';
  String _pin = '1234';

  bool get isCamouflaged => _isCamouflaged;
  bool get isCamouflageFeatureActive => _isCamouflageFeatureActive;
  String get camouflageType => _camouflageType;
  String get pin => _pin;
  bool get isDefaultPin => _pin == '1234';

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isCamouflageFeatureActive = prefs.getBool('camouflage_active') ?? true;
      _pin = prefs.getString('camouflage_pin') ?? '1234';
      _camouflageType = prefs.getString('camouflage_type') ?? 'calculator';
      notifyListeners();
    } catch (_) {}
  }

  void triggerCamouflage() {
    _isCamouflaged = true;
    notifyListeners();
  }

  bool unlock(String enteredPin) {
    if (enteredPin.trim() == _pin.trim()) {
      _isCamouflaged = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> configure({
    required bool active,
    required String type,
    required String newPin,
  }) async {
    _isCamouflageFeatureActive = active;
    _camouflageType = type;
    if (newPin.trim().isNotEmpty) {
      _pin = newPin.trim();
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('camouflage_active', _isCamouflageFeatureActive);
      await prefs.setString('camouflage_pin', _pin);
      await prefs.setString('camouflage_type', _camouflageType);
    } catch (_) {}
  }
}
