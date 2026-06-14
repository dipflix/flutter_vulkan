/*
 * vulkan_jni.cpp
 *
 * JNI bridge: converts a Java android.view.Surface into an ANativeWindow*
 * and exposes the pointer as a jlong so Dart can pass it to
 * vkb_renderer3d_create_android via FFI.
 *
 * This file is compiled into libflutter_vulkan.so together with
 * vulkan_bridge.cpp and vkb_renderer3d.cpp, so the single .so exposes all
 * vkb_* symbols and Dart can reach them via DynamicLibrary.open().
 */

#include <jni.h>
#include <android/native_window_jni.h>

extern "C" {

// Called from VulkanPlatformView.kt: surfaceToNativeWindow(surface)
// JNI name mangling: com.vkb.flutter_vulkan → com_vkb_flutter_1vulkan
JNIEXPORT jlong JNICALL
Java_com_vkb_flutter_1vulkan_VulkanPlatformView_surfaceToNativeWindow(
    JNIEnv* env, jobject /* thiz */, jobject surface)
{
    ANativeWindow* win = ANativeWindow_fromSurface(env, surface);
    return reinterpret_cast<jlong>(win);
}

// Called from VulkanPlatformView.kt: nativeReleaseWindow(ptr)
JNIEXPORT void JNICALL
Java_com_vkb_flutter_1vulkan_VulkanPlatformView_nativeReleaseWindow(
    JNIEnv* /* env */, jobject /* thiz */, jlong ptr)
{
    if (ptr != 0) {
        ANativeWindow_release(reinterpret_cast<ANativeWindow*>(ptr));
    }
}

} // extern "C"
