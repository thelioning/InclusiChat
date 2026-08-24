import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release build never falls back to the debug signing key', () {
    final gradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('Release signing is not configured'));
    expect(File('android/key.properties.example').existsSync(), isTrue);
  });
}
