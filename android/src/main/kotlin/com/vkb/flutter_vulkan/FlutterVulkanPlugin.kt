package com.vkb.flutter_vulkan

import io.flutter.embedding.engine.plugins.FlutterPlugin

class FlutterVulkanPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE_ID,
            VulkanViewFactory(binding.binaryMessenger),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    companion object {
        const val VIEW_TYPE_ID = "com.vkb/vulkan_view"

        init {
            // Loads libflutter_vulkan.so which contains both the JNI bridge
            // and all vkb_* symbols (vulkan_bridge + renderer3d compiled in).
            System.loadLibrary("flutter_vulkan")
        }
    }
}
