import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _backgroundSupabaseInitialized = false;

/// Initializes Supabase inside a background Flutter engine/isolate and restores
/// the persisted authenticated session used by the foreground application.
Future<bool> ensureBackgroundSupabase() async {
  if (_backgroundSupabaseInitialized) {
    return Supabase.instance.client.auth.currentSession != null;
  }

  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final key = publishableKey.isNotEmpty ? publishableKey : anonKey;
  if (url.isEmpty || key.isEmpty) return false;

  try {
    // A background callback can occasionally run on an engine where Supabase
    // has already been initialized. Reuse that instance instead of initializing
    // it twice.
    final session = Supabase.instance.client.auth.currentSession;
    _backgroundSupabaseInitialized = true;
    return session != null;
  } catch (_) {
    // Expected for a fresh background engine.
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
