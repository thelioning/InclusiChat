import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const emailConfirmationRedirect =
      'com.inclusichat.inclusichat://login-callback/';

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signInWithMagicLink({required String email}) async {
    await _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: emailConfirmationRedirect,
    );
  }

  Future<bool> isUsernameAvailable(String username) async {
    final sanitized = username.trim().toLowerCase().replaceAll('@', '');
    if (sanitized.isEmpty) return false;
    try {
      final res = await _client.rpc(
        'check_username_available',
        params: {'target_username': sanitized},
      );
      if (res != null) return res as bool;
    } catch (_) {}

    try {
      final res = await _client
          .from('profiles')
          .select('id')
          .eq('username', sanitized)
          .maybeSingle();
      return res == null;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> generateUsernameSuggestions(String baseUsername) async {
    final clean = baseUsername
        .trim()
        .toLowerCase()
        .replaceAll('@', '')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (clean.isEmpty) return [];

    final suggestions = <String>[];
    final random = Random();
    final currentYear = DateTime.now().year;

    final candidates = [
      '${clean}_${random.nextInt(899) + 100}',
      '$clean${random.nextInt(89) + 10}',
      '${clean}_$currentYear',
      '${clean}_chat',
      '${clean}_rd',
      '${clean}_vip',
    ];

    for (final candidate in candidates) {
      if (suggestions.length >= 3) break;
      if (await isUsernameAvailable(candidate)) {
        suggestions.add(candidate);
      }
    }

    return suggestions;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) {
    final sanitizedUsername = username.trim().toLowerCase().replaceAll('@', '');
    return _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailConfirmationRedirect,
      data: {
        'display_name': displayName.trim(),
        'username': sanitizedUsername,
      },
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> resendConfirmation({required String email}) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: emailConfirmationRedirect,
    );
  }

  Future<void> resetPassword({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: emailConfirmationRedirect,
    );
  }

  Future<void> deleteAccount() async {
    await _client.rpc('delete_user_account');
    await signOut();
  }
}
