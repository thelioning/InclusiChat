import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class InviteService {
  static Future<void> inviteViaWhatsApp({String? customUsername}) async {
    final user = Supabase.instance.client.auth.currentUser;
    final username = customUsername ??
        user?.userMetadata?['username'] as String? ??
        (user?.email != null ? user!.email!.split('@').first : 'usuario');

    final text = '¡Hola! Te invito a probar InclusiChat 💜✨ Mensajería privada y segura sin compartir tu número de teléfono.\n\n'
        '📲 Descarga la app aquí:\nhttps://github.com/thelioning/InclusiChat/releases/download/v1.0.0/InclusiChat-v1.0.apk\n\n'
        'Al instalarla, búscame en la pestaña Contactos como @$username para chatear 🙌';

    final uri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }
}
