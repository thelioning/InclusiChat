import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/message_push_service.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/chat/presentation/chat_home_page.dart';
import 'shared/widgets/brand_logo.dart';
import 'theme/app_theme.dart';

class SupabaseInitializationApp extends StatefulWidget {
  const SupabaseInitializationApp({
    super.key,
    required this.url,
    required this.publishableKey,
  });

  final String url;
  final String publishableKey;

  @override
  State<SupabaseInitializationApp> createState() =>
      _SupabaseInitializationAppState();
}

class _SupabaseInitializationAppState
    extends State<SupabaseInitializationApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    _initialization = Supabase.initialize(
      url: widget.url,
      publishableKey: widget.publishableKey,
    ).timeout(const Duration(seconds: 20));
  }

  void _retry() {
    setState(_startInitialization);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          final auth = Supabase.instance.client.auth;
          return InclusiChatApp(
            initiallyAuthenticated: auth.currentSession != null,
            authStateChanges: auth.onAuthStateChange,
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandLogo(size: 112),
                      const SizedBox(height: 22),
                      const Text(
                        'InclusiChat',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (!snapshot.hasError) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('Preparando tu espacio seguro…'),
                      ] else ...[
                        const Text(
                          'No pudimos restaurar la sesión local.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class InclusiChatApp extends StatelessWidget {
  const InclusiChatApp({
    super.key,
    this.initiallyAuthenticated = false,
    this.authStateChanges,
  });

  final bool initiallyAuthenticated;
  final Stream<AuthState>? authStateChanges;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'InclusiChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: authStateChanges == null
          ? _pageForAuthentication(initiallyAuthenticated)
          : StreamBuilder<AuthState>(
              stream: authStateChanges,
              builder: (context, snapshot) {
                final authenticated = snapshot.hasData
                    ? snapshot.data!.session != null
                    : initiallyAuthenticated;
                return _pageForAuthentication(authenticated);
              },
            ),
    );
  }

  Widget _pageForAuthentication(bool authenticated) =>
      authenticated ? const _AuthenticatedHome() : const LoginPage();
}

class _AuthenticatedHome extends StatefulWidget {
  const _AuthenticatedHome();

  @override
  State<_AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<_AuthenticatedHome> {
  @override
  void initState() {
    super.initState();
    MessagePushService.initializeForCurrentUser();
  }

  @override
  Widget build(BuildContext context) => const ChatHomePage();
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogo(size: 112),
                SizedBox(height: 24),
                Text(
                  'Falta la configuración pública de Supabase. Ejecuta la app con '
                  '--dart-define-from-file=config/dev.json.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
