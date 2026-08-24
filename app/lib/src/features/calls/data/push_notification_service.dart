import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_manager.dart';
import 'call_service.dart';
import 'native_call_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['event'] == 'incoming_call') {
    await showNativeIncomingCall(message.data);
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static bool _initialized = false;
  static String? _initializedUserId;
  static String? _registeredToken;

  static Future<void> initializeForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (_initialized) await reset();
      return;
    }

    if (_initialized && _initializedUserId == user.id) return;
    if (_initialized) await reset();

    _initialized = true;
    _initializedUserId = user.id;

    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      await NativeCallNotificationService.initialize();

      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(token, user.id);
      }

      _tokenSubscription = _messaging.onTokenRefresh.listen(
        (newToken) async {
          final currentUser = Supabase.instance.client.auth.currentUser;
          if (currentUser == null || currentUser.id != _initializedUserId) {
            return;
          }
          await _saveToken(newToken, currentUser.id);
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('FCM token refresh failed: $error');
        },
      );
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_openCall);
      _openedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_openCall);

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        await _openCall(initialMessage);
      }
    } catch (error, stack) {
      debugPrint('FCM initialization failed: $error\n$stack');
      await reset();
    }
  }

  static Future<void> _saveToken(String token, String userId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null ||
        currentUser.id != userId ||
        _initializedUserId != userId) {
      return;
    }

    try {
      await Supabase.instance.client.from('device_push_tokens').upsert({
        'token': token,
        'user_id': userId,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      _registeredToken = token;
    } catch (error, stack) {
      debugPrint('FCM token registration failed: $error\n$stack');
    }
  }

  static Future<void> unregisterCurrentUser({SupabaseClient? client}) async {
    final supabase = client ?? Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id ?? _initializedUserId;

    String? token = _registeredToken;
    if (token == null || token.isEmpty) {
      try {
        token = await _messaging.getToken();
      } catch (error, stack) {
        debugPrint('FCM token lookup during logout failed: $error\n$stack');
      }
    }

    if (userId != null && token != null && token.isNotEmpty) {
      try {
        await supabase
            .from('device_push_tokens')
            .delete()
            .eq('token', token)
            .eq('user_id', userId);
      } catch (error, stack) {
        debugPrint('FCM token unregister failed: $error\n$stack');
      }
    }

    // Invalidating the Firebase token prevents a stale database row from
    // continuing to receive notifications if the network cleanup above fails.
    // A later login obtains a fresh token and registers it for that account.
    try {
      await _messaging.deleteToken();
    } catch (error, stack) {
      debugPrint('FCM token invalidation failed: $error\n$stack');
    }

    try {
      await reset();
    } catch (error, stack) {
      debugPrint('FCM listener reset during logout failed: $error\n$stack');
    }
  }

  static Future<void> _openCall(RemoteMessage message) async {
    final data = message.data;
    if (data['event'] != 'incoming_call') return;

    final receiverId = data['receiver_id']?.toString();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (receiverId != null &&
        receiverId.isNotEmpty &&
        receiverId != currentUserId) {
      debugPrint('Ignoring FCM call intended for a different user.');
      return;
    }

    final callId = data['call_id'];
    final conversationId = data['conversation_id'];
    if (callId == null || callId.isEmpty || conversationId == null) return;

    // A notification can be opened after the caller has already hung up.
    // Verify the persisted signal before presenting a stale call screen.
    try {
      final action = await CallService().getCallSignalState(
        conversationId: conversationId,
        callId: callId,
      );
      if (action == 'end' || action == 'reject') return;
    } catch (error, stack) {
      debugPrint('Incoming call preflight failed: $error\n$stack');
    }

    // The app is already visible and will present its own call screen. Remove
    // any native heads-up left by a background-to-foreground transition so
    // the user sees only one set of working controls.
    await NativeCallNotificationService.end(callId);
    CallManager.instance.showIncomingCall(
      callId: callId,
      callerName: data['caller_name'] ?? 'Contacto',
      callerAvatar: data['caller_avatar'],
      callerId: data['caller_id'],
      conversationId: conversationId,
      callType: data['call_type'] == 'video' ? 'video' : 'audio',
    );
  }

  static Future<void> reset() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
    await NativeCallNotificationService.reset();
    _registeredToken = null;
    _initializedUserId = null;
    _initialized = false;
  }
}
