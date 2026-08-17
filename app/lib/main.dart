import 'package:flutter/material.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final key = publishableKey.isNotEmpty ? publishableKey : anonKey;

  if (url.isEmpty || key.isEmpty) {
    runApp(const ConfigurationErrorApp());
    return;
  }

  runApp(
    SupabaseInitializationApp(url: url, publishableKey: key),
  );
}
