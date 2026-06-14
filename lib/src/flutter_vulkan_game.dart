import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:dart_vulkan/dart_vulkan.dart' show Renderer3D, GpuInfo;
// ignore: always_use_package_imports
import 'vulkan_flutter_loader.dart';

/// Surface info and loaded shader bytes passed to [FlutterVulkanGame.onLoad].
///
/// Use [createRenderer] for a platform-agnostic way to create a renderer:
/// - Android: creates via `vkb_renderer3d_create_android` (ANativeWindow path)
/// - Windows/desktop: wraps a pre-created offscreen renderer pointer
class FlutterVulkanContext {
  final ffi.DynamicLibrary lib;

  /// Platform-specific surface handle:
  /// - Android: `ANativeWindow*` as an integer
  /// - Windows: pointer to the pre-created offscreen `VkbRenderer3D`
  final int nativeWindow;
  final int width;
  final int height;

  /// Compiled SPIR-V for the vertex shader.
  final Uint8List vertSpv;

  /// Compiled SPIR-V for the fragment shader.
  final Uint8List fragSpv;

  /// GPU index passed from [FlutterVulkanGame.gpuIndex]. -1 = auto.
  final int gpuIndex;

  const FlutterVulkanContext({
    required this.lib,
    required this.nativeWindow,
    required this.width,
    required this.height,
    required this.vertSpv,
    required this.fragSpv,
    this.gpuIndex = -1,
  });

  /// Creates a [Renderer3D] in the correct way for the current platform.
  ///
  /// Call this inside [FlutterVulkanGame.onLoad] rather than constructing a
  /// renderer directly — it handles the Android vs. desktop differences.
  Renderer3D createRenderer() {
    if (Platform.isAndroid) {
      return Renderer3D.createForAndroid(
        lib,
        nativeWindow: nativeWindow,
        width: width,
        height: height,
        vertSpv: vertSpv,
        fragSpv: fragSpv,
        gpuIndex: gpuIndex,
      );
    }
    // Windows / Linux desktop: nativeWindow is the pre-created renderer ptr.
    return Renderer3D.fromPointer(lib, nativeWindow);
  }
}

/// Abstract base for a Vulkan game running inside a [VulkanGameView].
///
/// Subclass this, implement [onLoad], [onUpdate], and [onRenderFrame], then
/// pass an instance to [VulkanGameView].
///
/// Flutter widgets placed above [VulkanGameView] in the widget tree are
/// composited natively on top of the Vulkan surface — no ImGui needed.
///
/// ```dart
/// class MyGame extends FlutterVulkanGame {
///   late Renderer3D _r;
///
///   @override
///   Future<void> onLoad(FlutterVulkanContext ctx) async {
///     _r = ctx.createRenderer();
///   }
///
///   @override
///   void onRenderFrame(ffi.DynamicLibrary lib, int w, int h) {
///     if (!_r.beginFrame()) return;
///     _r.drawMesh(mesh, mvp: camera.viewProjection(w / h));
///     _r.endFrame();
///   }
/// }
/// ```
abstract class FlutterVulkanGame {
  // ---- overrideable contract -----------------------------------------------

  /// Flutter asset path for the vertex SPIR-V.
  String get vertShaderAsset => 'assets/shaders/mesh3d.vert.spv';

  /// Flutter asset path for the fragment SPIR-V.
  String get fragShaderAsset => 'assets/shaders/mesh3d.frag.spv';

  /// GPU index to use for rendering (0-based, matching [enumerateGpus]).
  /// Set to -1 (default) for automatic selection (prefers discrete GPU).
  int get gpuIndex => -1;

  /// Returns all Vulkan-capable GPUs on this system.
  ///
  /// Call this before creating the game to populate a GPU selection UI.
  /// The returned [GpuInfo.index] can be passed to [gpuIndex].
  static List<GpuInfo> enumerateGpus() =>
      Renderer3D.enumerateGpus(VulkanFlutterLoader.openLib());

  /// Called once after the Vulkan surface is ready and shaders are loaded.
  Future<void> onLoad(FlutterVulkanContext ctx) async {}

  /// Called every frame before rendering. [dt] is seconds since last frame.
  void onUpdate(double dt) {}

  /// Perform all Vulkan draw calls for this frame.
  void onRenderFrame(ffi.DynamicLibrary lib, int width, int height) {}

  /// Called when the surface is resized.
  void onResize(int width, int height) {}

  // ---- internal state ------------------------------------------------------

  ffi.DynamicLibrary? _lib;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  int _surfaceWidth  = 0;
  int _surfaceHeight = 0;
  bool _running      = false;

  // Windows-specific fields
  int _windowsTextureId              = -1;
  void Function(int)? _flushFn;
  bool _resizePending                = false;

  /// Read by [VulkanGameView] on Windows after [surfaceCreatedInternal] returns.
  // ignore: library_private_types_in_public_api
  int get windowsTextureIdInternal => _windowsTextureId;

  // ---- internal surface callbacks (called by VulkanGameView) ---------------
  // Not prefixed with _ so vulkan_view.dart (a different library file) can call them.

  // ignore: library_private_types_in_public_api
  Future<void> surfaceCreatedInternal({
    required int nativeWindow, // Android: ANativeWindow*; Windows: pass 0
    required int width,
    required int height,
  }) async {
    _surfaceWidth  = width;
    _surfaceHeight = height;

    final lib = VulkanFlutterLoader.openLib();
    _lib = lib;

    final vertData = await rootBundle.load(vertShaderAsset);
    final fragData = await rootBundle.load(fragShaderAsset);
    final vertSpv  = vertData.buffer.asUint8List();
    final fragSpv  = fragData.buffer.asUint8List();

    int effectiveNativeWindow = nativeWindow;

    if (Platform.isWindows) {
      // Create the offscreen renderer that the game will use for rendering.
      final offRenderer = Renderer3D.createOffscreen(
        lib,
        width: width, height: height,
        vertSpv: vertSpv, fragSpv: fragSpv,
        gpuIndex: gpuIndex,
      );
      effectiveNativeWindow = offRenderer.handleAddress;
      // The game will wrap this pointer via ctx.createRenderer() → fromPointer.
      // offRenderer Dart object goes out of scope here (no dispose), keeping
      // the underlying C++ object alive for the game to own.

      // Register the renderer with the Flutter texture system.
      const channel = MethodChannel('com.vkb/flutter_vulkan');
      final result = await channel.invokeMapMethod<String, dynamic>(
        'registerTexture',
        {
          'rendererPtr': effectiveNativeWindow,
          'width': width,
          'height': height,
        },
      );
      _windowsTextureId = result!['textureId'] as int;

      // Resolve the per-frame flush function from the plugin DLL.
      try {
        final pluginLib =
            ffi.DynamicLibrary.open('flutter_vulkan_plugin.dll');
        _flushFn = pluginLib.lookupFunction<
            ffi.Void Function(ffi.Int64),
            void Function(int)>('vkb_windows_flush_frame');
      } catch (_) {
        // flush silently absent — texture won't update, but won't crash
      }
    }

    final ctx = FlutterVulkanContext(
      lib:          lib,
      nativeWindow: effectiveNativeWindow,
      width:        width,
      height:       height,
      vertSpv:      vertSpv,
      fragSpv:      fragSpv,
      gpuIndex:     gpuIndex,
    );

    await onLoad(ctx);
    _startLoop();
  }

  void surfaceChangedInternal(int width, int height) {
    _surfaceWidth  = width;
    _surfaceHeight = height;
    onResize(width, height);
  }

  /// Windows-only: resize the offscreen Vulkan target and Flutter texture.
  /// Pauses the render loop for the duration to avoid Vulkan concurrency issues.
  ///
  /// The plugin calls `vkb_renderer3d_resize` directly, so games must NOT
  /// also call `_renderer.onResize` inside their [onResize] override on Windows
  /// — that would cause a redundant (and potentially crashing) double resize.
  Future<void> surfaceResizedWindowsInternal(int width, int height) async {
    if (!Platform.isWindows || _windowsTextureId == -1) return;
    _resizePending = true;
    try {
      const channel = MethodChannel('com.vkb/flutter_vulkan');
      await channel.invokeMethod<void>('resizeTexture', {
        'textureId': _windowsTextureId,
        'width': width,
        'height': height,
      });
      _surfaceWidth  = width;
      _surfaceHeight = height;
      // Do NOT call onResize here: the plugin already called vkb_renderer3d_resize.
      // Calling it again from the game's onResize would double-resize the renderer.
    } finally {
      _resizePending = false;
    }
  }

  void surfaceDestroyedInternal() {
    _stopLoop();
    if (Platform.isWindows && _windowsTextureId != -1) {
      const MethodChannel('com.vkb/flutter_vulkan').invokeMethod<void>(
        'unregisterTexture',
        {'textureId': _windowsTextureId},
      );
      _windowsTextureId = -1;
    }
    _flushFn = null;
    _lib     = null;
  }

  /// Release all Vulkan resources and stop the game loop.
  /// Override in subclasses to also free meshes, textures, etc.
  void dispose() {
    surfaceDestroyedInternal();
  }

  // ---- game loop -----------------------------------------------------------

  void _startLoop() {
    _running  = true;
    _lastTick = Duration.zero;
    _ticker   = Ticker(_tick)..start();
  }

  void _stopLoop() {
    _running = false;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  void _tick(Duration elapsed) {
    if (!_running || _lib == null || _resizePending) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    onUpdate(dt);
    onRenderFrame(_lib!, _surfaceWidth, _surfaceHeight);
    _flushFn?.call(_windowsTextureId);
  }
}
