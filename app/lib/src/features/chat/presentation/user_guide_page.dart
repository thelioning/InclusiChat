import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guía de uso y funciones'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Banner de bienvenida
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Bienvenido a InclusiChat',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Mensajería privada e inclusiva diseñada para que converses con total libertad y sin exponer tus datos personales.',
                  style:
                      TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Aspectos clave de la aplicación:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          _GuideCard(
            icon: Icons.alternate_email_rounded,
            iconColor: Colors.purpleAccent,
            title: '1. Tu identidad por @alias',
            description:
                'Nunca necesitas compartir tu número de teléfono. Tus contactos te encuentran usando tu alias único (ej: @carlos). Puedes cambiar tu nombre y alias en Ajustes > Perfil.',
          ),
          const SizedBox(height: 12),

          _GuideCard(
            icon: Icons.person_add_rounded,
            iconColor: Colors.blueAccent,
            title: '2. Búsqueda y Solicitudes',
            description:
                'Ve a la pestaña "Contactos" y pulsa "+" para buscar personas por su alias. Para tu seguridad, nadie puede chatearte hasta que aceptes su solicitud de contacto.',
          ),
          const SizedBox(height: 12),

          _GuideCard(
            icon: Icons.calculate_outlined,
            iconColor: Colors.amberAccent,
            title: '3. Modo Camuflaje y PIN Personalizable',
            description:
                'Primero configura un PIN personal en Ajustes > Privacidad y camuflaje. Después podrás usar el icono de camuflaje para mostrar la calculadora. No existe un PIN de fábrica y el modo permanece desactivado hasta que establezcas uno de 4 a 6 dígitos.',
          ),
          const SizedBox(height: 12),

          _GuideCard(
            icon: Icons.call_outlined,
            iconColor: Colors.greenAccent,
            title: '4. Llamadas y Videollamadas',
            description:
                'Los iconos de teléfono y cámara abren una vista previa experimental de señalización. La versión actual todavía no transporta audio o video.',
          ),
          const SizedBox(height: 12),

          _GuideCard(
            icon: Icons.share_rounded,
            iconColor: const Color(0xFF25D366),
            title: '5. Invitar amigos por WhatsApp',
            description:
                'En la pestaña Contactos verás el botón para compartir tu alias por WhatsApp con un solo toque y conectar de inmediato con tus amigos.',
          ),
          const SizedBox(height: 28),

          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded),
            label: const Text('¡Entendido, a chatear!'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
