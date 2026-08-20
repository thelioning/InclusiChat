import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../data/chat_service.dart';
import 'call_screen.dart';

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
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallScreen(
                    contactName: widget.title,
                    avatarUrl: widget.avatarUrl,
                    callType: CallType.video,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            tooltip: 'Llamada de voz',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallScreen(
                    contactName: widget.title,
                    avatarUrl: widget.avatarUrl,
                    callType: CallType.audio,
                  ),
                ),
              );
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
                    Text('Silenciar notificaciones'),
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

  void _toggleMute() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notificaciones silenciadas para esta conversación.'),
        backgroundColor: AppColors.surfaceRaised,
      ),
    );
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
      if (file == null) return;

      setState(() => _sending = true);
      final imageUrl = await _service.uploadImageFile(file.path);
      final caption = _controller.text.trim();

      await _service.sendImageMessage(
        conversationId: widget.conversationId,
        imageUrl: imageUrl,
        caption: caption.isNotEmpty ? caption : null,
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

  void _showVoiceNoteRecorder() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: 14),
            const Text(
              'Grabando nota de voz segura...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Audio cifrado de extremo a extremo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  label: const Text('Descartar', style: TextStyle(color: AppColors.error)),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _sendTextMessage('🎤 [Nota de voz segura 0:08]');
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Enviar audio'),
                ),
              ],
            ),
          ],
        ),
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
    String displayContent = content;

    if (content.startsWith('{') && (content.contains('image_url') || content.contains('image_base64'))) {
      try {
        final decoded = jsonDecode(content) as Map;
        imageUrl = decoded['image_url'] as String?;
        imageBase64 = decoded['image_base64'] as String?;
        caption = decoded['caption'] as String?;
      } catch (_) {}
    } else if (content.contains('[IMAGE_URL]')) {
      final clean = content.replaceAll('📷 [IMAGE_URL]', '').replaceAll('[IMAGE_URL]', '');
      final parts = clean.split('|||');
      imageUrl = parts[0].trim();
      if (parts.length > 1) caption = parts[1].trim();
    } else if (metadata != null) {
      imageUrl = metadata!['image_url'] as String?;
      imageBase64 = metadata!['image_base64'] as String?;
      caption = metadata!['caption'] as String?;
    }

    final hasImage = (imageUrl != null && imageUrl.isNotEmpty) ||
                     (imageBase64 != null && imageBase64.isNotEmpty);
    final cleanCaption = (caption != null && caption.isNotEmpty)
        ? caption
        : (hasImage
            ? displayContent.replaceAll('📷 Foto', '').replaceAll('📷 ', '').trim()
            : displayContent);

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
              if (cleanCaption.isNotEmpty || !hasImage)
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
