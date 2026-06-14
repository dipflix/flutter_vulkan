#include "flutter_vulkan/flutter_vulkan_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <cstdlib>
#include <map>
#include <memory>
#include <mutex>

// ---------------------------------------------------------------------------
// Function pointers loaded at runtime from vkb_game.dll
// ---------------------------------------------------------------------------
typedef void* VkbRenderer3D;
typedef int32_t (*PFN_read_pixels)(VkbRenderer3D r, uint8_t** out_pixels);
typedef int32_t (*PFN_renderer3d_resize)(VkbRenderer3D r, int32_t w, int32_t h);

static HMODULE               g_vkb_lib          = nullptr;
static PFN_read_pixels       g_read_pixels       = nullptr;
static PFN_renderer3d_resize g_renderer3d_resize = nullptr;

static bool EnsureVkbLib() {
  if (g_vkb_lib) return g_read_pixels != nullptr;
  g_vkb_lib = LoadLibraryA("vkb_game.dll");
  if (!g_vkb_lib) return false;
  g_read_pixels = reinterpret_cast<PFN_read_pixels>(
      GetProcAddress(g_vkb_lib, "vkb_renderer3d_read_pixels"));
  g_renderer3d_resize = reinterpret_cast<PFN_renderer3d_resize>(
      GetProcAddress(g_vkb_lib, "vkb_renderer3d_resize"));
  return g_read_pixels != nullptr;
}

// ---------------------------------------------------------------------------
// Per-texture state
// ---------------------------------------------------------------------------
struct RendererEntry {
  VkbRenderer3D renderer = nullptr;
  uint32_t width  = 0;
  uint32_t height = 0;
  // desc.buffer points directly into the Vulkan HOST_CACHED readback buffer —
  // no memcpy needed. The double-buffered readback guarantees the pointer is
  // stable for one full frame cycle (Vulkan won't overwrite it until begin_frame
  // of the frame after next, by which time Flutter has already consumed it).
  FlutterDesktopPixelBuffer desc{};
  std::unique_ptr<flutter::TextureVariant> texture_variant;
  std::mutex pixel_mutex;
};

// ---------------------------------------------------------------------------
// Plugin class
// ---------------------------------------------------------------------------
namespace {

class FlutterVulkanPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar* registrar);
  explicit FlutterVulkanPlugin(flutter::PluginRegistrar* registrar);
  ~FlutterVulkanPlugin() override;

  void FlushFrame(int64_t texture_id);

 private:
  flutter::TextureRegistrar* texture_registrar_;
  std::map<int64_t, std::unique_ptr<RendererEntry>> entries_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

FlutterVulkanPlugin* g_plugin = nullptr;

void FlutterVulkanPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrar* registrar) {
  auto plugin = std::make_unique<FlutterVulkanPlugin>(registrar);
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.vkb/flutter_vulkan",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [ptr = plugin.get()](const auto& call, auto result) {
        ptr->HandleMethodCall(call, std::move(result));
      });
  g_plugin = plugin.get();
  registrar->AddPlugin(std::move(plugin));
}

FlutterVulkanPlugin::FlutterVulkanPlugin(flutter::PluginRegistrar* registrar)
    : texture_registrar_(registrar->texture_registrar()) {}

FlutterVulkanPlugin::~FlutterVulkanPlugin() {
  for (auto& [id, _] : entries_) {
    texture_registrar_->UnregisterTexture(id);
  }
  g_plugin = nullptr;
}

void FlutterVulkanPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "registerTexture") {
    if (!EnsureVkbLib()) {
      result->Error("INIT", "Cannot load vkb_game.dll or find vkb_renderer3d_read_pixels");
      return;
    }

    const auto* map_ptr =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!map_ptr) {
      result->Error("BAD_ARGS", "expected EncodableMap");
      return;
    }
    const auto& args = *map_ptr;

    // Flutter StandardMethodCodec encodes small Dart ints as int32, large as
    // int64.  Pointer addresses may fall in either range, so check both.
    auto get_int64 = [](const flutter::EncodableMap& m,
                        const char* key) -> int64_t {
      auto it = m.find(flutter::EncodableValue(std::string(key)));
      if (it == m.end()) return 0;
      if (const auto* v = std::get_if<int64_t>(&it->second)) return *v;
      if (const auto* v = std::get_if<int32_t>(&it->second))
        return static_cast<int64_t>(*v);
      return 0;
    };
    auto get_int32 = [](const flutter::EncodableMap& m,
                        const char* key) -> int32_t {
      auto it = m.find(flutter::EncodableValue(std::string(key)));
      if (it == m.end()) return 0;
      if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
      if (const auto* v = std::get_if<int64_t>(&it->second))
        return static_cast<int32_t>(*v);
      return 0;
    };

    int64_t renderer_ptr = get_int64(args, "rendererPtr");
    int32_t w            = get_int32(args, "width");
    int32_t h            = get_int32(args, "height");

    auto entry        = std::make_unique<RendererEntry>();
    entry->renderer   = reinterpret_cast<VkbRenderer3D>(
        static_cast<intptr_t>(renderer_ptr));
    entry->width      = static_cast<uint32_t>(w);
    entry->height     = static_cast<uint32_t>(h);
    // desc.buffer is set to null here; FlushFrame will point it directly at the
    // Vulkan-mapped readback memory (no staging copy needed).
    entry->desc.buffer           = nullptr;
    entry->desc.width            = static_cast<size_t>(w);
    entry->desc.height           = static_cast<size_t>(h);
    entry->desc.release_callback = nullptr;
    entry->desc.release_context  = nullptr;

    RendererEntry* raw = entry.get();
    entry->texture_variant = std::make_unique<flutter::TextureVariant>(
        flutter::PixelBufferTexture(
            [raw](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
              std::lock_guard<std::mutex> lock(raw->pixel_mutex);
              return &raw->desc;
            }));

    int64_t texture_id =
        texture_registrar_->RegisterTexture(entry->texture_variant.get());
    entries_[texture_id] = std::move(entry);

    result->Success(flutter::EncodableMap{
        {flutter::EncodableValue("textureId"),
         flutter::EncodableValue(texture_id)},
    });

  } else if (call.method_name() == "resizeTexture") {
    const auto* rmap = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!rmap) { result->Error("BAD_ARGS", "expected EncodableMap"); return; }
    const auto& rargs = *rmap;

    auto get_i64 = [](const flutter::EncodableMap& m, const char* key) -> int64_t {
      auto it = m.find(flutter::EncodableValue(std::string(key)));
      if (it == m.end()) return 0;
      if (const auto* v = std::get_if<int64_t>(&it->second)) return *v;
      if (const auto* v = std::get_if<int32_t>(&it->second)) return static_cast<int64_t>(*v);
      return 0;
    };
    auto get_i32 = [](const flutter::EncodableMap& m, const char* key) -> int32_t {
      auto it = m.find(flutter::EncodableValue(std::string(key)));
      if (it == m.end()) return 0;
      if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
      if (const auto* v = std::get_if<int64_t>(&it->second)) return static_cast<int32_t>(*v);
      return 0;
    };

    int64_t tid   = get_i64(rargs, "textureId");
    int32_t new_w = get_i32(rargs, "width");
    int32_t new_h = get_i32(rargs, "height");

    auto eit = entries_.find(tid);
    if (eit == entries_.end()) { result->Error("NOT_FOUND", "texture not registered"); return; }
    RendererEntry* entry = eit->second.get();

    if (new_w > 0 && new_h > 0 && g_renderer3d_resize) {
      g_renderer3d_resize(entry->renderer, new_w, new_h);
    }

    {
      std::lock_guard<std::mutex> lock(entry->pixel_mutex);
      entry->width       = static_cast<uint32_t>(new_w);
      entry->height      = static_cast<uint32_t>(new_h);
      entry->desc.buffer = nullptr; // will be refreshed by next FlushFrame
      entry->desc.width  = static_cast<size_t>(new_w);
      entry->desc.height = static_cast<size_t>(new_h);
    }
    texture_registrar_->MarkTextureFrameAvailable(tid);
    result->Success();

  } else if (call.method_name() == "unregisterTexture") {
    const auto* map_ptr2 =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!map_ptr2) { result->Error("BAD_ARGS", "expected EncodableMap"); return; }
    const auto& args = *map_ptr2;
    auto it = args.find(flutter::EncodableValue(std::string("textureId")));
    int64_t texture_id = 0;
    if (it != args.end()) {
      if (const auto* p64 = std::get_if<int64_t>(&it->second)) texture_id = *p64;
      else if (const auto* p32 = std::get_if<int32_t>(&it->second)) texture_id = *p32;
    }
    texture_registrar_->UnregisterTexture(texture_id);
    entries_.erase(texture_id);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterVulkanPlugin::FlushFrame(int64_t texture_id) {
  auto it = entries_.find(texture_id);
  if (it == entries_.end() || !g_read_pixels) return;
  RendererEntry* entry = it->second.get();

  uint8_t* raw = nullptr;
  if (g_read_pixels(entry->renderer, &raw) != 0 || !raw) return;

  {
    std::lock_guard<std::mutex> lock(entry->pixel_mutex);
    // Point directly at the Vulkan HOST_CACHED readback buffer — zero memcpy.
    // The readback double-buffer guarantees this pointer stays valid for the
    // entire frame: Vulkan will not write to it again until begin_frame of the
    // frame after next (after waiting for the in-flight fence).
    entry->desc.buffer = raw;
  }
  texture_registrar_->MarkTextureFrameAvailable(texture_id);
}

}  // namespace

// ---------------------------------------------------------------------------
// Plugin registration entry point (called by Flutter)
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport)
void FlutterVulkanPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  FlutterVulkanPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrar>(registrar));
}

// ---------------------------------------------------------------------------
// Dart FFI export: called each frame by the game to flush the rendered image
// into the Flutter texture pipeline.
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport)
void vkb_windows_flush_frame(int64_t texture_id) {
  if (g_plugin) g_plugin->FlushFrame(texture_id);
}
