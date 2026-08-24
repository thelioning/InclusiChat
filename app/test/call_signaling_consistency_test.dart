import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outgoing screen and persisted signal use the same call id', () {
    final screen = File('lib/src/features/chat/presentation/call_screen.dart')
        .readAsStringSync();
    final service = File('lib/src/features/calls/data/call_service.dart')
        .readAsStringSync();

    expect(screen, contains('callId: _activeCallId'));
    expect(screen, contains('await _callService.startCall'));
    expect(service, contains('required String callId'));
    expect(
      service,
      isNot(contains("final callId = 'call_\${DateTime.now()")),
    );
  });

  test('both ringing sides expire and terminal operations are awaited', () {
    final screen = File('lib/src/features/chat/presentation/call_screen.dart')
        .readAsStringSync();

    expect(screen, contains('_expireOutgoingCall'));
    expect(screen, contains('_expireIncomingCall'));
    expect(screen, contains('Future<void> _answerCall() async'));
    expect(screen, contains('Future<void> _rejectIncomingCall() async'));
    expect(screen, contains('Future<void> _endCall() async'));
  });

  test('database migration provides indexed call metadata', () {
    final migration = File(
      '../supabase/migrations/20260820_004_call_signal_metadata.sql',
    ).readAsStringSync();

    expect(migration, contains('add column if not exists metadata jsonb'));
    expect(migration, contains('messages_call_signal_lookup_idx'));
    expect(migration, contains("notify pgrst, 'reload schema'"));
  });
}
