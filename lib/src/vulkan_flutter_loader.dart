import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:vulkan_bridge/vulkan_bridge.dart';

// ignore: avoid_classes_with_only_static_members
class VulkanFlutterLoader {
  /// Returns bindings loaded from the single `libflutter_vulkan.so` that the
  /// Android plugin registers. On all other platforms falls back to the
  /// standard desktop vulkan_bridge loader.
  static VulkanBridgeBindings loadBridge() {
    if (Platform.isAndroid) {
      // System.loadLibrary("flutter_vulkan") was already called by the Kotlin
      // plugin initializer, so the library is in the process image.
      return VulkanBridgeBindings(
          ffi.DynamicLibrary.open('libflutter_vulkan.so'));
    }
    return loadVulkanBridge();
  }

  static ffi.DynamicLibrary openLib() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libflutter_vulkan.so');
    }
    // Desktop: vkb_game.dll already loaded by Game._openGameLib(); just reuse.
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('vkb_game.dll');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libvkb_game.so');
    }
    if (Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libvkb_game.dylib');
    }
    return ffi.DynamicLibrary.process();
  }
}
