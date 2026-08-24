import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camouflage PIN is stored with secure storage and has no default', () {
    final source = File(
      'lib/src/features/security/data/camouflage_service.dart',
    ).readAsStringSync();

    expect(source, contains('FlutterSecureStorage'));
    expect(source, contains("String _pin = ''"));
    expect(source, isNot(contains("setString('camouflage_pin'")));
    expect(source, contains("remove('camouflage_pin')"));
    expect(source, contains('_failedAttempts'));
    expect(source, contains('_lockedUntil'));
  });
}
