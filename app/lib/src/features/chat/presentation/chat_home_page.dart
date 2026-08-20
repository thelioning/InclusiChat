import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_service.dart';
import '../../security/data/camouflage_service.dart';
import '../../security/presentation/camouflage_screen.dart';
import '../../security/presentation/camouflage_settings_page.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import '../../calls/data/call_signaling_service.dart';
import '../../update/update_service.dart';
import 'about_page.dart';
import 'call_screen.dart';
import 'calls_page.dart';
import 'contacts_page.dart';
import 'conversation_page.dart';
import 'new_conversation_page.dart';
import 'profile_settings_page.dart';
import 'quick_photo_preview_page.dart';
import 'settings_page.dart';
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
  List<ConversationSummary> _conversations = [];
  bool _isConversationsLoading = true;
  int _pendingRequestsCount = 0;
  int _totalUnreadCount = 0;
  List<ContactRequestItem> _incomingRequests = [];
  Timer? _homeRefreshTimer;
  Timer? _callCheckTimer;
  String? _activeShowingCallId;

  static const _titles = ['Conversaciones', 'Contactos', 'Llamadas'];

  @override
  void initState() {
    super.initState();
    _chatService.loadUserProfile();
    _fetchHomeData(initial: true);
    _homeRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchHomeData(initial: false));
    _callCheckTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) => _checkIncomingRingingCalls());

    CallSignalingService().initialize(
      incomingCallHandler: (event) {
        if (mounted && _activeShowingCallId != event.callId) {
          _activeShowingCallId = event.callId;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CallScreen(
                contactName: event.callerName,
                avatarUrl: event.callerAvatar,
                callerId: event.callerId,
                callId: event.callId,
                conversationId: event.conversationId,
                callType: event.callType == 'video' ? CallType.video : CallType.audio,
                isIncoming: true,
              ),
            ),
          ).then((_) {
            _activeShowingCallId = null;
          });
        }
      },
    );
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) UpdateService.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    _homeRefreshTimer?.cancel();
    _callCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkIncomingRingingCalls() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final rows = await Supabase.instance.client
          .from('call_records')
          .select('''
            id,
            caller_id,
            conversation_id,
            call_type,
            started_at,
            caller:profiles!call_records_caller_id_fkey(id, display_name, username, avatar_url)
          ''')
          .eq('receiver_id', uid)
          .eq('status', 'ringing')
          .order('started_at', ascending: false)
          .limit(1);

      if ((rows as List).isNotEmpty) {
        final row = rows.first;
        final callId = row['id']?.toString() ?? '';
        final startedAtStr = row['started_at']?.toString();
        final startedAt = startedAtStr != null ? DateTime.tryParse(startedAtStr) : null;

        if (startedAt != null && DateTime.now().toUtc().difference(startedAt.toUtc()).inSeconds < 40) {
          if (_activeShowingCallId != callId && mounted) {
            _activeShowingCallId = callId;
            final callerProfile = row['caller'] as Map?;
            final callerName = (callerProfile?['display_name'] as String?) ??
                (callerProfile?['username'] as String?) ??
                'Contacto';
            final callerAvatar = callerProfile?['avatar_url'] as String?;
            final callerId = row['caller_id']?.toString() ?? '';
            final conversationId = row['conversation_id']?.toString();
            final callType = row['call_type']?.toString() ?? 'audio';

            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CallScreen(
                  contactName: callerName,
                  avatarUrl: callerAvatar,
                  callerId: callerId,
                  callId: callId,
                  conversationId: conversationId,
                  callType: callType == 'video' ? CallType.video : CallType.audio,
                  isIncoming: true,
                ),
              ),
            ).then((_) {
              _activeShowingCallId = null;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchHomeData({bool initial = false}) async {
    if (initial && mounted) {
      setState(() => _isConversationsLoading = true);
    }
    try {
      final results = await Future.wait([
        _chatService.loadConversations(),
        _chatService.loadContactRequests(),
      ]);
      final convs = results[0] as List<ConversationSummary>;
      final reqs = results[1] as List<ContactRequestItem>;
      final incoming = reqs.where((r) => r.isIncoming).toList();
      final unread = convs.fold<int>(0, (sum, c) => sum + c.unreadCount);

      if (mounted) {
        setState(() {
          _conversations = convs;
          _pendingRequestsCount = incoming.length;
          _incomingRequests = incoming;
          _totalUnreadCount = unread;
          _isConversationsLoading = false;
        });
      }
    } catch (_) {
      if (mounted && initial) {
        setState(() => _isConversationsLoading = false);
      }
    }
  }

  Future<void> _reloadConversations() async {
    await _fetchHomeData(initial: false);
  }

  Future<void> _startConversation() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewConversationPage()),
    );
    if (mounted) await _reloadConversations();
  }

  Future<void> _openQuickCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                  title: const Text('Tomar foto con la cámara'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppColors.secondary),
                  title: const Text('Elegir foto de la galería'),
                  onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        ),
      );

      if (picked == null) return;

      final file = await picker.pickImage(
        source: picked,
        imageQuality: 50,
        maxWidth: 700,
        maxHeight: 700,
      );

      if (file != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => QuickPhotoPreviewPage(imagePath: file.path),
          ),
        );
        if (mounted) await _reloadConversations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo acceder a la cámara o galería.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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
              if (_selectedIndex == 0)
                IconButton(
                  tooltip: 'Cámara rápida',
                  onPressed: _openQuickCamera,
                  icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                ),
              if (CamouflageService.instance.isCamouflageFeatureActive)
                IconButton(
                  tooltip: 'Modo pánico / Camuflar',
                  onPressed: () => CamouflageService.instance.triggerCamouflage(),
                  icon: const Icon(Icons.visibility_off_rounded, color: AppColors.primary),
                ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                    );
                  }
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
                  if (value == 'guide') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const UserGuidePage()),
                    );
                  }
                  if (value == 'about') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                    );
                  }
                  if (value == 'logout') _signOut();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings_outlined, color: AppColors.primary),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Ajustes', style: TextStyle(fontWeight: FontWeight.w600))),
                        if (totalBadges > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: Text('$totalBadges', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
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
                        const Expanded(child: Text('Privacidad y camuflaje')),
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
                  const PopupMenuItem(
                    value: 'guide',
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded),
                        SizedBox(width: 12),
                        Text('Guía de uso'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded),
                        SizedBox(width: 12),
                        Text('Acerca de InclusiChat'),
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
                isLoading: _isConversationsLoading,
                onRefresh: _reloadConversations,
                searchQuery: _searchQuery,
                filter: _filter,
                incomingRequests: _incomingRequests,
                onGoToContacts: () => setState(() => _selectedIndex = 1),
                onSearchChanged: (value) => setState(() => _searchQuery = value),
                onFilterChanged: (value) => setState(() => _filter = value),
              ),
              const ContactsPage(),
              const CallsPage(),
            ],
          ),
          floatingActionButton: _selectedIndex == 0
              ? FloatingActionButton(
                  tooltip: 'Nuevo chat o contacto',
                  onPressed: _startConversation,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.add_comment_rounded, color: Colors.white),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
              if (index == 0) _reloadConversations();
            },
            destinations: [
              NavigationDestination(
                icon: _totalUnreadCount > 0
                    ? Badge.count(
                        count: _totalUnreadCount,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.chat_bubble_outline_rounded),
                      )
                    : const Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: _totalUnreadCount > 0
                    ? Badge.count(
                        count: _totalUnreadCount,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.chat_bubble_rounded),
                      )
                    : const Icon(Icons.chat_bubble_rounded),
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
              const NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call_rounded),
                label: 'Llamadas',
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
    required this.isLoading,
    required this.onRefresh,
    required this.searchQuery,
    required this.filter,
    required this.incomingRequests,
    required this.onGoToContacts,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final List<ConversationSummary> conversations;
  final bool isLoading;
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
          child: isLoading && conversations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : () {
                  final items = conversations.where(_matches).toList();
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
                          subtitle: Row(
                            children: [
                              if (item.isLastMessageMine && item.lastMessage != null) ...[
                                Icon(
                                  item.lastMessageReceiptStatus == 'sent'
                                      ? Icons.check_rounded
                                      : Icons.done_all_rounded,
                                  size: 16,
                                  color: switch (item.lastMessageReceiptStatus) {
                                    'read' => AppColors.receiptRead,
                                    _ => AppColors.textSecondary,
                                  },
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  item.lastMessage ?? 'Conversación nueva',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: item.unreadCount > 0
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: item.unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: SizedBox(
                            width: 76,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatActivity(item.lastActivityAt),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: item.unreadCount > 0
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: item.unreadCount > 0
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (item.unreadCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: AppColors.brandGradient,
                                      borderRadius: BorderRadius.circular(10),
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
                }(),
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
