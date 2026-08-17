import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/brand_app_bar.dart';
import '../../../theme/app_colors.dart';
import '../data/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscurePassword = true;
  bool _acceptedTerms = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  String? _requiredName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Escribe el nombre que deseas mostrar';
    if (name.length < 2) return 'El nombre es demasiado corto';
    if (name.length > 80) return 'El nombre es demasiado largo';
    return null;
  }

  String? _validateUsername(String? value) {
    final username = value?.trim().toLowerCase().replaceAll('@', '') ?? '';
    if (username.isEmpty) return 'Elige tu alias de usuario';
    if (username.length < 3) return 'Debe tener al menos 3 caracteres';
    if (username.length > 24) return 'Máximo 24 caracteres';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      return 'Solo letras minúsculas, números y guiones bajos (_)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Escribe tu correo electrónico';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Escribe un correo válido';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 10) return 'Usa al menos 10 caracteres';
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Incluye mayúscula, minúscula y número';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes aceptar los términos y la política de privacidad.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final response = await AuthService().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        username: _usernameController.text.trim(),
      );
      if (!mounted) return;
      if (response.session != null) {
        return;
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirma tu correo'),
            content: const Text(
              'Te enviamos un enlace de confirmación. Ábrelo antes de iniciar sesión.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      final normalized = error.message.toLowerCase();
      final message = normalized.contains('already registered')
          ? 'Ya existe una cuenta con ese correo.'
          : normalized.contains('rate')
          ? 'Demasiados intentos. Espera un momento.'
          : 'Error de autenticación: ${error.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pudimos conectar con el servicio ($e).'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Crear cuenta', showBackButton: true),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandLogo(size: 112),
                      const SizedBox(height: 16),
                      const Text(
                        'Crea tu cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tu identidad es tuya. Comparte solo lo que desees.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('displayNameField'),
                        controller: _nameController,
                        validator: _requiredName,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nombre para mostrar',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('usernameField'),
                        controller: _usernameController,
                        validator: _validateUsername,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Alias único (@usuario)',
                          prefixText: '@',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                          helperText: 'Tus contactos podrán encontrarte con este alias.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('registerEmailField'),
                        controller: _emailController,
                        validator: _validateEmail,
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('registerPasswordField'),
                        controller: _passwordController,
                        validator: _validatePassword,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar contraseñas'
                                : 'Ocultar contraseñas',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('confirmationField'),
                        controller: _confirmationController,
                        validator: _validateConfirmation,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _acceptedTerms,
                        onChanged: _isSubmitting
                            ? null
                            : (value) => setState(
                                () => _acceptedTerms = value ?? false,
                              ),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'Acepto los términos de uso y la política de privacidad.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: FilledButton(
                          key: const Key('createAccountButton'),
                          onPressed: _isSubmitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white70,
                            shadowColor: Colors.transparent,
                          ),
                          child: _isSubmitting
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Crear cuenta',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
