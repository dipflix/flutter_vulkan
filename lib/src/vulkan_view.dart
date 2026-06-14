import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'flutter_vulkan_game.dart';

/// A Flutter widget that hosts Vulkan rendering.
///
/// On **Android** it embeds a native `SurfaceView` via Hybrid Composition.
/// On **Windows** it uses a Flutter `Texture` widget backed by an offscreen
/// Vulkan renderer (pixel-buffer readback each frame).
///
/// Stack Flutter widgets on top normally — they are composited by Flutter:
/// ```dart
/// Stack(children: [
///   VulkanGameView(game: MyGame()),
///   Positioned(bottom: 16, right: 16, child: FloatingActionButton(...)),
/// ])
/// ```
class VulkanGameView extends StatefulWidget {
  final FlutterVulkanGame game;

  const VulkanGameView({super.key, required this.game});

  @override
  State<VulkanGameView> createState() => _VulkanGameViewState();
}

class _VulkanGameViewState extends State<VulkanGameView> {
  MethodChannel? _channel;

  // Windows-specific state
  int?   _textureId;
  bool   _initializing = false;
  bool   _resizing     = false;
  int    _lastW        = 0;
  int    _lastH        = 0;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: 'com.vkb/vulkan_view',
        onPlatformViewCreated: _onViewCreated,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    if (Platform.isWindows) {
      return LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth.toInt();
        final h = constraints.maxHeight.toInt();
        if (!_initializing && _textureId == null && w > 0 && h > 0) {
          _initWindows(w, h);
        } else if (_textureId != null && !_resizing &&
                   (w != _lastW || h != _lastH) && w > 0 && h > 0) {
          debugPrint('[VulkanGameView] resize: ${_lastW}x$_lastH → ${w}x$h');
          _resizeWindows(w, h);
        }
        if (_textureId == null) return const SizedBox.expand();
        return Texture(textureId: _textureId!);
      });
    }

    return const Center(
      child: Text('VulkanGameView: unsupported platform'),
    );
  }

  Future<void> _initWindows(int w, int h) async {
    _initializing = true;
    await widget.game.surfaceCreatedInternal(
      nativeWindow: 0,
      width: w,
      height: h,
    );
    if (mounted) {
      setState(() {
        _textureId = widget.game.windowsTextureIdInternal;
        _lastW = w;
        _lastH = h;
      });
    }
  }

  Future<void> _resizeWindows(int w, int h) async {
    _resizing = true;
    _lastW = w;
    _lastH = h;
    try {
      await widget.game.surfaceResizedWindowsInternal(w, h);
    } finally {
      if (mounted) setState(() => _resizing = false);
    }
  }

  // ---- Android callbacks ---------------------------------------------------

  void _onViewCreated(int id) {
    _channel = MethodChannel('com.vkb/vulkan_view_$id');
    _channel!.setMethodCallHandler(_onMethodCall);
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'surfaceCreated':
        final args = call.arguments as Map;
        await widget.game.surfaceCreatedInternal(
          nativeWindow: args['nativeWindow'] as int,
          width:  args['width']  as int,
          height: args['height'] as int,
        );

      case 'surfaceChanged':
        final args = call.arguments as Map;
        widget.game.surfaceChangedInternal(
          args['width']  as int,
          args['height'] as int,
        );

      case 'surfaceDestroyed':
        widget.game.surfaceDestroyedInternal();
    }
  }

  @override
  void dispose() {
    widget.game.surfaceDestroyedInternal();
    super.dispose();
  }
}
