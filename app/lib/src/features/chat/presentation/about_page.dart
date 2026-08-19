import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/brand_logo.dart';
import '../../../theme/app_colors.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _websiteUrl = 'https://inclusichat.org';
  static const _privacyUrl = 'https://inclusichat.org/privacy.html';
  static const _termsUrl = 'https://inclusichat.org/terms.html';
  static const _githubUrl = 'https://github.com/thelioning/InclusiChat';

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir el enlace: $url')),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acerca de InclusiChat'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                // Header con Logo
                const BrandLogo(size: 80),
                const SizedBox(height: 16),
                const Text(
                  'InclusiChat',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mensajería privada e inclusiva con modo camuflaje',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Versión 1.2.0 (Build 21) • Release Estable',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Tarjeta de Autor y Derechos de Autor
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.copyright_rounded, size: 20, color: AppColors.primary),
                          SizedBox(width: 10),
                          Text(
                            'Propiedad y Derechos de Autor',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: Colors.white10),
                      const Text(
                        '© 2026 InclusiChat & Baremetal Academy',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Creador y Desarrollador:',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'Ermógenes Rodríguez Fernández',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Licencia de Software:',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const Text(
                        'Software Libre de Código Abierto y Tecnología de Interés Público.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Enlaces Oficiales y Documentación Legal
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                        title: const Text('Sitio Web Oficial'),
                        subtitle: const Text('inclusichat.org'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => _openUrl(context, _websiteUrl),
                      ),
                      const Divider(height: 1, indent: 56, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
                        title: const Text('Política de Privacidad'),
                        subtitle: const Text('Protección y derechos de datos'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => _openUrl(context, _privacyUrl),
                      ),
                      const Divider(height: 1, indent: 56, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                        title: const Text('Términos de Servicio'),
                        subtitle: const Text('Normas de uso y convivencia'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => _openUrl(context, _termsUrl),
                      ),
                      const Divider(height: 1, indent: 56, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.code_rounded, color: AppColors.primary),
                        title: const Text('Código Fuente en GitHub'),
                        subtitle: const Text('thelioning/InclusiChat'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => _openUrl(context, _githubUrl),
                      ),
                      const Divider(height: 1, indent: 56, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.workspace_premium_outlined, color: AppColors.primary),
                        title: const Text('Licencias de Código Abierto'),
                        subtitle: const Text('Bibliotecas y software de terceros'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          showLicensePage(
                            context: context,
                            applicationName: 'InclusiChat',
                            applicationVersion: '1.2.0',
                            applicationLegalese: '© 2026 InclusiChat & Baremetal Academy (Ermógenes Rodríguez Fernández)',
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Firma y Pie de Página
                const Text(
                  'Desarrollado con 💜 por Ermógenes Rodríguez Fernández\nBaremetal Academy • República Dominicana',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
