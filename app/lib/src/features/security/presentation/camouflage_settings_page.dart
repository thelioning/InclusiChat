import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../data/camouflage_service.dart';

class CamouflageSettingsPage extends StatefulWidget {
  const CamouflageSettingsPage({super.key});

  @override
  State<CamouflageSettingsPage> createState() => _CamouflageSettingsPageState();
}

class _CamouflageSettingsPageState extends State<CamouflageSettingsPage> {
  final _service = CamouflageService.instance;
  late bool _isActive;
  late String _pin;
  final _pinEditController = TextEditingController();
  final _pinConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isActive = _service.isCamouflageFeatureActive;
    _pin = '';
  }

  @override
  void dispose() {
    _pinEditController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    _service.configure(
      active: _isActive,
      type: 'calculator',
      newPin: _pin,
    );
  }

  void _showChangePinDialog() {
    _pinEditController.clear();
    _pinConfirmController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar PIN secreto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa un PIN de 4 a 6 dígitos que usarás en la calculadora señuelo para volver a tus chats.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinEditController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Nuevo PIN secreto',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinConfirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirmar nuevo PIN',
                prefixIcon: Icon(Icons.lock_reset_rounded),
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
              final newPin = _pinEditController.text.trim();
              final confirmPin = _pinConfirmController.text.trim();
              if (newPin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El PIN debe tener al menos 4 dígitos.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              if (newPin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Los PINs no coinciden. Inténtalo de nuevo.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              setState(() => _pin = newPin);
              _saveSettings();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PIN secreto actualizado con éxito.'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: const Text('Guardar PIN'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = !_service.hasSecurePin && _pin.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacidad y camuflaje'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (isDefault) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF332211),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Configura un PIN seguro',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.amber),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'El modo camuflaje permanece desactivado hasta que configures un PIN de 4 a 6 dígitos.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: _showChangePinDialog,
                          child: const Text('Personalizar mi PIN',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.visibility_off_rounded,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo Camuflaje Seguro',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Disfraza la app como una calculadora completamente funcional ante situaciones de revisión obligatoria.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Activar modo camuflaje',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Habilita la calculadora señuelo y el botón de pánico.'),
            value: _isActive,
            onChanged: (val) {
              setState(() => _isActive = val);
              _saveSettings();
            },
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.pin_rounded, color: AppColors.primary),
            title: Row(
              children: [
                const Text('PIN secreto de salida'),
                if (isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('1',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              isDefault
                  ? 'Sin PIN configurado'
                  : 'PIN protegido (${"•" * (_pin.isNotEmpty ? _pin.length : _service.pinLength)})',
              style: TextStyle(color: isDefault ? Colors.amberAccent : null),
            ),
            trailing: FilledButton(
              style: isDefault
                  ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                  : null,
              onPressed: _showChangePinDialog,
              child: const Text('Cambiar'),
            ),
          ),
          const SizedBox(height: 32),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFC2185B)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: FilledButton.icon(
              onPressed: () {
                _service.triggerCamouflage();
                Navigator.of(context).pop();
              },
              icon:
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
              label: const Text(
                'Activar camuflaje ahora (Prueba)',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Al activarlo, la app mostrará una calculadora. Para volver a InclusiChat, escribe tu PIN secreto y presiona el botón "=".',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
