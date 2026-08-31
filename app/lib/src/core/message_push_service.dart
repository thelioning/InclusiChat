import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _pushOwnerKey = 'inclusichat_message_push_owner';
const _pushTokenKey = 'inclusichat_message_push_token';
const _installationIdKey = 'inclusichat_push_installation_id';
const _messageChannelId = 'inclusichat_messages_v2';
const _silentMessageChannelId = 'inclusichat_messages_silent_v2';
const _messageChannelName = 'Mensajes de InclusiChat';
const _messageSummaryNotificationId = 731001;

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

  // Mostrar el aviso no depende de que Supabase restaure la sesión enseguida.
  await MessagePushService.showChatNotification(message.data);

  if (!await _ensureBackgroundSupabase()) return;
  final client = Supabase.instance.client;
  if (client.auth.currentUser?.id != receiverId) return;

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
  static final Random _secureRandom = Random.secure();

  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static RealtimeChannel? _readStateChannel;
  static bool _initialized = false;
  static String? _initializedUserId;
  static bool _localNotificationsInitialized = false;

  static Future<void> initializeForCurrentUser() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (_initialized && _initializedUserId == user.id) return;

    if (_initialized && _initializedUserId != user.id) {
      await resetRuntimeSubscriptions();
    }

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

    _listenForReadStates(user.id);
    _initializedUserId = user.id;
    _initialized = true;
    await refreshUnreadBadge();
  }

  static String _randomInstallationId() {
    final bytes = List<int>.generate(20, (_) => _secureRandom.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _installationId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _randomInstallationId();
    await preferences.setString(_installationIdKey, created);
    return created;
  }

  static Future<void> _saveToken(String token, String userId) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.id != userId) return;

      final installationId = await _installationId();
      await Supabase.instance.client
          .from('device_push_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('installation_id', installationId)
          .neq('token', token);

      await Supabase.instance.client.from('device_push_tokens').upsert({
        'token': token,
        'user_id': userId,
        'platform': 'android',
        'installation_id': installationId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pushOwnerKey, userId);
      await preferences.setString(_pushTokenKey, token);
    } catch (error, stack) {
      debugPrint('FCM token registration failed: $error\n$stack');
    }
  }

  static void _listenForReadStates(String userId) {
    final client = Supabase.instance.client;
    final oldChannel = _readStateChannel;
    if (oldChannel != null) {
      client.removeChannel(oldChannel);
    }

    _readStateChannel = client
        .channel('message-push-read-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_read_states',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => unawaited(refreshUnreadBadge()),
        )
        .subscribe();
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

    const loudChannel = AndroidNotificationChannel(
      _messageChannelId,
      _messageChannelName,
      description: 'Mensajes nuevos con sonido y vibración',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    const silentChannel = AndroidNotificationChannel(
      _silentMessageChannelId,
      'Mensajes silenciados',
      description: 'Mensajes nuevos sin sonido ni vibración',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: true,
    );

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(loudChannel);
    await android?.createNotificationChannel(silentChannel);
    _localNotificationsInitialized = true;
  }

  static Future<void> showChatNotification(
    Map<String, dynamic> data,
  ) async {
    await _ensureLocalNotificationsInitialized();

    final senderName = data['sender_name']?.toString().trim();
    final messageType =
        data['chat_type']?.toString() ?? data['message_type']?.toString() ?? 'text';
    final badgeCount = int.tryParse(
          data['badge_count']?.toString() ?? data['unread_count']?.toString() ?? '',
        ) ??
        1;
    final muted = data['muted']?.toString() == 'true';

    final singleBody = switch (messageType) {
      'image' => 'Nueva foto',
      'audio' => 'Nueva nota de voz',
      _ => 'Nuevo mensaje',
    };
    final body = badgeCount > 1 ? '$badgeCount mensajes pendientes' : singleBody;
    final channelId = muted ? _silentMessageChannelId : _messageChannelId;
    final channelName = muted ? 'Mensajes silenciados' : _messageChannelName;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: muted
            ? 'Mensajes nuevos sin sonido ni vibración'
            : 'Mensajes nuevos con sonido y vibración',
        importance: muted ? Importance.defaultImportance : Importance.high,
        priority: muted ? Priority.defaultPriority : Priority.high,
        playSound: !muted,
        enableVibration: !muted,
        channelShowBadge: true,
        number: badgeCount,
        onlyAlertOnce: muted,
      ),
    );

    await _notifications.show(
      _messageSummaryNotificationId,
      senderName == null || senderName.isEmpty ? 'InclusiChat' : senderName,
      body,
      details,
      payload: data['conversation_id']?.toString(),
    );
  }

  static Future<void> refreshUnreadBadge() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final result = await Supabase.instance.client.rpc(
        'count_my_unread_chat_messages',
      );
      final count = result is int ? result : int.tryParse(result.toString()) ?? 0;
      await _ensureLocalNotificationsInitialized();
      if (count <= 0) {
        await _notifications.cancel(_messageSummaryNotificationId);
        return;
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _silentMessageChannelId,
          'Mensajes silenciados',
          channelDescription: 'Mensajes pendientes de InclusiChat',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          channelShowBadge: true,
          number: count,
          onlyAlertOnce: true,
        ),
      );
      await _notifications.show(
        _messageSummaryNotificationId,
        'InclusiChat',
        count == 1 ? '1 mensaje pendiente' : '$count mensajes pendientes',
        details,
      );
    } catch (error, stack) {
      debugPrint('Unread badge refresh failed: $error\n$stack');
    }
  }

  static Future<void> clearConversationNotification(String _) async {
    await refreshUnreadBadge();
  }

  static Future<void> resetRuntimeSubscriptions() async {
    final client = Supabase.instance.client;
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;

    final readState = _readStateChannel;
    if (readState != null) {
      await client.removeChannel(readState);
      _readStateChannel = null;
    }

    _initialized = false;
    _initializedUserId = null;
  }

  static Future<void> prepareForSignOut() async {
    final preferences = await SharedPreferences.getInstance();
    final installationId = preferences.getString(_installationIdKey);
    final user = Supabase.instance.client.auth.currentUser;

    if (installationId != null && installationId.isNotEmpty && user != null) {
      try {
        await Supabase.instance.client
            .from('device_push_tokens')
            .delete()
            .eq('user_id', user.id)
            .eq('installation_id', installationId);
      } catch (error, stack) {
        debugPrint('FCM installation detach failed: $error\n$stack');
      }
    }

    await preferences.remove(_pushOwnerKey);
    await preferences.remove(_pushTokenKey);
    await resetRuntimeSubscriptions();

    await _ensureLocalNotificationsInitialized();
    await _notifications.cancel(_messageSummaryNotificationId);

    try {
      await _messaging.deleteToken();
    } catch (error, stack) {
      debugPrint('FCM token invalidation failed: $error\n$stack');
    }
  }
}
