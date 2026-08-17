import 'dart:async';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

enum CallType { audio, video }

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.contactName,
    this.avatarUrl,
    this.callType = CallType.audio,
  });

  final String contactName;
  final String? avatarUrl;
  final CallType callType;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _timer;
  int _seconds = 0;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Simular conexión segura tras 2.5 segundos
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _isConnected = true);
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _endCall() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == CallType.video && _isVideoEnabled;

    return Scaffold(
      backgroundColor: const Color(0xFF0F141A),
      body: SafeArea(
        child: Stack(
          children: [
            // Si es videollamada, fondo con diseño de cámara simulada
            if (isVideo)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF1E2630),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_rounded, size: 80, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'Cámara segura activa',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Contenido principal
            Column(
              children: [
                const SizedBox(height: 40),
                // Indicador de cifrado de llamada
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 14, color: AppColors.success),
                      SizedBox(width: 6),
                      Text(
                        'Cifrado de Extremo a Extremo',
                        style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Nombre del contacto
                Text(
                  widget.contactName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                // Estado / Temporizador
                Text(
                  _isConnected ? _formatDuration(_seconds) : 'Llamando de forma segura...',
                  style: TextStyle(
                    color: _isConnected ? Colors.white70 : AppColors.primary,
                    fontSize: 16,
                    fontWeight: _isConnected ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),

                const Spacer(),

                // Avatar con animación de pulso de audio
                if (!isVideo)
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: _isConnected ? 0.35 : 0.15),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 64,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
                        child: widget.avatarUrl == null
                            ? Text(
                                widget.contactName.isNotEmpty
                                    ? widget.contactName.characters.first.toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 42, color: Colors.white, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                  ),

                const Spacer(flex: 2),

                // Barra de controles inferiores
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161C24),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Silenciar
                      _CallActionButton(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _isMuted ? 'Silenciado' : 'Silenciar',
                        isActive: _isMuted,
                        onPressed: () => setState(() => _isMuted = !_isMuted),
                      ),

                      // Altavoz
                      _CallActionButton(
                        icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Altavoz',
                        isActive: _isSpeakerOn,
                        onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                      ),

                      // Video (si aplica)
                      if (widget.callType == CallType.video)
                        _CallActionButton(
                          icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          label: 'Cámara',
                          isActive: _isVideoEnabled,
                          onPressed: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                        ),

                      // Botón Colgar
                      FloatingActionButton(
                        heroTag: 'endCallBtn',
                        backgroundColor: AppColors.error,
                        elevation: 4,
                        onPressed: _endCall,
                        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isActive ? Colors.white24 : Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
