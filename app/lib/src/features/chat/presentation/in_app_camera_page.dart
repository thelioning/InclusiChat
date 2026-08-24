import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class InAppCameraPage extends StatefulWidget {
  const InAppCameraPage({super.key});

  @override
  State<InAppCameraPage> createState() => _InAppCameraPageState();
}

class _InAppCameraPageState extends State<InAppCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      _initializeCamera();
    }
  }

  Future<void> _loadCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException(
          'no_camera',
          'No se encontró una cámara disponible.',
        );
      }
      final backIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIndex < 0 ? 0 : backIndex;
      await _initializeCamera();
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = error.description ?? 'No se pudo iniciar la cámara.';
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameras.isEmpty) return;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (error) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = error.description ?? 'No se pudo iniciar la cámara.';
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El flash no está disponible.')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_capturing || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _flashMode = FlashMode.off;
    await _initializeCamera();
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(photo.path);
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.description ?? 'No se pudo tomar la foto.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            _CameraPreviewFill(controller: controller)
          else
            Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : const CircularProgressIndicator(color: AppColors.primary),
            ),
          const _CameraOverlayGradient(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: _CameraControlButton(
                  tooltip: 'Cerrar cámara',
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topRight,
                child: _CameraControlButton(
                  tooltip: _flashMode == FlashMode.auto
                      ? 'Flash automático'
                      : 'Flash apagado',
                  icon: _flashMode == FlashMode.auto
                      ? Icons.flash_auto_rounded
                      : Icons.flash_off_rounded,
                  onPressed: _toggleFlash,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 138,
                padding: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.56),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 52),
                    GestureDetector(
                      onTap: _initializing ? null : _takePicture,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 82,
                        height: 82,
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          gradient: AppColors.brandGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x88CD1AE9),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _capturing ? Colors.white54 : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26, width: 2),
                          ),
                        ),
                      ),
                    ),
                    _CameraControlButton(
                      tooltip: 'Cambiar cámara',
                      icon: Icons.cameraswitch_rounded,
                      onPressed: _cameras.length > 1 ? _switchCamera : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewFill extends StatelessWidget {
  const _CameraPreviewFill({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    var scale = screen.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }
}

class _CameraOverlayGradient extends StatelessWidget {
  const _CameraOverlayGradient();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x99000000),
              Colors.transparent,
              Colors.transparent,
              Color(0x66000000),
            ],
            stops: [0, 0.22, 0.68, 1],
          ),
        ),
      ),
    );
  }
}

class _CameraControlButton extends StatelessWidget {
  const _CameraControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.58),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      elevation: 8,
      shadowColor: Colors.black87,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: Colors.white,
        disabledColor: Colors.white30,
        icon: Icon(icon),
      ),
    );
  }
}
