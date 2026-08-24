import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application installs top-level error handlers', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('FlutterError.onError'));
    expect(source, contains('PlatformDispatcher.instance.onError'));
    expect(source, contains('runZonedGuarded'));
    expect(source, isNot(contains('SUPABASE_SERVICE_ROLE')));
  });
}
