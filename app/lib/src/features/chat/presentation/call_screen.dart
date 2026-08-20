import 'dart:async';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../calls/data/call_service.dart';
import '../../calls/data/call_signaling_service.dart';

enum CallType { audio, video }

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.contactName,
    this.avatarUrl,
    this.receiverUserId,
    this.callerId,
    this.callId,
    this.conversationId,
    this.callType = CallType.audio,
    this.isIncoming = false,
  });

  final String contactName;
  final String? avatarUrl;
  final String? receiverUserId;
  final String? callerId;
  final String? callId;
  final String? conversationId;
  final CallType callType;
  final bool isIncoming;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _timer;
  Timer? _statusPollTimer;
  Timer? _timeoutTimer;
  int _seconds = 0;
  bool _isConnected = false;
  bool _isIncomingRinging = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  final _callService = CallService();
  final _signaling = CallSignalingService();
  bool _hasEnded = false;
  String? _activeCallId;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _isIncomingRinging = widget.isIncoming;
    _activeCallId = widget.callId;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.28).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (!_isIncomingRinging) {
      _statusMessage = 'Repicando de forma segura...';
      _initiateOutgoingCall();
    } else {
      _statusMessage = 'Llamada de voz entrante...';
      _listenToRemoteCallState();
    }
  }

  Future<void> _initiateOutgoingCall() async {
    final targetId = widget.receiverUserId;
    if (targetId == null || targetId.isEmpty) return;

    // Crear sesión en base de datos
    final callId = await _callService.createCallSession(
      receiverId: targetId,
      conversationId: widget.conversationId,
      callType: widget.callType == CallType.video ? 'video' : 'audio',
    );

    if (!mounted) return;

    if (callId != null) {
      _activeCallId = callId;
    }

    // Enviar señal WebSocket de respaldo
    if (_activeCallId != null) {
      await _signaling.sendIncomingCall(
        receiverId: targetId,
        callId: _activeCallId!,
        callerName: widget.contactName,
        callerAvatar: widget.avatarUrl,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
        conversationId: widget.conversationId,
      );
    }

    // Monitorear en tiempo real si el receptor contesta o rechaza
    _listenToRemoteCallState();

    // Timeout de 35s si no contesta
    _timeoutTimer = Timer(const Duration(seconds: 35), () {
      if (mounted && !_isConnected && !_hasEnded) {
        _handleCallTerminated('Sin respuesta', wasConnected: false);
      }
    });
  }

  void _listenToRemoteCallState() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      if (_hasEnded || _activeCallId == null) return;

      final currentStatus = await _callService.getCallStatus(_activeCallId!);
      if (!mounted || _hasEnded) return;

      if (currentStatus == 'accepted' && !_isConnected) {
        // ¡El receptor contestó la llamada!
        _timeoutTimer?.cancel();
        setState(() {
          _isConnected = true;
          _isIncomingRinging = false;
          _statusMessage = 'Conectado';
        });
        _startTimer();
      } else if (currentStatus == 'rejected') {
        // ¡El receptor rechazó la llamada!
        _handleCallTerminated('Llamada rechazada', wasConnected: false);
      } else if (currentStatus == 'completed' || currentStatus == 'missed') {
        // La otra parte finalizó la llamada
        _handleCallTerminated('Llamada finalizada', wasConnected: _isConnected);
      }
    });
  }

  void _handleCallTerminated(String message, {required bool wasConnected}) {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() {
        _statusMessage = message;
        _isConnected = false;
        _isIncomingRinging = false;
      });
    }

    if (_activeCallId != null) {
      _callService.endCall(
        callId: _activeCallId!,
        conversationId: widget.conversationId,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
        durationSeconds: _seconds,
        wasConnected: wasConnected,
      );
    }

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _answerCall() async {
    _timeoutTimer?.cancel();
    if (_activeCallId != null) {
      await _callService.acceptCall(_activeCallId!);
    }

    final callerId = widget.callerId ?? widget.receiverUserId;
    if (callerId != null && callerId.isNotEmpty && _activeCallId != null) {
      await _signaling.sendCallAccepted(
        callerId: callerId,
        callId: _activeCallId!,
      );
    }

    if (mounted) {
      setState(() {
        _isIncomingRinging = false;
        _isConnected = true;
        _statusMessage = 'Conectado';
      });
      _startTimer();
    }
  }

  Future<void> _rejectIncomingCall() async {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();

    if (_activeCallId != null) {
      await _callService.rejectCall(_activeCallId!);
    }

    final callerId = widget.callerId ?? widget.receiverUserId;
    if (callerId != null && callerId.isNotEmpty && _activeCallId != null) {
      await _signaling.sendCallRejected(
        callerId: callerId,
        callId: _activeCallId!,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _endCall() async {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();

    if (_activeCallId != null) {
      await _callService.endCall(
        callId: _activeCallId!,
        conversationId: widget.conversationId,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
        durationSeconds: _seconds,
        wasConnected: _isConnected,
      );
    }

    final targetId = widget.isIncoming ? widget.callerId : widget.receiverUserId;
    if (targetId != null && targetId.isNotEmpty && _activeCallId != null) {
      await _signaling.sendCallEnded(
        targetUserId: targetId,
        callId: _activeCallId!,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == CallType.video && _isVideoEnabled;

    return Scaffold(
      backgroundColor: const Color(0xFF0F141A),
      body: SafeArea(
        child: Stack(
          children: [
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

            Column(
              children: [
                const SizedBox(height: 36),
                // Indicador de cifrado de llamada
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isConnected
                          ? AppColors.success.withValues(alpha: 0.4)
                          : AppColors.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isConnected ? Icons.lock_rounded : Icons.lock_outline_rounded,
                        size: 14,
                        color: _isConnected ? AppColors.success : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isConnected ? 'Conexión Cifrada E2EE' : 'Estableciendo canal seguro...',
                        style: TextStyle(
                          color: _isConnected ? AppColors.success : AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

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
                  _isConnected ? _formatDuration(_seconds) : _statusMessage,
                  style: TextStyle(
                    color: _isConnected
                        ? Colors.white
                        : (_statusMessage.contains('rechazada') || _statusMessage.contains('Sin respuesta')
                            ? AppColors.error
                            : AppColors.primary),
                    fontSize: _isConnected ? 22 : 16,
                    fontWeight: _isConnected ? FontWeight.bold : FontWeight.w600,
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
                            color: (_isConnected ? AppColors.success : AppColors.primary)
                                .withValues(alpha: _isConnected ? 0.35 : 0.2),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 64,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                            ? NetworkImage(widget.avatarUrl!)
                            : null,
                        child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
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
                  child: _isIncomingRinging
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton(
                                  heroTag: 'declineCallBtn',
                                  backgroundColor: AppColors.error,
                                  onPressed: _rejectIncomingCall,
                                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                                ),
                                const SizedBox(height: 8),
                                const Text('Rechazar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton(
                                  heroTag: 'answerCallBtn',
                                  backgroundColor: AppColors.success,
                                  onPressed: _answerCall,
                                  child: const Icon(Icons.call_rounded, color: Colors.white, size: 28),
                                ),
                                const SizedBox(height: 8),
                                const Text('Contestar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ],
                        )
                      : Row(
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
                              label: _isSpeakerOn ? 'Altavoz' : 'Auricular',
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
                              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
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
