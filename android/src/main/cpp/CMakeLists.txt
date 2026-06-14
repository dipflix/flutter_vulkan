cmake_minimum_required(VERSION 3.22)
project(flutter_vulkan CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Paths relative to this CMakeLists.txt:
#   cpp/ → main/ → android/ → flutter_vulkan/ → packages/ → repo root
set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../..")

find_package(Vulkan REQUIRED)

# Single shared library that Dart loads via DynamicLibrary.open("libflutter_vulkan.so").
# It exports:
#   - JNI bridge (ANativeWindow* ↔ Surface)
#   - all vkb_* symbols from vulkan_bridge and vkb_renderer3d
add_library(flutter_vulkan SHARED
    vulkan_jni.cpp
    ${REPO_ROOT}/packages/vulkan_bridge/native/src/vulkan_bridge.cpp
    ${REPO_ROOT}/native/src/vkb_renderer3d.cpp
)

target_include_directories(flutter_vulkan PRIVATE
    ${REPO_ROOT}/packages/vulkan_bridge/native/include
    ${REPO_ROOT}/native/include
)

# __ANDROID__ is set by the NDK toolchain; the renderer uses it to compile
# the Android-only vkb_renderer3d_create_android function.
target_compile_definitions(flutter_vulkan PRIVATE __ANDROID__)

find_library(log-lib log)
target_link_libraries(flutter_vulkan PRIVATE
    android
    Vulkan::Vulkan
    ${log-lib}
)
