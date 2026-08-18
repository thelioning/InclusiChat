import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/data/auth_service.dart';
import '../../security/data/camouflage_service.dart';
import '../../security/presentation/camouflage_screen.dart';
import '../../security/presentation/camouflage_settings_page.dart';
import '../../security/presentation/security_settings_page.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import '../data/invite_service.dart';
import 'about_page.dart';
import 'contacts_page.dart';
import 'conversation_page.dart';
import 'new_conversation_page.dart';
import 'profile_settings_page.dart';
import 'user_guide_page.dart';

enum _ConversationFilter { all, unread, starred, circles, collectives }

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  int _selectedIndex = 0;
  bool _signingOut = false;
  String _searchQuery = '';
  _ConversationFilter _filter = _ConversationFilter.all;
  final _chatService = ChatService();
  late Future<List<ConversationSummary>> _conversations;
  int _pendingRequestsCount = 0;
  List<ContactRequestItem> _incomingRequests = [];
  Timer? _homeRefreshTimer;

  static const _titles = ['Conversaciones', 'Contactos', 'Ajustes'];

  @override
  void initState() {
    super.initState();
    _conversations = _chatService.loadConversations();
    _chatService.loadUserProfile();
    _checkRequests();
    _homeRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkRequests());
  }

  @override
  void dispose() {
    _homeRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkRequests() async {
    try {
      final reqs = await _chatService.loadContactRequests();
      final incoming = reqs.where((r) => r.isIncoming).toList();
      if (mounted && (_pendingRequestsCount != incoming.length || _incomingRequests.length != incoming.length)) {
        setState(() {
          _pendingRequestsCount = incoming.length;
          _incomingRequests = incoming;
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadConversations() async {
    setState(() => _conversations = _chatService.loadConversations());
    await _conversations;
    _checkRequests();
  }

  Future<void> _startConversation() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewConversationPage()),
    );
    if (mounted) await _reloadConversations();
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await AuthService().signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        CamouflageService.instance,
        ChatService.currentUserProfileNotifier,
      ]),
      builder: (context, _) {
        if (CamouflageService.instance.isCamouflaged) {
          return const CamouflageScreen();
        }

        final hasDefaultPin = CamouflageService.instance.isDefaultPin;
        final profile = ChatService.currentUserProfileNotifier.value;
        final hasMissingAvatar = (profile == null || profile.avatarUrl == null || profile.avatarUrl!.isEmpty);
        final totalBadges = (hasDefaultPin ? 1 : 0) + (hasMissingAvatar ? 1 : 0);

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                const BrandLogo(size: 34),
                const SizedBox(width: 10),
                Text(
                  _titles[_selectedIndex],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              if (CamouflageService.instance.isCamouflageFeatureActive)
                IconButton(
                  tooltip: 'Modo pánico / Camuflar',
                  onPressed: () => CamouflageService.instance.triggerCamouflage(),
                  icon: const Icon(Icons.visibility_off_rounded, color: AppColors.primary),
                ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'profile') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const ProfileSettingsPage()),
                    );
                  }
                  if (value == 'camouflage') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const CamouflageSettingsPage()),
                    );
                  }
                  if (value == 'logout') _signOut();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline_rounded),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Mi perfil')),
                        if (hasMissingAvatar)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'camouflage',
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_off_outlined),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Camuflaje')),
                        if (hasDefaultPin)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: AppColors.error),
                        SizedBox(width: 12),
                        Text('Cerrar sesión', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
                icon: _signingOut
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              _ConversationList(
                conversations: _conversations,
                onRefresh: _reloadConversations,
                searchQuery: _searchQuery,
                filter: _filter,
                incomingRequests: _incomingRequests,
                onGoToContacts: () => setState(() => _selectedIndex = 1),
                onSearchChanged: (value) => setState(() => _searchQuery = value),
                onFilterChanged: (value) => setState(() => _filter = value),
              ),
              const ContactsPage(),
              _SettingsSection(
                hasDefaultPin: hasDefaultPin,
                hasMissingAvatar: hasMissingAvatar,
              ),
            ],
          ),
          floatingActionButton: _selectedIndex == 0
              ? FloatingActionButton(
                  tooltip: 'Nueva conversación',
                  onPressed: _startConversation,
                  child: const Icon(Icons.chat_rounded),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
              if (index == 0) _reloadConversations();
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chats',
              ),
              NavigationDestination(
                icon: _pendingRequestsCount > 0
                    ? Badge.count(
                        count: _pendingRequestsCount,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.people_outline_rounded),
                      )
                    : const Icon(Icons.people_outline_rounded),
                selectedIcon: _pendingRequestsCount > 0
                    ? Badge.count(
                        count: _pendingRequestsCount,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.people_rounded),
                      )
                    : const Icon(Icons.people_rounded),
                label: 'Contactos',
              ),
              NavigationDestination(
                icon: totalBadges > 0
                    ? Badge.count(
                        count: totalBadges,
                        backgroundColor: AppColors.error,
                        child: const Icon(Icons.settings_outlined),
                      )
                    : const Icon(Icons.settings_outlined),
                selectedIcon: totalBadges > 0
                    ? Badge.count(
                        count: totalBadges,
                        backgroundColor: AppColors.error,
                        child: const Icon(Icons.settings_rounded),
                      )
                    : const Icon(Icons.settings_rounded),
                label: 'Ajustes',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.onRefresh,
    required this.searchQuery,
    required this.filter,
    required this.incomingRequests,
    required this.onGoToContacts,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final Future<List<ConversationSummary>> conversations;
  final Future<void> Function() onRefresh;
  final String searchQuery;
  final _ConversationFilter filter;
  final List<ContactRequestItem> incomingRequests;
  final VoidCallback onGoToContacts;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ConversationFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (incomingRequests.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.surfaceRaised,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 20),
              ),
              title: Text(
                '${incomingRequests.length} ${incomingRequests.length == 1 ? 'solicitud de contacto recibida' : 'solicitudes de contacto recibidas'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: Text(
                'De @${incomingRequests.first.profile.username ?? incomingRequests.first.profile.displayName} • Toca para responder',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              trailing: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onGoToContacts,
                child: const Text('Revisar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              onTap: onGoToContacts,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Buscar conversaciones',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _FilterChip(
                label: 'Todas',
                value: _ConversationFilter.all,
                selected: filter,
                onSelected: onFilterChanged,
              ),
              _FilterChip(
                label: 'Por leer',
                value: _ConversationFilter.unread,
                selected: filter,
                onSelected: onFilterChanged,
              ),
              _FilterChip(
                label: 'Círculos',
                value: _ConversationFilter.circles,
                selected: filter,
                onSelected: onFilterChanged,
              ),
              _FilterChip(
                label: 'Colectivos',
                value: _ConversationFilter.collectives,
                selected: filter,
                onSelected: onFilterChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ConversationSummary>>(
            future: conversations,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _RetryState(onRefresh: onRefresh);
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!.where(_matches).toList();
              if (items.isEmpty) {
                return RefreshIndicator(
                  onRefresh: onRefresh,
                  child: const CustomScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptySection(
                          icon: Icons.forum_outlined,
                          title: 'Tus conversaciones aparecerán aquí',
                          message:
                              'Pulsa el botón de chat o agrega contactos para iniciar una conversación segura.',
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 82),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 27,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: item.avatarUrl != null ? NetworkImage(item.avatarUrl!) : null,
                        child: item.avatarUrl == null
                            ? Text(item.title.characters.first.toUpperCase())
                            : null,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: item.unreadCount > 0
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        item.lastMessage ?? 'Conversación nueva',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatActivity(item.lastActivityAt),
                            style: TextStyle(
                              color: item.unreadCount > 0
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (item.unreadCount > 0) ...[
                            const SizedBox(height: 5),
                            Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                gradient: AppColors.brandGradient,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(11),
                                ),
                              ),
                              child: Text(
                                item.unreadCount > 99
                                    ? '99+'
                                    : '${item.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ConversationPage(
                              conversationId: item.id,
                              title: item.title,
                              avatarUrl: item.avatarUrl,
                            ),
                          ),
                        );
                        await onRefresh();
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _matches(ConversationSummary item) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty &&
        !item.title.toLowerCase().contains(query) &&
        !(item.lastMessage ?? '').toLowerCase().contains(query)) {
      return false;
    }
    return switch (filter) {
      _ConversationFilter.all => true,
      _ConversationFilter.unread => item.unreadCount > 0,
      _ConversationFilter.starred => item.isStarred,
      _ConversationFilter.circles => item.type == 'circle' || item.type == 'group',
      _ConversationFilter.collectives => item.type == 'collective' || item.type == 'community',
    };
  }

  String _formatActivity(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final _ConversationFilter value;
  final _ConversationFilter selected;
  final ValueChanged<_ConversationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
        selectedColor: AppColors.primary.withValues(alpha: 0.22),
        side: BorderSide(
          color: selected == value
              ? AppColors.primary
              : AppColors.surfaceRaised,
        ),
      ),
    );
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48),
          const SizedBox(height: 12),
          const Text('No se pudieron cargar las conversaciones.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    this.hasDefaultPin = false,
    this.hasMissingAvatar = false,
  });

  final bool hasDefaultPin;
  final bool hasMissingAvatar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _SettingsTile(
          icon: Icons.person_outline_rounded,
          title: 'Perfil e identidad',
          subtitle: hasMissingAvatar
              ? '⚠️ Foto de perfil pendiente (Toca para agregar)'
              : 'Nombre, foto, alias @usuario y pronombres',
          badgeCount: hasMissingAvatar ? 1 : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileSettingsPage()),
            );
          },
        ),
        _SettingsTile(
          icon: Icons.visibility_off_outlined,
          title: 'Privacidad y camuflaje',
          subtitle: hasDefaultPin
              ? '⚠️ PIN secreto por defecto 1234 (Toca para cambiar)'
              : 'Modo señuelo, botón de pánico y PIN secreto',
          badgeCount: hasDefaultPin ? 1 : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CamouflageSettingsPage()),
            );
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
          onTap: () => InviteService.inviteViaWhatsApp(),
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
          icon: Icons.info_outline_rounded,
          title: 'Acerca de InclusiChat',
          subtitle: 'Versión 1.1.1, autor, derechos y licencias',
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'InclusiChat v1.1.1 • Hecho con 💜 por Ermógenes Rodríguez Fernández & Baremetal Academy',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.badgeCount,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final int? badgeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
          if (badgeCount != null && badgeCount! > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
