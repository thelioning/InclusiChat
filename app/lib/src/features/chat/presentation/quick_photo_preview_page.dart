import 'dart:io';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import 'quick_share_contact_picker_page.dart';

class QuickPhotoPreviewPage extends StatefulWidget {
  const QuickPhotoPreviewPage({
    super.key,
    required this.imagePath,
  });

  final String imagePath;

  @override
  State<QuickPhotoPreviewPage> createState() => _QuickPhotoPreviewPageState();
}

class _QuickPhotoPreviewPageState extends State<QuickPhotoPreviewPage> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _proceedToContactSelection() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickShareContactPickerPage(
          imagePath: widget.imagePath,
          initialCaption: _commentController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.imagePath);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Foto a pantalla completa
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.5,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        'No se pudo cargar la imagen',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Barra superior (Botón cerrar)
            Positioned(
              top: 10,
              left: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // Barra inferior con entrada de texto y botón de continuar (estilo WhatsApp adaptado a InclusiChat)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppColors.textSecondary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              style: const TextStyle(color: Colors.white),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Añade un comentario...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Botón circular de envío (Paleta InclusiChat con icono de flecha)
                  InkWell(
                    onTap: _proceedToContactSelection,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        gradient: AppColors.brandGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x55CD1AE9),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
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
