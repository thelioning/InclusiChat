import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'src/app.dart';
import 'src/features/calls/data/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Uncaught Flutter framework error',
      name: 'inclusichat.errors',
      error: details.exception,
      stackTrace: details.stack,
      level: 1000,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Uncaught platform error',
      name: 'inclusichat.errors',
      error: error,
      stackTrace: stack,
      level: 1000,
    );
    return true;
  };

  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final key = publishableKey.isNotEmpty ? publishableKey : anonKey;

  if (url.isEmpty || key.isEmpty) {
    runApp(const ConfigurationErrorApp());
    return;
  }

  runZonedGuarded(
    () => runApp(
      SupabaseInitializationApp(url: url, publishableKey: key),
    ),
    (error, stack) => developer.log(
      'Uncaught asynchronous error',
      name: 'inclusichat.errors',
      error: error,
      stackTrace: stack,
      level: 1000,
    ),
  );
}
