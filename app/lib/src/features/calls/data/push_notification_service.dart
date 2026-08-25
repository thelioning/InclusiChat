import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'background_supabase.dart';
import 'call_manager.dart';
import 'call_service.dart';
import 'native_call_notification_service.dart';

const _pushOwnerKey = 'inclusichat_push_owner_user_id';
const _pushTokenKey = 'inclusichat_push_registered_token';
const FlutterSecureStorage _pushSecureStorage = FlutterSecureStorage();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['event'] != 'incoming_call') return;

  try {
    final ownerUserId = await _pushSecureStorage.read(key: _pushOwnerKey);
    if (ownerUserId == null || ownerUserId.isEmpty) return;

    final receiverId = message.data['receiver_id'];
    if (receiverId != null &&
        receiverId.isNotEmpty &&
        receiverId != ownerUserId) {
      return;
    }
  } catch (error, stack) {
    debugPrint('Push owner validation failed: $error\n$stack');
    return;
  }

  await showNativeIncomingCall(message.data);
  await _watchBackgroundCallState(message.data);
}

@pragma('vm:entry-point')
Future<void> _watchBackgroundCallState(Map<String, dynamic> data) async {
  final callId = data['call_id']?.toString();
  final conversationId = data['conversation_id']?.toString();
  if (callId == null ||
      callId.isEmpty ||
      conversationId == null ||
      conversationId.isEmpty) {
    return;
  }

  if (!await ensureBackgroundSupabase()) return;

  // Firebase background work should stay short. The native CallKit timeout
  // remains the final 35-second safety net; this watcher covers the period in
  // which the remote caller is most likely to cancel while Android is locked.
  // Do not stop watching after accept: the remote side may end the call before
  // the foreground Flutter screen has finished restoring.
  final deadline = DateTime.now().add(const Duration(seconds: 28));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final action = await CallService().getCallSignalState(
        conversationId: conversationId,
        callId: callId,
      );
      if (action == 'end' || action == 'reject') {
        await NativeCallNotificationService.endFromRemote(callId);
        return;
      }
    } catch (error, stack) {
      debugPrint('Background call state check failed: $error\n$stack');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static Future<void>? _initializing;
  static bool _initialized = false;
  static String? _initializedUserId;
  static String? _registeredToken;

  static Future<void> initializeForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await reset();
      return;
    }

    if (_initialized && _initializedUserId == user.id) return;

    final inFlight = _initializing;
    if (inFlight != null) {
      await inFlight;
      if (_initialized && _initializedUserId == user.id) return;
    }

    final future = _initializeForUser(user.id);
    _initializing = future;
    try {
      await future;
    } finally {
      if (identical(_initializing, future)) _initializing = null;
    }
  }

  static Future<void> _initializeForUser(String userId) async {
    final persistedOwner = await _pushSecureStorage.read(key: _pushOwnerKey);
    final inMemoryOwner = _initializedUserId;

    if ((persistedOwner != null && persistedOwner != userId) ||
        (inMemoryOwner != null && inMemoryOwner != userId)) {
      await reset();
      await _clearPersistedOwnership();
      try {
        await _messaging.deleteToken();
      } catch (error, stack) {
        debugPrint('FCM stale token invalidation failed: $error\n$stack');
      }
    } else if (_initialized) {
      await reset();
    }

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser?.id != userId) return;

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await NativeCallNotificationService.initialize();

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      final saved = await _saveToken(token, userId);
      if (saved) _registeredToken = token;
    }

    _tokenSubscription = _messaging.onTokenRefresh.listen(
      (newToken) async {
        final activeUser = Supabase.instance.client.auth.currentUser;
        if (!_initialized ||
            activeUser == null ||
            activeUser.id != _initializedUserId) {
          return;
        }

        final previousToken = _registeredToken ??
            await _pushSecureStorage.read(key: _pushTokenKey);
        final saved = await _saveToken(newToken, activeUser.id);
        if (!saved) return;

        _registeredToken = newToken;
        if (previousToken != null &&
            previousToken.isNotEmpty &&
            previousToken != newToken) {
          await _deleteBackendToken(previousToken, activeUser.id);
        }
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('FCM token refresh failed: $error');
      },
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_openCall);
    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_openCall);

    _initializedUserId = userId;
    _initialized = true;

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      await _openCall(initialMessage);
    }
  }

  static Future<bool> _saveToken(String token, String userId) async {
    try {
      final activeUser = Supabase.instance.client.auth.currentUser;
      if (activeUser?.id != userId) return false;

      await Supabase.instance.client.from('device_push_tokens').upsert({
        'token': token,
        'user_id': userId,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      await _pushSecureStorage.write(key: _pushOwnerKey, value: userId);
      await _pushSecureStorage.write(key: _pushTokenKey, value: token);
      return true;
    } catch (error, stack) {
      debugPrint('FCM token registration failed: $error\n$stack');
      return false;
    }
  }

  static Future<bool> _deleteBackendToken(
    String token,
    String userId,
  ) async {
    try {
      await Supabase.instance.client
          .from('device_push_tokens')
          .delete()
          .eq('token', token)
          .eq('user_id', userId);
      return true;
    } catch (error, stack) {
      debugPrint('FCM token backend removal failed: $error\n$stack');
      return false;
    }
  }

  static Future<void> _openCall(RemoteMessage message) async {
    final data = message.data;
    if (data['event'] != 'incoming_call') return;

    final activeUser = Supabase.instance.client.auth.currentUser;
    if (activeUser == null) return;
    final receiverId = data['receiver_id'];
    if (receiverId != null &&
        receiverId.isNotEmpty &&
        receiverId != activeUser.id) {
      return;
    }

    final callId = data['call_id'];
    final conversationId = data['conversation_id'];
    if (callId == null || callId.isEmpty || conversationId == null) return;

    try {
      final action = await CallService().getCallSignalState(
        conversationId: conversationId,
        callId: callId,
      );
      if (action == 'end' || action == 'reject') return;
    } catch (error, stack) {
      debugPrint('Incoming call preflight failed: $error\n$stack');
    }

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

  static Future<void> prepareForSignOut() async {
    final user = Supabase.instance.client.auth.currentUser;
    final persistedToken = await _pushSecureStorage.read(key: _pushTokenKey);
    String? token = _registeredToken ?? persistedToken;

    if (token == null || token.isEmpty) {
      try {
        token = await _messaging.getToken();
      } catch (error, stack) {
        debugPrint('FCM token lookup during logout failed: $error\n$stack');
      }
    }

    await _clearPersistedOwnership();

    var backendDetached = user == null || token == null || token.isEmpty;
    if (!backendDetached) {
      backendDetached = await _deleteBackendToken(token, user.id);
    }

    await reset();

    var firebaseInvalidated = false;
    try {
      await _messaging.deleteToken();
      firebaseInvalidated = true;
    } catch (error, stack) {
      debugPrint('FCM token invalidation during logout failed: $error\n$stack');
    }

    if (!backendDetached && !firebaseInvalidated) {
      throw StateError(
        'No se pudo desvincular este dispositivo de las notificaciones.',
      );
    }
  }

  static Future<void> _clearPersistedOwnership() async {
    await _pushSecureStorage.delete(key: _pushOwnerKey);
    await _pushSecureStorage.delete(key: _pushTokenKey);
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
