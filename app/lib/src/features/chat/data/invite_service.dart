import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_service.dart';

class InviteService {
  static Future<void> inviteViaWhatsApp({String? customUsername}) async {
    String username = customUsername ?? '';

    if (username.isEmpty) {
      try {
        final profile = await ChatService().loadUserProfile();
        username = profile.username.replaceAll('@', '');
      } catch (_) {
        final user = Supabase.instance.client.auth.currentUser;
        username = user?.userMetadata?['username'] as String? ??
            (user?.email != null ? user!.email!.split('@').first : 'usuario');
      }
    }

    username = username.replaceAll('@', '').trim();
    if (username.isEmpty) username = 'usuario';

    final text = '¡Hola! Te invito a probar InclusiChat 💜✨ Mensajería privada y segura sin compartir tu número de teléfono.\n\n'
        '📲 Descarga la app aquí:\nhttps://github.com/thelioning/InclusiChat/releases/download/v1.2.1/InclusiChat-v1.2.1.apk\n\n'
        'Al instalarla, búscame en la pestaña Contactos como @$username para chatear 🙌';

    final nativeUri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');
    final webUri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}');

    try {
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }
}
