package com.vkb.flutter_vulkan

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * Hosts a SurfaceView and forwards the ANativeWindow* pointer to Dart once
 * the surface is ready. Dart then drives Vulkan rendering directly via FFI.
 */
class VulkanPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView, SurfaceHolder.Callback {

    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "${FlutterVulkanPlugin.VIEW_TYPE_ID}_$viewId")
    private var nativeWindowPtr: Long = 0L
    // true when surfaceCreated fired before the SurfaceView had non-zero dimensions;
    // the real surfaceCreated message is deferred until surfaceChanged provides them.
    private var pendingSurfaceCreated = false

    init {
        surfaceView.holder.addCallback(this)
    }

    // ---- PlatformView -------------------------------------------------------

    override fun getView(): View = surfaceView

    override fun dispose() {
        surfaceView.holder.removeCallback(this)
        releaseNativeWindow()
    }

    // ---- SurfaceHolder.Callback ---------------------------------------------

    override fun surfaceCreated(holder: SurfaceHolder) {
        nativeWindowPtr = surfaceToNativeWindow(holder.surface)
        val w = surfaceView.width
        val h = surfaceView.height
        if (w > 0 && h > 0) {
            channel.invokeMethod(
                "surfaceCreated",
                mapOf("nativeWindow" to nativeWindowPtr, "width" to w, "height" to h),
            )
        } else {
            // Dimensions not ready yet — defer until surfaceChanged delivers them.
            pendingSurfaceCreated = true
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (pendingSurfaceCreated && width > 0 && height > 0) {
            pendingSurfaceCreated = false
            channel.invokeMethod(
                "surfaceCreated",
                mapOf("nativeWindow" to nativeWindowPtr, "width" to width, "height" to height),
            )
        } else {
            channel.invokeMethod("surfaceChanged", mapOf("width" to width, "height" to height))
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        channel.invokeMethod("surfaceDestroyed", null)
        releaseNativeWindow()
    }

    // ---- Helpers ------------------------------------------------------------

    private fun releaseNativeWindow() {
        if (nativeWindowPtr != 0L) {
            nativeReleaseWindow(nativeWindowPtr)
            nativeWindowPtr = 0L
        }
    }

    // JNI — implemented in vulkan_jni.cpp
    private external fun surfaceToNativeWindow(surface: android.view.Surface): Long
    private external fun nativeReleaseWindow(ptr: Long)
}
