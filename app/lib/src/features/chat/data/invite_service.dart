import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class InviteService {
  static Future<void> inviteViaWhatsApp({String? customUsername}) async {
    final user = Supabase.instance.client.auth.currentUser;
    final username = customUsername ??
        user?.userMetadata?['username'] as String? ??
        (user?.email != null ? user!.email!.split('@').first : 'usuario');

    final text = '¡Hola! Ya estoy usando InclusiChat, la app de mensajería privada y segura. '
        'Descárgala para que conversemos con total privacidad y búscame como @$username ✨';

    final uri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }
}
