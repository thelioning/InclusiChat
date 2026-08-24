import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active call flow avoids predictable public broadcast channels', () {
    final home = File(
      'lib/src/features/chat/presentation/chat_home_page.dart',
    ).readAsStringSync();
    final callScreen = File(
      'lib/src/features/chat/presentation/call_screen.dart',
    ).readAsStringSync();

    expect(home, isNot(contains('CallSignalingService')));
    expect(callScreen, isNot(contains('CallSignalingService')));
    expect(callScreen, contains('_callService.startCall'));
    expect(callScreen, contains('_callService.acceptCall'));
  });
}
