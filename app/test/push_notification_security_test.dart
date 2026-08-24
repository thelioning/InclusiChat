import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FCM tokens are stored in a self-scoped RLS table', () {
    final migration = File(
      '../supabase/migrations/20260820_005_device_push_tokens.sql',
    ).readAsStringSync();
    expect(migration, contains('enable row level security'));
    expect(migration, contains('user_id = auth.uid()'));
    expect(migration, isNot(contains('using (true)')));
  });

  test('background messaging is registered before the app starts', () {
    final main = File('lib/main.dart').readAsStringSync();
    final service = File(
      'lib/src/features/calls/data/push_notification_service.dart',
    ).readAsStringSync();
    expect(main, contains('FirebaseMessaging.onBackgroundMessage'));
    expect(service, contains("@pragma('vm:entry-point')"));
    expect(service, contains("data['event'] != 'incoming_call'"));
  });

  test('call push function authenticates membership and keeps keys server-side',
      () {
    final function = File(
      '../supabase/functions/send-call-notification/index.ts',
    ).readAsStringSync();
    final callService = File(
      'lib/src/features/calls/data/call_service.dart',
    ).readAsStringSync();
    expect(function, contains('userClient.auth.getUser()'));
    expect(function, contains('Conversation membership denied'));
    expect(function, contains('FIREBASE_SERVICE_ACCOUNT_B64'));
    expect(function, isNot(contains('private_key":')));
    expect(callService, contains("'send-call-notification'"));
  });

  test('background calls use urgent data messages and native call UI', () {
    final function = File(
      '../supabase/functions/send-call-notification/index.ts',
    ).readAsStringSync();
    final pushService = File(
      'lib/src/features/calls/data/push_notification_service.dart',
    ).readAsStringSync();
    final nativeService = File(
      'lib/src/features/calls/data/native_call_notification_service.dart',
    ).readAsStringSync();

    expect(function, contains('priority: "high"'));
    expect(function, contains('ttl: "35s"'));
    expect(function, isNot(contains('notification: {')));
    expect(pushService, contains('showNativeIncomingCall(message.data)'));
    expect(nativeService, contains('isShowFullLockedScreen: true'));
    expect(nativeService, contains('CallEventActionCallAccept'));
    expect(nativeService, contains('CallEventActionCallDecline'));
  });

  test('logout unregisters this device token and resets push listeners', () {
    final pushService = File(
      'lib/src/features/calls/data/push_notification_service.dart',
    ).readAsStringSync();
    final authService = File(
      'lib/src/features/auth/data/auth_service.dart',
    ).readAsStringSync();

    expect(pushService, contains('unregisterCurrentUser'));
    expect(pushService, contains(".from('device_push_tokens')"));
    expect(pushService, contains(".eq('token', token)"));
    expect(pushService, contains(".eq('user_id', userId)"));
    expect(pushService, contains('_messaging.deleteToken()'));
    expect(pushService, contains('await reset()'));
    expect(authService,
        contains('PushNotificationService.unregisterCurrentUser(client: _client)'));
    expect(
      authService.indexOf('PushNotificationService.unregisterCurrentUser'),
      lessThan(authService.indexOf('_client.auth.signOut()')),
    );
  });

  test('push initialization is bound to the authenticated account', () {
    final pushService = File(
      'lib/src/features/calls/data/push_notification_service.dart',
    ).readAsStringSync();
    final function = File(
      '../supabase/functions/send-call-notification/index.ts',
    ).readAsStringSync();

    expect(pushService, contains('_initializedUserId'));
    expect(pushService, contains('_registeredToken'));
    expect(pushService, contains('_initializedUserId == user.id'));
    expect(pushService, contains('currentUser.id != _initializedUserId'));
    expect(pushService, contains("data['receiver_id']"));
    expect(function, contains('receiver_id: body.receiver_id'));
  });
}
