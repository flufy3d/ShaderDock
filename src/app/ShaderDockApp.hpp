#pragma once

#include <SDL.h>

#include <array>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "app/AppConfig.hpp"
#include "bindings/providers/CubemapInputProvider.hpp"
#include "bindings/providers/InputProvider.hpp"
#include "bindings/providers/KeyboardInputProvider.hpp"
#include "bindings/providers/TextureInputProvider.hpp"
#include "manifest/ManifestTypes.hpp"
#include "render/FullscreenTriangle.hpp"
#include "render/RenderPipeline.hpp"
#include "resources/TextureLoader.hpp"

namespace shaderdock::app {

struct AppOptions {
    std::optional<std::string> demo_token;
};

class ShaderDockApp
{
public:
    explicit ShaderDockApp(AppOptions options = {});

    bool initialize();
    void run();
    void shutdown();

private:
    bool load_app_config();
    bool create_window_and_context();
    bool load_demo_resources();
    bool resolve_demo_selection();
    bool build_pipeline();
    void process_event(const SDL_Event& event);
    void update_viewport();
    void render_frame(float elapsed_seconds, float delta_seconds);
    void update_input_providers(float delta_seconds);
    void update_mouse_position(int window_x, int window_y);
    std::array<float, 4> build_mouse_uniform();
    void handle_key_event(const SDL_KeyboardEvent& key_event);

    AppOptions options_;
    AppConfig config_;
    std::filesystem::path config_path_;

    SDL_Window* window_ = nullptr;
    SDL_GLContext gl_context_ = nullptr;
    bool sdl_initialized_ = false;
    bool running_ = false;
    bool viewport_dirty_ = false;
    int drawable_width_ = 720;
    int drawable_height_ = 480;
    Uint32 start_ticks_ = 0;
    Uint32 last_frame_ticks_ = 0;
    int frame_index_ = 0;
    Uint32 frame_delay_ms_ = 0;

    render::FullscreenTriangle full_screen_triangle_;
    render::RenderPipeline pipeline_;
    render::FrameUniforms frame_uniforms_;
    int hardware_performance_level_ = 0;

    std::optional<manifest::DemoManifest> demo_manifest_;
    std::filesystem::path selected_manifest_path_;
    std::string selected_demo_name_;
    resources::TextureCache texture_cache_;
    std::vector<bindings::InputProviderPtr> input_providers_;
    std::shared_ptr<bindings::TextureInputProvider> texture_input_provider_;
    std::shared_ptr<bindings::CubemapInputProvider> cubemap_input_provider_;
    bindings::KeyboardInputProviderPtr keyboard_input_provider_;

    bool mouse_button_down_ = false;
    float mouse_current_x_ = 0.0F;
    float mouse_current_y_ = 0.0F;
    float mouse_click_x_ = 0.0F;
    float mouse_click_y_ = 0.0F;
    float mouse_release_x_ = 0.0F;
    float mouse_release_y_ = 0.0F;
    bool mouse_tap_pending_ = false;
    bool mouse_dragged_ = false;

};

} // namespace shaderdock::app
