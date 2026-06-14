cmake_minimum_required(VERSION 3.21)
project(flutter_vulkan_plugin VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PLUGIN_NAME "flutter_vulkan_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_vulkan_plugin.cpp"
)

# apply_standard_settings is injected by the Flutter app's windows/CMakeLists.txt.
# Define a minimal fallback so the plugin can be configured standalone too.
if(NOT COMMAND apply_standard_settings)
  function(apply_standard_settings TARGET)
    target_compile_features(${TARGET} PUBLIC cxx_std_17)
    if(MSVC)
      target_compile_options(${TARGET} PRIVATE /W3 /EHsc)
      target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
    endif()
  endfunction()
endif()

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}")

# flutter and flutter_wrapper_plugin are provided by the parent Flutter app build.
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# vkb_game.dll is built by the dart_vulkan native CMake and placed in
# lib/native/ at the project root.  Because this CMakeLists is accessed
# through a Flutter directory junction (.plugin_symlinks), relative paths
# cannot be used here — the consuming app must install vkb_game.dll itself.
# See the example's windows/CMakeLists.txt for how this is done.
