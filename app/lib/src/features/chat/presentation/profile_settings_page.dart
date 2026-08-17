import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _chatService = ChatService();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _pronounsController = TextEditingController();
  final _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isVerified = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _pronounsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _chatService.loadUserProfile();
      if (mounted) {
        setState(() {
          _nameController.text = profile.displayName;
          _usernameController.text = profile.username.replaceAll('@', '');
          _pronounsController.text = profile.pronouns ?? '';
          _bioController.text = profile.bio ?? '';
          _avatarUrl = profile.avatarUrl;
          _isVerified = profile.isVerified;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAvatarPicker() {
    final avatarPresets = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
      'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=150',
      'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=150',
      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=150',
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona tu Avatar de Perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Elige un avatar seguro o restaura tus iniciales.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: avatarPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final url = avatarPresets[idx];
                  return InkWell(
                    borderRadius: BorderRadius.circular(35),
                    onTap: () {
                      setState(() => _avatarUrl = url);
                      Navigator.of(ctx).pop();
                    },
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: NetworkImage(url),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _avatarUrl = null);
                      Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Quitar foto'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showCustomUrlDialog();
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Enlace URL'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomUrlDialog() {
    final urlController = TextEditingController(text: _avatarUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pegar enlace de imagen'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            hintText: 'https://ejemplo.com/tu-foto.jpg',
            prefixIcon: Icon(Icons.image_outlined),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final text = urlController.text.trim();
              if (text.isNotEmpty) {
                setState(() => _avatarUrl = text);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final cleanUsername = _usernameController.text.trim().toLowerCase().replaceAll('@', '');
      await _chatService.updateUserProfile(
        displayName: _nameController.text.trim(),
        username: cleanUsername,
        pronouns: _pronounsController.text.trim(),
        bio: _bioController.text.trim(),
        avatarUrl: _avatarUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado con éxito.'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar los cambios: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil e identidad'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: InkWell(
                            onTap: _showAvatarPicker,
                            borderRadius: BorderRadius.circular(46),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 46,
                                  backgroundColor: AppColors.secondary,
                                  backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                                  child: _avatarUrl == null
                                      ? Text(
                                          _nameController.text.isNotEmpty
                                              ? _nameController.text.characters.first.toUpperCase()
                                              : 'U',
                                          style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nameController,
                          validator: (v) => v?.trim().isEmpty == true ? 'El nombre es obligatorio' : null,
                          decoration: const InputDecoration(
                            labelText: 'Nombre visible',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usernameController,
                          validator: (v) {
                            final u = v?.trim().toLowerCase().replaceAll('@', '') ?? '';
                            if (u.length < 3) return 'Mínimo 3 caracteres';
                            if (!RegExp(r'^[a-z0-9_]+$').hasMatch(u)) return 'Solo letras, números y guiones bajos';
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Alias único (@usuario)',
                            prefixText: '@',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                            helperText: 'Tus contactos te encuentran usando este alias.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pronounsController,
                          decoration: const InputDecoration(
                            labelText: 'Pronombres (opcional)',
                            prefixIcon: Icon(Icons.badge_outlined),
                            hintText: 'Ej. ella/her, él/him, elle/they',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          maxLength: 140,
                          decoration: const InputDecoration(
                            labelText: 'Biografía o estado seguro',
                            prefixIcon: Icon(Icons.info_outline_rounded),
                            hintText: 'Describe lo que desees compartir.',
                          ),
                        ),
                        if (_isVerified) ...[
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(Icons.verified_rounded, color: AppColors.primary, size: 20),
                              SizedBox(width: 8),
                              Text('Cuenta verificada de confianza', style: TextStyle(color: AppColors.primary)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 28),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            child: _isSaving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Guardar cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
