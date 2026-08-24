import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../theme/app_colors.dart';
import '../../calls/data/call_audio_service.dart';
import '../../calls/data/call_manager.dart';
import '../../calls/data/native_call_notification_service.dart';
import '../../calls/data/call_service.dart';
import '../data/chat_service.dart';
import 'chat_home_page.dart';

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
    this.acceptedFromSystem = false,
  });

  final String contactName;
  final String? avatarUrl;
  final String? receiverUserId;
  final String? callerId;
  final String? callId;
  final String? conversationId;
  final CallType callType;
  final bool isIncoming;
  final bool acceptedFromSystem;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _timer;
  Timer? _statusPollTimer;
  Timer? _timeoutTimer;
  Timer? _vibrateTimer;
  int _seconds = 0;
  bool _isConnected = false;
  bool _isIncomingRinging = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  final _callService = CallService();
  final _chatService = ChatService();
  bool _hasEnded = false;
  late String _activeCallId;
  String? _activeConversationId;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    CallManager.instance.isCallActive = true;
    _isIncomingRinging = widget.isIncoming && !widget.acceptedFromSystem;
    _isConnected = widget.acceptedFromSystem;
    _activeCallId = widget.callId ?? const Uuid().v4();
    _activeConversationId = widget.conversationId;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.28).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (!widget.isIncoming) {
      _statusMessage = 'Repicando de forma segura...';
      CallAudioService.startOutgoingDialTone();
      _initiateOutgoingCall();
    } else if (widget.acceptedFromSystem) {
      _statusMessage = 'Conectado';
      _startStatusPolling();
      _startTimer();
    } else {
      _statusMessage = 'Llamada de voz entrante...';
      CallAudioService.startIncomingRinging(callerName: widget.contactName);
      _startRingingVibration();
      _startStatusPolling();
      _timeoutTimer = Timer(const Duration(seconds: 35), () {
        if (mounted && !_isConnected && !_hasEnded) {
          _expireIncomingCall();
        }
      });
    }
  }

  void _startRingingVibration() {
    _vibrateTimer?.cancel();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (_hasEnded || _isConnected || !_isIncomingRinging) {
        _vibrateTimer?.cancel();
        return;
      }
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    });
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  void _stopRingingVibration() {
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    CallAudioService.stopIncomingRinging();
    CallAudioService.stopOutgoingDialTone();
  }

  Future<void> _initiateOutgoingCall() async {
    try {
      final targetId = widget.receiverUserId;
      if (targetId == null || targetId.isEmpty) return;

      String convId = _activeConversationId ?? '';
      if (convId.isEmpty) {
        convId = await _chatService.createDirectConversation(targetId);
        _activeConversationId = convId;
      }

      // La señal se guarda en la conversación y queda protegida por RLS.
      await _callService.startCall(
        conversationId: convId,
        receiverId: targetId,
        callType: widget.callType == CallType.video ? 'video' : 'audio',
        callId: _activeCallId,
      );

      _startStatusPolling();

      _timeoutTimer = Timer(const Duration(seconds: 35), () {
        if (mounted && !_isConnected && !_hasEnded) {
          _expireOutgoingCall();
        }
      });
    } catch (e) {
      debugPrint('Error initiating outgoing call: $e');
      _handleCallTerminated('No se pudo iniciar la llamada',
          wasConnected: false);
    }
  }

  Future<void> _expireOutgoingCall() async {
    final convId = _activeConversationId;
    if (convId != null) {
      try {
        await _callService.endCall(
          conversationId: convId,
          callId: _activeCallId,
          durationSeconds: 0,
          wasConnected: false,
          callType: widget.callType == CallType.video ? 'video' : 'audio',
        );
      } catch (e) {
        debugPrint('Error expiring outgoing call: $e');
      }
    }
    _handleCallTerminated('Sin respuesta', wasConnected: false);
  }

  Future<void> _expireIncomingCall() async {
    final convId = _activeConversationId;
    if (convId != null) {
      try {
        await _callService.rejectCall(
          conversationId: convId,
          callId: _activeCallId,
        );
      } catch (e) {
        debugPrint('Error expiring incoming call: $e');
      }
    }
    _handleCallTerminated('Llamada perdida', wasConnected: false);
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) async {
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
    _stopRingingVibration();
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
    _stopRingingVibration();
    CallManager.instance.isCallActive = false;
    unawaited(NativeCallNotificationService.end(_activeCallId));

    if (mounted) {
      setState(() {
        _statusMessage = message;
        _isConnected = false;
        _isIncomingRinging = false;
      });
    }

    unawaited(_closeTerminatedCall());
  }

  Future<void> _closeTerminatedCall() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final popped = await navigator.maybePop();
    if (!popped && mounted) {
      // If Android restored the call notification as the only route, rebuild
      // the authenticated home instead of leaving a terminal call on screen.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const ChatHomePage()),
        (_) => false,
      );
    }
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
    _stopRingingVibration();
    _pulseController.dispose();
    CallManager.instance.isCallActive = false;
    unawaited(NativeCallNotificationService.end(_activeCallId));
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _answerCall() async {
    if (_hasEnded) return;
    _timeoutTimer?.cancel();
    _stopRingingVibration();

    // 1. Respuesta visual instantánea al toque
    setState(() {
      _isIncomingRinging = false;
      _isConnected = true;
      _statusMessage = 'Conectado';
    });
    _startTimer();

    // Notificar al emisor mediante la conversación protegida por RLS.
    if (_activeConversationId != null) {
      try {
        await _callService.acceptCall(
          conversationId: _activeConversationId!,
          callId: _activeCallId,
        );
      } catch (e) {
        debugPrint('Error accepting incoming call: $e');
        if (mounted) {
          _handleCallTerminated('No se pudo aceptar', wasConnected: false);
        }
      }
    }
  }

  Future<void> _rejectIncomingCall() async {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();
    _stopRingingVibration();
    CallManager.instance.isCallActive = false;
    await NativeCallNotificationService.end(_activeCallId);

    // Notificar al emisor mediante la conversación protegida por RLS.
    if (_activeConversationId != null) {
      try {
        await _callService.rejectCall(
          conversationId: _activeConversationId!,
          callId: _activeCallId,
        );
      } catch (e) {
        debugPrint('Error rejecting incoming call: $e');
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_hasEnded) return;
    _hasEnded = true;
    _timer?.cancel();
    _statusPollTimer?.cancel();
    _timeoutTimer?.cancel();
    _stopRingingVibration();
    CallManager.instance.isCallActive = false;

    final dur = _seconds;
    final conn = _isConnected;

    // Notificar al otro usuario mediante la conversación protegida por RLS.
    if (_activeConversationId != null) {
      try {
        await _callService.endCall(
          conversationId: _activeConversationId!,
          callId: _activeCallId,
          durationSeconds: dur,
          wasConnected: conn,
          callType: widget.callType == CallType.video ? 'video' : 'audio',
        );
      } catch (e) {
        debugPrint('Error ending call: $e');
      }
    }
    if (mounted) Navigator.of(context).pop();
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
                        Icon(Icons.videocam_rounded,
                            size: 80,
                            color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text(
                          'Cámara segura activa',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 14),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        _isConnected
                            ? Icons.lock_rounded
                            : Icons.lock_outline_rounded,
                        size: 14,
                        color: _isConnected
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isConnected
                            ? 'Señalización conectada (sin audio/video)'
                            : 'Estableciendo señalización...',
                        style: TextStyle(
                          color: _isConnected
                              ? AppColors.success
                              : AppColors.primary,
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
                        : (_statusMessage.contains('rechazada') ||
                                _statusMessage.contains('Sin respuesta')
                            ? AppColors.error
                            : AppColors.primary),
                    fontSize: _isConnected ? 22 : 16,
                    fontWeight:
                        _isConnected ? FontWeight.bold : FontWeight.w600,
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
                            color: (_isConnected
                                    ? AppColors.success
                                    : AppColors.primary)
                                .withValues(alpha: _isConnected ? 0.35 : 0.2),
                            blurRadius: 36,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 64,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: widget.avatarUrl != null &&
                                widget.avatarUrl!.isNotEmpty
                            ? NetworkImage(widget.avatarUrl!)
                            : null,
                        child: widget.avatarUrl == null ||
                                widget.avatarUrl!.isEmpty
                            ? Text(
                                widget.contactName.isNotEmpty
                                    ? widget.contactName.characters.first
                                        .toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 42,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                  ),
                const Spacer(flex: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161C24),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: _isIncomingRinging
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CallControlButton(
                              icon: Icons.call_end_rounded,
                              label: 'Rechazar',
                              backgroundColor: AppColors.error,
                              iconColor: Colors.white,
                              onTap: _rejectIncomingCall,
                            ),
                            _CallControlButton(
                              icon: Icons.call_rounded,
                              label: 'Contestar',
                              backgroundColor: AppColors.success,
                              iconColor: Colors.white,
                              onTap: _answerCall,
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CallActionButton(
                              icon: _isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              label: _isMuted ? 'Silenciado' : 'Silenciar',
                              isActive: _isMuted,
                              onPressed: () =>
                                  setState(() => _isMuted = !_isMuted),
                            ),
                            _CallActionButton(
                              icon: _isSpeakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_down_rounded,
                              label: _isSpeakerOn ? 'Altavoz' : 'Auricular',
                              isActive: _isSpeakerOn,
                              onPressed: () =>
                                  setState(() => _isSpeakerOn = !_isSpeakerOn),
                            ),
                            if (widget.callType == CallType.video)
                              _CallActionButton(
                                icon: _isVideoEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                label: 'Cámara',
                                isActive: _isVideoEnabled,
                                onPressed: () => setState(
                                    () => _isVideoEnabled = !_isVideoEnabled),
                              ),
                            _CallControlButton(
                              icon: Icons.call_end_rounded,
                              label: 'Colgar',
                              backgroundColor: AppColors.error,
                              iconColor: Colors.white,
                              onTap: _endCall,
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

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          elevation: 6,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: iconColor, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
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
