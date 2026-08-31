import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class ConversationPhotoPreviewResult {
  const ConversationPhotoPreviewResult({required this.caption});

  final String caption;
}

class ConversationPhotoPreviewPage extends StatefulWidget {
  const ConversationPhotoPreviewPage({
    super.key,
    required this.imagePath,
    this.initialCaption = '',
  });

  final String imagePath;
  final String initialCaption;

  @override
  State<ConversationPhotoPreviewPage> createState() =>
      _ConversationPhotoPreviewPageState();
}

class _ConversationPhotoPreviewPageState
    extends State<ConversationPhotoPreviewPage> {
  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _confirmSend() {
    Navigator.of(context).pop(
      ConversationPhotoPreviewResult(
        caption: _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.imagePath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Vista previa'),
        leading: IconButton(
          tooltip: 'Cancelar',
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'No se pudo cargar la imagen.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.98),
                border: const Border(
                  top: BorderSide(color: Colors.white12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Añade un comentario...',
                        hintStyle: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceRaised,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Enviar foto',
                    onPressed: _confirmSend,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
