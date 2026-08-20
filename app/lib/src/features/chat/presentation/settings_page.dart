import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../theme/app_colors.dart';
import '../../auth/data/auth_service.dart';
import '../../security/data/camouflage_service.dart';
import '../../security/presentation/camouflage_settings_page.dart';
import '../../security/presentation/security_settings_page.dart';
import '../../update/update_service.dart';
import '../data/chat_service.dart';
import '../data/invite_service.dart';
import 'about_page.dart';
import 'profile_settings_page.dart';
import 'user_guide_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _chatService = ChatService();
  UserProfileData? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _chatService.loadUserProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDefaultPin = CamouflageService.instance.isDefaultPin;
    final hasMissingAvatar = _profile?.avatarUrl == null || _profile!.avatarUrl!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                // Tarjeta de perfil superior
                if (_profile != null)
                  InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ProfileSettingsPage()),
                      );
                      _loadProfile();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.secondary,
                            backgroundImage: _profile!.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty
                                ? NetworkImage(_profile!.avatarUrl!)
                                : null,
                            child: _profile!.avatarUrl == null || _profile!.avatarUrl!.isEmpty
                                ? Text(
                                    _profile!.displayName.isNotEmpty ? _profile!.displayName[0].toUpperCase() : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile!.displayName,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${_profile!.username}',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                if (_profile!.bio != null && _profile!.bio!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _profile!.bio!,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),

                _SettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Perfil e identidad',
                  subtitle: hasMissingAvatar
                      ? '⚠️ Foto de perfil pendiente (Toca para agregar)'
                      : 'Nombre, foto, alias @usuario y pronombres',
                  badgeCount: hasMissingAvatar ? 1 : null,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const ProfileSettingsPage()),
                    );
                    _loadProfile();
                  },
                ),
                _SettingsTile(
                  icon: Icons.visibility_off_outlined,
                  title: 'Privacidad y camuflaje',
                  subtitle: hasDefaultPin
                      ? '⚠️ PIN secreto por defecto 1234 (Toca para cambiar)'
                      : 'Modo señuelo, botón de pánico y PIN secreto',
                  badgeCount: hasDefaultPin ? 1 : null,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const CamouflageSettingsPage()),
                    );
                    _loadProfile();
                  },
                ),
                _SettingsTile(
                  icon: Icons.security_rounded,
                  title: 'Seguridad',
                  subtitle: 'Aislamiento de datos, permisos y sesiones',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SecuritySettingsPage()),
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notificaciones',
                  subtitle: 'Alertas discretas de mensajes y llamadas',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notificaciones discretas activas por defecto.')),
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.share_rounded,
                  iconColor: const Color(0xFF25D366),
                  title: 'Invitar amigos por WhatsApp',
                  subtitle: 'Comparte tu @alias para conectar en InclusiChat',
                  onTap: () => InviteService.inviteViaWhatsApp(customUsername: _profile?.username),
                ),
                _SettingsTile(
                  icon: Icons.menu_book_rounded,
                  title: 'Guía de uso y funciones',
                  subtitle: 'Aprende cómo usar el alias, camuflaje y llamadas',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const UserGuidePage()),
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.system_update_rounded,
                  title: 'Buscar actualizaciones',
                  subtitle: 'Comprobar si hay una nueva versión disponible',
                  onTap: () => UpdateService.checkForUpdates(context, forceShow: true),
                ),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Acerca de InclusiChat',
                  subtitle: 'Versión ${AppConfig.version}, autor, derechos y licencias',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                    );
                  },
                ),
                const Divider(height: 24),
                _SettingsTile(
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.error,
                  title: 'Cerrar sesión',
                  subtitle: 'Desconectar tu cuenta de este dispositivo',
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Cerrar sesión'),
                        content: const Text('¿Deseas cerrar tu sesión en este dispositivo?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancelar'),
                          ),
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
                    }
                  },
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    AppConfig.footerCredit,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.badgeCount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: (iconColor ?? AppColors.primary).withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor ?? AppColors.primary, size: 22),
          ),
          if (badgeCount != null && badgeCount! > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
