import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
  final _imagePicker = ImagePicker();

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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64String = base64Encode(bytes);
        setState(() {
          _avatarUrl = 'data:image/jpeg;base64,$base64String';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto seleccionada. Recuerda pulsar "Guardar cambios".'),
              backgroundColor: AppColors.surfaceRaised,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar la imagen: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  ImageProvider? _getAvatarProvider(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:image')) {
      try {
        final base64Str = url.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(url);
  }

  void _showAvatarPicker() {
    // 1. Comunidad Afrodescendiente & Piel Oscura (Prominente)
    final afroAvatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=250&q=80', // Mujer afro con recogido
      'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?auto=format&fit=crop&w=250&q=80', // Mujer afrodescendiente
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=250&q=80', // Hombre afrodescendiente sonriente
      'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?auto=format&fit=crop&w=250&q=80', // Joven piel oscura
      'https://images.unsplash.com/photo-1589156280159-27698a70f29e?auto=format&fit=crop&w=250&q=80', // Mujer afro con trenzas
      'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=250&q=80', // Mujer profesional afro
      'https://images.unsplash.com/photo-1506277886164-e25aa3f4ef7f?auto=format&fit=crop&w=250&q=80', // Hombre afrodescendiente
      'https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&w=250&q=80', // Retrato mujer piel oscura
    ];

    // 2. Diversidad Global (Latina, Indígena, Asiática y Medio Oriente)
    final globalAvatars = [
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=250&q=80', // Mujer latina
      'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?auto=format&fit=crop&w=250&q=80', // Hombre latino
      'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=250&q=80', // Hombre piel morena
      'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=250&q=80', // Mujer asiática
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=250&q=80', // Retrato global
      'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=250&q=80', // Joven diversa
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Foto y Avatar Inclusivo',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cámara, galería o avatares diversos.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Opciones de foto real
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                    label: const Text('Galería del móvil'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                    label: const Text('Tomar foto'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // SECCIÓN 1: Afrodescendientes y Piel Oscura
            const Row(
              children: [
                Text(
                  '✊🏾 Avatares Afrodescendientes & Piel Oscura',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.amberAccent),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: afroAvatars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final url = afroAvatars[idx];
                  return _AvatarOptionCircle(
                    imageUrl: url,
                    isSelected: _avatarUrl == url,
                    onTap: () {
                      setState(() => _avatarUrl = url);
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 22),

            // SECCIÓN 2: Diversidad Global
            const Row(
              children: [
                Text(
                  '🌎 Diversidad Latina, Indígena y Global',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: globalAvatars.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, idx) {
                  final url = globalAvatars[idx];
                  return _AvatarOptionCircle(
                    imageUrl: url,
                    isSelected: _avatarUrl == url,
                    onTap: () {
                      setState(() => _avatarUrl = url);
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Botones secundarios
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _avatarUrl = null);
                      Navigator.of(ctx).pop();
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    label: const Text('Quitar foto', style: TextStyle(color: AppColors.error)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _showCustomUrlDialog();
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Pegar URL'),
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
                          child: Column(
                            children: [
                              InkWell(
                                onTap: _showAvatarPicker,
                                borderRadius: BorderRadius.circular(46),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 46,
                                      backgroundColor: AppColors.secondary,
                                      backgroundImage: _getAvatarProvider(_avatarUrl),
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
                                    if (_avatarUrl == null || _avatarUrl!.isEmpty)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.error,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.surface, width: 2),
                                          ),
                                          child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_avatarUrl == null || _avatarUrl!.isEmpty) ...[
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  onPressed: _showAvatarPicker,
                                  icon: const Icon(Icons.add_a_photo_outlined, size: 16, color: AppColors.primary),
                                  label: const Text('Elegir foto o avatar de perfil', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ],
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
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                          ],
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

class _AvatarOptionCircle extends StatelessWidget {
  const _AvatarOptionCircle({
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });

  final String imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(38),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipOval(
          child: SizedBox(
            width: 68,
            height: 68,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppColors.surfaceRaised,
                  child: const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppColors.surfaceRaised,
                  child: const Icon(Icons.person_rounded, color: AppColors.textSecondary),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
