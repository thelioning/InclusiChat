import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../auth/data/auth_service.dart';

class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad y blindaje'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.success, size: 36),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Espacio Protegido',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tus datos y conexiones están aislados bajo protocolos de seguridad y Row Level Security.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const ListTile(
            leading: Icon(Icons.lock_clock_outlined, color: AppColors.primary),
            title: Text('Mensajería efímera'),
            subtitle: Text('Los mensajes no persisten indefinidamente en el servidor.'),
          ),
          const Divider(height: 16),
          const ListTile(
            leading: Icon(Icons.phone_locked_outlined, color: AppColors.primary),
            title: Text('Privacidad de número'),
            subtitle: Text('Tu número de teléfono nunca es visible para otros contactos.'),
          ),
          const Divider(height: 16),
          const ListTile(
            leading: Icon(Icons.devices_rounded, color: AppColors.primary),
            title: Text('Sesión activa'),
            subtitle: Text('Conexión protegida vía token seguro con Supabase Auth.'),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Deseas cerrar tu sesión en este dispositivo?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar sesión en este dispositivo'),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Eliminar cuenta definitivamente'),
                  content: const Text(
                    'Esta acción es irreversible.\n\nSe eliminarán tu perfil, mensajes, solicitudes y contactos de forma permanente de acuerdo con el derecho al olvido.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Eliminar mi cuenta'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  await AuthService().deleteAccount();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tu cuenta y datos han sido eliminados correctamente.'),
                        backgroundColor: AppColors.surfaceRaised,
                      ),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No se pudo eliminar la cuenta. Inténtalo de nuevo.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 18),
            label: const Text(
              'Eliminar mi cuenta y borrar mis datos',
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
