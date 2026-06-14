/// flutter_vulkan — Vulkan rendering inside Flutter with native UI overlay.
///
/// ## Typical usage
/// ```dart
/// import 'package:flutter_vulkan/flutter_vulkan.dart';
/// import 'package:dart_vulkan/dart_vulkan.dart';
///
/// class MyGame extends FlutterVulkanGame {
///   late Renderer3D _r;
///   late Mesh _cube;
///
///   @override
///   Future<void> onLoad(FlutterVulkanContext ctx) async {
///     _r   = ctx.createRenderer(); // platform-agnostic: Android or Windows
///     _cube = Mesh.cube();
///   }
///
///   @override
///   void onRenderFrame(ffi.DynamicLibrary lib, int w, int h) {
///     if (!_r.beginFrame()) return;
///     _r.drawMesh(_cube, mvp: camera.viewProjection(w / h));
///     _r.endFrame();
///   }
/// }
///
/// // In your widget tree:
/// Stack(children: [
///   VulkanGameView(game: MyGame()),
///   Positioned(bottom: 16, child: FlutterHUD()),   // Flutter UI on top
/// ])
/// ```
library;

export 'src/flutter_vulkan_game.dart' show FlutterVulkanGame, FlutterVulkanContext;
export 'src/vulkan_view.dart'         show VulkanGameView;
export 'package:dart_vulkan/dart_vulkan.dart' show GpuInfo, VulkanDeviceType;
