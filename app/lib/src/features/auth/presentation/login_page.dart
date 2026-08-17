import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/brand_logo.dart';
import '../../../theme/app_colors.dart';
import '../data/auth_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    if (value == null || value.isEmpty) return 'Escribe tu contraseña';
    if (value.length < 8) return 'Debe tener al menos 8 caracteres';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await AuthService().signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.statusCode) {
        '400' => 'Correo o contraseña incorrectos (${error.message}).',
        '429' => 'Demasiados intentos. Espera un momento.',
        _ => 'No pudimos iniciar sesión: ${error.message}',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay conexión con el servicio ($e).'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    final emailToSend = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa tu correo y te enviaremos las instrucciones para restablecer tu contraseña:',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final email = resetEmailController.text.trim();
              if (email.isNotEmpty) {
                Navigator.of(ctx).pop(email);
              }
            },
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );

    if (emailToSend == null || emailToSend.isEmpty) return;

    final emailError = _validateEmail(emailToSend);
    if (emailError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(emailError), backgroundColor: AppColors.warning),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await AuthService().resetPassword(email: emailToSend);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace de recuperación enviado. Revisa tu bandeja de entrada.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar recuperación: ${error.message}'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pudimos enviar el correo de recuperación ($e).'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError), backgroundColor: AppColors.warning),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await AuthService().resendConfirmation(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enviamos un correo nuevo. Usa solamente el más reciente.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      final message = error.statusCode == '429'
          ? 'Espera un momento antes de solicitar otro correo.'
          : 'No pudimos reenviar la confirmación.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          BrandLogo(size: 76),
                          SizedBox(width: 12),
                          Text(
                            'InclusiChat',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Conecta con libertad. Conversa con seguridad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 42),
                      const Text(
                        'Bienvenido de nuevo',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Inicia sesión para continuar',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('emailField'),
                        controller: _emailController,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('passwordField'),
                        controller: _passwordController,
                        validator: _validatePassword,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !_isSubmitting,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _isSubmitting ? null : _forgotPassword,
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : _resendConfirmation,
                              child: const Text(
                                'Reenviar correo de confirmación',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: FilledButton(
                          key: const Key('signInButton'),
                          onPressed: _isSubmitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white70,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
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
                                  'Iniciar sesión',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          const Text(
                            '¿Aún no tienes cuenta?',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterPage(),
                              ),
                            ),
                            child: const Text('Crear cuenta'),
                          ),
                        ],
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
