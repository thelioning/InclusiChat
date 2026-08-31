import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import 'call_screen.dart';
import 'conversation_photo_preview_page.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.conversationId,
    required this.title,
    this.avatarUrl,
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _service = ChatService();
  final Set<String> _markedRead = {};
  bool _sending = false;
  bool _hasText = false;
  bool _showJumpToLatest = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
  }

  void _onScroll() {
    final show =
        _scrollController.hasClients &&
        (_scrollController.position.maxScrollExtent -
                _scrollController.position.pixels) >
            180;
    if (show != _showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = show);
    }
  }

  void _jumpToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _keepLatestMessageVisible(int messageCount) {
    if (messageCount == _lastMessageCount) return;
    _lastMessageCount = messageCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isSubmitting = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSubmitting) return;
    _isSubmitting = true;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await _service.sendTextMessage(
        conversationId: widget.conversationId,
        content: text,
      );
    } catch (e) {
      _controller.text = text;
      if (mounted) {
        final cleanErr = e.toString()
            .replaceAll('Exception:', '')
            .replaceAll('PostgrestException', '')
            .replaceAll('(message:', '')
            .trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cleanErr.isNotEmpty ? cleanErr : 'No se pudo enviar el mensaje.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      _isSubmitting = false;
      if (mounted) setState(() => _sending = false);
    }
  }

  void _markIncomingMessagesRead(List<Map<String, dynamic>> messages) {
    final unreadIds = messages
        .where((message) => !_service.isOwnMessage(message))
        .map((message) => message['id'] as String)
        .where(_markedRead.add)
        .toList();
    if (unreadIds.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final id in unreadIds) {
        try {
          await _service.markMessageRead(id);
        } catch (_) {
          _markedRead.remove(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: AppColors.secondary,
              backgroundImage: widget.avatarUrl == null
                  ? null
                  : NetworkImage(widget.avatarUrl!),
              child: widget.avatarUrl == null
                  ? Text(
                      widget.title.characters.first.toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Videollamada',
            onPressed: () async {
              final otherId = await _service.getOtherParticipantId(widget.conversationId);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CallScreen(
                      contactName: widget.title,
                      avatarUrl: widget.avatarUrl,
                      receiverUserId: otherId,
                      conversationId: widget.conversationId,
                      callType: CallType.video,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Llamada de voz',
            onPressed: () async {
              final otherId = await _service.getOtherParticipantId(widget.conversationId);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CallScreen(
                      contactName: widget.title,
                      avatarUrl: widget.avatarUrl,
                      receiverUserId: otherId,
                      conversationId: widget.conversationId,
                      callType: CallType.audio,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.call_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (value) {
              if (value == 'info') _showChatInfo();
              if (value == 'mute') _toggleMute();
              if (value == 'clear') _confirmClearChat();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 12),
                    Text('Información del contacto'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'mute',
                child: Row(
                  children: [
                    Icon(Icons.notifications_off_outlined),
                    SizedBox(width: 12),
                    Text('Silenciar / activar notificaciones'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, color: AppColors.error),
                    SizedBox(width: 12),
                    Text('Vaciar conversación', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _service.watchMessages(widget.conversationId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('No se pudieron cargar los mensajes.'),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rawMessages = snapshot.data ?? const [];
                      final seenIds = <String>{};
                      final messages = <Map<String, dynamic>>[];
                      for (final m in rawMessages) {
                        final id = m['id'] as String?;
                        final meta = m['metadata'];
                        if (meta is Map && meta['call_signal'] == true) {
                          final action = meta['action'] as String?;
                          if (action != 'end') {
                            continue;
                          }
                        }
                        if (id != null && seenIds.add(id)) {
                          messages.add(m);
                        }
                      }
                      messages.sort(
                        (a, b) => DateTime.parse(a['created_at'] as String)
                            .compareTo(
                              DateTime.parse(b['created_at'] as String),
                            ),
                      );
                      _markIncomingMessagesRead(messages);
                      _keepLatestMessageVisible(messages.length);
                      if (messages.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Esta conversación comienza aquí.\nEnvía un saludo seguro.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _service.watchReceipts(),
                        builder: (context, receiptSnapshot) {
                          final receiptStatus = <String, String>{};
                          for (final receipt
                              in receiptSnapshot.data ??
                                  const <Map<String, dynamic>>[]) {
                            final messageId = receipt['message_id'] as String;
                            final status = receipt['status'] as String;
                            if (status == 'read' ||
                                receiptStatus[messageId] == null) {
                              receiptStatus[messageId] = status;
                            }
                          }
                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              final own = _service.isOwnMessage(message);
                              return _MessageBubble(
                                messageId: message['id'] as String,
                                content: message['content'] as String? ?? '',
                                type: message['type'] as String?,
                                metadata: message['metadata'] as Map?,
                                own: own,
                                createdAt: DateTime.parse(
                                  message['created_at'] as String,
                                ),
                                receiptStatus: receiptStatus[message['id']],
                                onLongPress: () => _showMessageOptions(message, own),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_showJumpToLatest)
                  Positioned(
                    right: 14,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'jumpToLatest',
                      tooltip: 'Ir al mensaje más reciente',
                      onPressed: _jumpToLatest,
                      backgroundColor: AppColors.surfaceRaised,
                      child: const Icon(
                        Icons.keyboard_double_arrow_down_rounded,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Emoji rápido',
                          onPressed: _showQuickEmojiPicker,
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              if (_hasText && !_isSubmitting) _send();
                            },
                            decoration: const InputDecoration(
                              hintText: 'Mensaje',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Adjuntar archivo',
                          onPressed: _showAttachmentMenu,
                          icon: const Icon(Icons.attach_file_rounded),
                        ),
                        IconButton(
                          tooltip: 'Tomar foto',
                          onPressed: () => _pickAndSendImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: _hasText ? 'Enviar' : 'Mensaje de voz',
                    onPressed: _sending
                        ? null
                        : _hasText
                        ? _send
                        : _showVoiceNoteRecorder,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _hasText ? Icons.send_rounded : Icons.mic_rounded,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatInfo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.secondary,
              backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
              child: widget.avatarUrl == null
                  ? Text(
                      widget.title.isNotEmpty ? widget.title.characters.first.toUpperCase() : '?',
                      style: const TextStyle(fontSize: 28, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Contacto Verificado • InclusiChat',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mensajería con aislamiento de datos y cifrado en tránsito.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMute() async {
    try {
      final current = await _service.isConversationMuted(widget.conversationId);
      final next = !current;
      await _service.setConversationMuted(widget.conversationId, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Notificaciones silenciadas para esta conversación.'
                : 'Notificaciones activadas para esta conversación.',
          ),
          backgroundColor: AppColors.surfaceRaised,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cambiar la configuración de notificaciones.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmClearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar conversación'),
        content: const Text('¿Estás seguro de que deseas limpiar los mensajes de este chat?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversación vaciada.'),
          backgroundColor: AppColors.surfaceRaised,
        ),
      );
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachmentOption(
                icon: Icons.image_rounded,
                color: Colors.purpleAccent,
                label: 'Galería',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              _AttachmentOption(
                icon: Icons.camera_alt_rounded,
                color: Colors.pinkAccent,
                label: 'Cámara',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              _AttachmentOption(
                icon: Icons.insert_drive_file_rounded,
                color: Colors.blueAccent,
                label: 'Documento',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _sendTextMessage('📄 Documento seguro adjunto');
                },
              ),
              _AttachmentOption(
                icon: Icons.location_on_rounded,
                color: Colors.greenAccent,
                label: 'Ubicación',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _sendTextMessage('📍 Ubicación segura compartida');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (file == null || !mounted) return;

      final initialCaption = _controller.text.trim();
      final preview = await Navigator.of(context)
          .push<ConversationPhotoPreviewResult>(
        MaterialPageRoute<ConversationPhotoPreviewResult>(
          builder: (_) => ConversationPhotoPreviewPage(
            imagePath: file.path,
            initialCaption: initialCaption,
          ),
        ),
      );

      if (preview == null || !mounted) return;

      setState(() => _sending = true);
      final imageUrl = await _service.uploadImageFile(file.path);

      await _service.sendImageMessage(
        conversationId: widget.conversationId,
        imageUrl: imageUrl,
        caption: preview.caption.isNotEmpty ? preview.caption : null,
      );

      _controller.clear();
      _onTextChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo enviar la foto.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendTextMessage(String text) async {
    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        conversationId: widget.conversationId,
        content: text,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAudioVoiceNote(String filePath, int durationSeconds) async {
    setState(() => _sending = true);
    try {
      final audioUrl = await _service.uploadAudioFile(filePath);
      await _service.sendAudioMessage(
        conversationId: widget.conversationId,
        audioUrl: audioUrl,
        durationSeconds: durationSeconds,
      );
      _jumpToLatest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar nota de voz: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showVoiceNoteRecorder() {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _VoiceRecorderModal(
        onSend: _sendAudioVoiceNote,
      ),
    );
  }

  void _showQuickEmojiPicker() {
    final emojis = ['💜', '🏳️‍🌈', '✨', '👋', '❤️', '😊', '🔒', '🫂', '🔥', '👏'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: emojis.map((e) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(ctx).pop();
              _controller.text += e;
              _onTextChanged();
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(e, style: const TextStyle(fontSize: 28)),
            ),
          )).toList(),
        ),
      ),
    );
  }
  void _showMessageOptions(Map<String, dynamic> message, bool own) {
    final messageId = message['id'] as String;
    final content = message['content'] as String? ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              const Divider(height: 16),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppColors.primary),
                title: const Text('Copiar texto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mensaje copiado al portapapeles.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('Eliminar para mí', style: TextStyle(color: AppColors.error)),
                subtitle: const Text('Se eliminará únicamente de tu chat'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _service.deleteMessageForMe(messageId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mensaje eliminado para ti.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
              if (own)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                  title: const Text(
                    'Eliminar para todos',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Se eliminará para ti y para el destinatario'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _service.deleteMessageForEveryone(messageId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mensaje eliminado para todos.'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceRecorderModal extends StatefulWidget {
  const _VoiceRecorderModal({
    required this.onSend,
  });

  final Future<void> Function(String filePath, int durationSeconds) onSend;

  @override
  State<_VoiceRecorderModal> createState() => _VoiceRecorderModalState();
}

class _VoiceRecorderModalState extends State<_VoiceRecorderModal> with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  bool _isUploading = false;
  String? _recordedPath;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se requiere permiso de micrófono para grabar notas de voz.')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      if (mounted) {
        setState(() {
          _recordedPath = path;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _seconds++);
          }
        });
      }
    } catch (e) {
      debugPrint('Recording start error: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _stopAndDiscard() async {
    _timer?.cancel();
    try {
      await _recorder.stop();
      if (_recordedPath != null) {
        final file = File(_recordedPath!);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    final duration = _seconds > 0 ? _seconds : 1;
    setState(() => _isUploading = true);
    try {
      final path = await _recorder.stop();
      final finalPath = path ?? _recordedPath;
      if (finalPath != null && File(finalPath).existsSync()) {
        await widget.onSend(finalPath, duration);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Error sending voice note: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar la nota de voz: $e')),
        );
      }
    }
  }

  String get _formattedTime {
    final m = _seconds ~/ 60;
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isUploading) ...[
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              'Enviando nota de voz...',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ] else ...[
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (ctx, child) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15 + (_animCtrl.value * 0.15)),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: _animCtrl.value * 0.3),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 36),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _formattedTime,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 4),
            const Text(
              'Grabando nota de voz segura...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: _stopAndDiscard,
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  label: const Text('Descartar', style: TextStyle(color: AppColors.error)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: _stopAndSend,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Enviar nota'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AudioPlayerBubble extends StatefulWidget {
  const _AudioPlayerBubble({
    required this.audioUrl,
    required this.durationSeconds,
    required this.own,
  });

  final String audioUrl;
  final int durationSeconds;
  final bool own;

  @override
  State<_AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<_AudioPlayerBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _totalDuration = Duration(seconds: widget.durationSeconds);

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
        });
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() {
          _totalDuration = dur;
        });
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(widget.audioUrl));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final currentMs = _position.inMilliseconds.toDouble();
    final totalMs = _totalDuration.inMilliseconds.toDouble();
    final maxMs = totalMs > 0 ? totalMs : 1.0;
    final valueMs = currentMs.clamp(0.0, maxMs);

    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: widget.own ? Colors.white24 : AppColors.primary.withValues(alpha: 0.2),
            child: IconButton(
              iconSize: 22,
              padding: EdgeInsets.zero,
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.own ? Colors.white : AppColors.primary,
              ),
              onPressed: _togglePlay,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    activeTrackColor: widget.own ? Colors.white : AppColors.primary,
                    inactiveTrackColor: widget.own ? Colors.white24 : Colors.white12,
                    thumbColor: widget.own ? Colors.white : AppColors.primary,
                  ),
                  child: Slider(
                    value: valueMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (val) async {
                      final newPos = Duration(milliseconds: val.toInt());
                      await _player.seek(newPos);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isPlaying ? _formatDuration(_position) : _formatDuration(_totalDuration),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.own ? Colors.white70 : AppColors.textSecondary,
                        ),
                      ),
                      Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: widget.own ? Colors.white70 : AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.messageId,
    required this.content,
    this.type,
    this.metadata,
    required this.own,
    required this.createdAt,
    this.receiptStatus,
    required this.onLongPress,
  });

  final String messageId;
  final String content;
  final String? type;
  final Map<dynamic, dynamic>? metadata;
  final bool own;
  final DateTime createdAt;
  final String? receiptStatus;
  final VoidCallback onLongPress;

  void _openFullPhoto(BuildContext context, {String? imageUrl, String? imageBase64}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          );
                        },
                      )
                    : Image.memory(
                        base64Decode(imageBase64!),
                        fit: BoxFit.contain,
                      ),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? imageUrl;
    String? imageBase64;
    String? caption;
    String? audioUrl;
    int? audioDuration;
    String displayContent = content;

    if (content.startsWith('{')) {
      try {
        final decoded = jsonDecode(content) as Map;
        if (decoded.containsKey('audio_url')) {
          audioUrl = decoded['audio_url'] as String?;
          audioDuration = decoded['duration'] as int?;
        } else if (decoded.containsKey('image_url') || decoded.containsKey('image_base64')) {
          imageUrl = decoded['image_url'] as String?;
          imageBase64 = decoded['image_base64'] as String?;
          caption = (decoded['caption'] as String?)?.trim();
        }
      } catch (_) {}
    } else if (content.contains('[IMAGE_URL]')) {
      final clean = content.replaceAll('📷 [IMAGE_URL]', '').replaceAll('[IMAGE_URL]', '');
      final parts = clean.split('|||');
      imageUrl = parts[0].trim();
      if (parts.length > 1) caption = parts[1].trim();
    } else if (metadata != null) {
      audioUrl = metadata!['audio_url'] as String?;
      audioDuration = metadata!['duration'] as int?;
      imageUrl = metadata!['image_url'] as String?;
      imageBase64 = metadata!['image_base64'] as String?;
      caption = (metadata!['caption'] as String?)?.trim();
    }

    final hasImage = (imageUrl != null && imageUrl.isNotEmpty) ||
                     (imageBase64 != null && imageBase64.isNotEmpty);
    final hasAudio = (audioUrl != null && audioUrl.isNotEmpty);

    final cleanCaption = (caption != null && caption.isNotEmpty)
        ? caption
        : (hasImage || hasAudio ? '' : displayContent);

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: own ? AppColors.secondary : AppColors.surfaceRaised,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(own ? 16 : 4),
              bottomRight: Radius.circular(own ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasImage) ...[
                GestureDetector(
                  onTap: () => _openFullPhoto(context, imageUrl: imageUrl, imageBase64: imageBase64),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 220,
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 220,
                                color: Colors.black26,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40),
                            ),
                          )
                        : Image.memory(
                            base64Decode(imageBase64!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 220,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40),
                            ),
                          ),
                  ),
                ),
                if (cleanCaption.isNotEmpty) const SizedBox(height: 6),
              ],
              if (hasAudio && audioUrl != null) ...[
                _AudioPlayerBubble(
                  audioUrl: audioUrl,
                  durationSeconds: audioDuration ?? 0,
                  own: own,
                ),
              ],
              if (cleanCaption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(cleanCaption),
                  ),
                ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (own) ...[
                      const SizedBox(width: 4),
                      Icon(
                        receiptStatus == 'delivered' || receiptStatus == 'read'
                            ? Icons.done_all_rounded
                            : Icons.check_rounded,
                        size: 16,
                        color: receiptStatus == 'read'
                            ? AppColors.receiptRead
                            : AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
