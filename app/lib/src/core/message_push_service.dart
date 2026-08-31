import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pushOwnerKey = 'inclusichat_message_push_owner';
const _pushTokenKey = 'inclusichat_message_push_token';
const _messageChannelId = 'inclusichat_messages_channel';
const _messageChannelName = 'Mensajes de InclusiChat';

bool _backgroundSupabaseInitialized = false;

Future<bool> _ensureBackgroundSupabase() async {
  if (_backgroundSupabaseInitialized) {
    return Supabase.instance.client.auth.currentSession != null;
  }

  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final key = publishableKey.isNotEmpty ? publishableKey : anonKey;
  if (url.isEmpty || key.isEmpty) return false;

  try {
    final session = Supabase.instance.client.auth.currentSession;
    _backgroundSupabaseInitialized = true;
    return session != null;
  } catch (_) {
    // Fresh background Flutter engine.
  }

  try {
    await Supabase.initialize(url: url, publishableKey: key);
    _backgroundSupabaseInitialized = true;
    return Supabase.instance.client.auth.currentSession != null;
  } catch (error, stack) {
    debugPrint('Background Supabase initialization failed: $error\n$stack');
    return false;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['event'] != 'chat_message') return;

  final receiverId = message.data['receiver_id']?.toString();
  final messageId = message.data['message_id']?.toString();
  final conversationId = message.data['conversation_id']?.toString();
  if (receiverId == null ||
      receiverId.isEmpty ||
      messageId == null ||
      messageId.isEmpty ||
      conversationId == null ||
      conversationId.isEmpty) {
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  final ownerUserId = preferences.getString(_pushOwnerKey);
  if (ownerUserId == null || ownerUserId != receiverId) return;

  // La notificación se muestra aunque la restauración de Supabase tarde o
  // falle. El usuario no debe perder el aviso por un problema de sesión local.
  await MessagePushService.showChatNotification(message.data);

  if (!await _ensureBackgroundSupabase()) return;
  final client = Supabase.instance.client;
  final currentUserId = client.auth.currentUser?.id;
  if (currentUserId != receiverId) return;

  try {
    await client.from('message_receipts').upsert({
      'message_id': messageId,
      'user_id': receiverId,
      'status': 'delivered',
      'status_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'message_id,user_id');
  } catch (error, stack) {
    debugPrint('Background delivered receipt failed: $error\n$stack');
  }
}

class MessagePushService {
  MessagePushService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static bool _initialized = false;
  static String? _initializedUserId;
  static bool _localNotificationsInitialized = false;

  static Future<void> initializeForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (_initialized && _initializedUserId == user.id) return;

    await _ensureLocalNotificationsInitialized();

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(token, user.id);
    }

    await _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) async {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;
      await _saveToken(token, currentUser.id);
    });

    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['event'] != 'chat_message') return;
      await _markDeliveredInForeground(message.data);
    });

    _initializedUserId = user.id;
    _initialized = true;
  }

  static Future<void> _saveToken(String token, String userId) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.id != userId) return;

      await Supabase.instance.client.from('device_push_tokens').upsert({
        'token': token,
        'user_id': userId,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pushOwnerKey, userId);
      await preferences.setString(_pushTokenKey, token);
    } catch (error, stack) {
      debugPrint('FCM token registration failed: $error\n$stack');
    }
  }

  static Future<void> _markDeliveredInForeground(
    Map<String, dynamic> data,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    final receiverId = data['receiver_id']?.toString();
    final messageId = data['message_id']?.toString();
    if (user == null ||
        receiverId != user.id ||
        messageId == null ||
        messageId.isEmpty) {
      return;
    }

    try {
      await Supabase.instance.client.from('message_receipts').upsert({
        'message_id': messageId,
        'user_id': user.id,
        'status': 'delivered',
        'status_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'message_id,user_id');
    } catch (error, stack) {
      debugPrint('Foreground delivered receipt failed: $error\n$stack');
    }
  }

  static Future<void> _ensureLocalNotificationsInitialized() async {
    if (_localNotificationsInitialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('mipmap/ic_launcher'),
    );
    await _notifications.initialize(initializationSettings);

    const channel = AndroidNotificationChannel(
      _messageChannelId,
      _messageChannelName,
      description: 'Avisos discretos de mensajes nuevos',
      importance: Importance.high,
      showBadge: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _localNotificationsInitialized = true;
  }

  static Future<void> showChatNotification(
    Map<String, dynamic> data,
  ) async {
    await _ensureLocalNotificationsInitialized();

    final conversationId = data['conversation_id']?.toString() ?? '';
    if (conversationId.isEmpty) return;

    final senderName = data['sender_name']?.toString().trim();
    final messageType = data['message_type']?.toString() ?? 'text';
    final unreadCount = int.tryParse(data['unread_count']?.toString() ?? '') ?? 1;

    final body = switch (messageType) {
      'image' => 'Nueva foto',
      'audio' => 'Nueva nota de voz',
      _ => 'Nuevo mensaje',
    };

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _messageChannelId,
        _messageChannelName,
        channelDescription: 'Avisos discretos de mensajes nuevos',
        importance: Importance.high,
        priority: Priority.high,
        channelShowBadge: true,
        number: unreadCount,
      ),
    );

    await _notifications.show(
      notificationIdForConversation(conversationId),
      senderName == null || senderName.isEmpty ? 'InclusiChat' : senderName,
      body,
      details,
      payload: conversationId,
    );
  }

  static int notificationIdForConversation(String conversationId) {
    var hash = 0;
    for (final unit in conversationId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<void> clearConversationNotification(
    String conversationId,
  ) async {
    await _ensureLocalNotificationsInitialized();
    await _notifications.cancel(notificationIdForConversation(conversationId));
  }

  static Future<void> prepareForSignOut() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_pushTokenKey);
    final user = Supabase.instance.client.auth.currentUser;

    if (token != null && token.isNotEmpty && user != null) {
      try {
        await Supabase.instance.client
            .from('device_push_tokens')
            .delete()
            .eq('token', token)
            .eq('user_id', user.id);
      } catch (error, stack) {
        debugPrint('FCM token backend removal failed: $error\n$stack');
      }
    }

    await preferences.remove(_pushOwnerKey);
    await preferences.remove(_pushTokenKey);
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;
    _initialized = false;
    _initializedUserId = null;

    await _ensureLocalNotificationsInitialized();
    await _notifications.cancelAll();

    try {
      await _messaging.deleteToken();
    } catch (error, stack) {
      debugPrint('FCM token invalidation failed: $error\n$stack');
    }
  }
}
