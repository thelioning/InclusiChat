import 'dart:async';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../calls/data/call_service.dart';
import '../../calls/data/call_signaling_service.dart';
import '../data/chat_service.dart';

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
  final _chatService = ChatService();
  final _signaling = CallSignalingService();
  bool _hasEnded = false;
  late String _activeCallId;
  String? _activeConversationId;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _isIncomingRinging = widget.isIncoming;
    _activeCallId = widget.callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    _activeConversationId = widget.conversationId;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.28).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Conectar a la sala de señalización de la llamada
    _signaling.joinCallRoom(
      callId: _activeCallId,
      callAcceptedHandler: (id) {
        if (!_isConnected && mounted && !_hasEnded) {
          _onRemoteAccepted();
        }
      },
      callRejectedHandler: (id) {
        if (mounted && !_hasEnded) {
          _handleCallTerminated('Llamada rechazada', wasConnected: false);
        }
      },
      callEndedHandler: (id) {
        if (mounted && !_hasEnded) {
          _handleCallTerminated('Llamada finalizada', wasConnected: _isConnected);
        }
      },
    );

    if (!_isIncomingRinging) {
      _statusMessage = 'Repicando de forma segura...';
      _initiateOutgoingCall();
    } else {
      _statusMessage = 'Llamada de voz entrante...';
      _startStatusPolling();
    }
  }

  Future<void> _initiateOutgoingCall() async {
    try {
      final targetId = widget.receiverUserId;
      if (targetId == null || targetId.isEmpty) return;

      // Obtener o crear conversación directa
      String convId = _activeConversationId ?? '';
      if (convId.isEmpty) {
        convId = await _chatService.createDirectConversation(targetId);
        _activeConversationId = convId;
      }

      // Obtener mi nombre de perfil
      String myName = 'Contacto';
      String? myAvatar;
      try {
        final profile = await _chatService.loadUserProfile();
        myName = profile.displayName;
        myAvatar = profile.avatarUrl;
      } catch (_) {}

      // 1. Enviar señal Realtime directa al usuario destinatario
      await _signaling.sendIncomingCallSignal(
        receiverId: targetId,
        callId: _activeCallId,
        callerName: myName,
        callerAvatar: myAvatar,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
        conversationId: convId,
      );

      // 2. Enviar mensaje de señal en la conversación como respaldo dual
      await _callService.startCall(
        conversationId: convId,
        receiverId: targetId,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
      );

      _startStatusPolling();

      // Timeout si no contesta en 35 segundos
      _timeoutTimer = Timer(const Duration(seconds: 35), () {
        if (mounted && !_isConnected && !_hasEnded) {
          _handleCallTerminated('Sin respuesta', wasConnected: false);
        }
      });
    } catch (e) {
      debugPrint('Error initiating outgoing call: $e');
    }
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 750), (_) async {
      if (_hasEnded || _activeConversationId == null) return;

      final action = await _callService.getCallSignalState(
        conversationId: _activeConversationId!,
        callId: _activeCallId,
      );

      if (!mounted || _hasEnded) return;

      if (action == 'accept' && !_isConnected) {
        _onRemoteAccepted();
      } else if (action == 'reject') {
        _handleCallTerminated('Llamada rechazada', wasConnected: false);
      } else if (action == 'end') {
        _handleCallTerminated(
          _isIncomingRinging ? 'Llamada cancelada' : 'Llamada finalizada',
          wasConnected: _isConnected,
        );
      }
    });
  }

  void _onRemoteAccepted() {
    _timeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _isConnected = true;
        _isIncomingRinging = false;
        _statusMessage = 'Conectado';
      });
      _startTimer();
    }
  }

  void _handleCallTerminated(String message, {required bool wasConnected}) {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();
    _signaling.leaveCallRoom();

    if (mounted) {
      setState(() {
        _statusMessage = message;
        _isConnected = false;
        _isIncomingRinging = false;
      });
    }

    Future.delayed(const Duration(milliseconds: 1300), () {
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
    _signaling.leaveCallRoom();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _answerCall() async {
    _timeoutTimer?.cancel();

    // 1. Enviar señal Realtime a la sala
    await _signaling.sendAcceptSignal(_activeCallId);

    // 2. Enviar señal de aceptación en la conversación
    if (_activeConversationId != null) {
      await _callService.acceptCall(
        conversationId: _activeConversationId!,
        callId: _activeCallId,
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

    // 1. Enviar señal Realtime de rechazo a la sala
    await _signaling.sendRejectSignal(_activeCallId);

    // 2. Enviar mensaje de rechazo en conversación
    if (_activeConversationId != null) {
      await _callService.rejectCall(
        conversationId: _activeConversationId!,
        callId: _activeCallId,
      );
    }

    _signaling.leaveCallRoom();

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

    // 1. Enviar señal Realtime de finalización a la sala
    await _signaling.sendEndSignal(_activeCallId);

    // 2. Enviar mensaje de finalización en conversación
    if (_activeConversationId != null) {
      await _callService.endCall(
        conversationId: _activeConversationId!,
        callId: _activeCallId,
        durationSeconds: _seconds,
        wasConnected: _isConnected,
      );
    }

    _signaling.leaveCallRoom();

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

                Text(
                  widget.contactName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

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
                            _CallActionButton(
                              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              label: _isMuted ? 'Silenciado' : 'Silenciar',
                              isActive: _isMuted,
                              onPressed: () => setState(() => _isMuted = !_isMuted),
                            ),
                            _CallActionButton(
                              icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                              label: _isSpeakerOn ? 'Altavoz' : 'Auricular',
                              isActive: _isSpeakerOn,
                              onPressed: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                            ),
                            if (widget.callType == CallType.video)
                              _CallActionButton(
                                icon: _isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                                label: 'Cámara',
                                isActive: _isVideoEnabled,
                                onPressed: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                              ),
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
