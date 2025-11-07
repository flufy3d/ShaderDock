#pragma once

#include <SDL.h>

#include <array>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>

#include "render/FullscreenTriangle.hpp"
#include "render/RenderPipeline.hpp"
#include "resources/DemoManifest.hpp"
#include "resources/TextureLoader.hpp"

namespace shaderdock::app {

class ShaderDockApp
{
public:
    bool initialize();
    void run();
    void shutdown();

private:
    bool create_window_and_context();
    bool load_demo_resources();
    bool preload_textures();
    bool build_pipeline();
    void process_event(const SDL_Event& event);
    void update_viewport();
    void render_frame(float elapsed_seconds, float delta_seconds);
    void update_mouse_position(int window_x, int window_y);
    std::array<float, 4> build_mouse_uniform() const;

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

    render::FullscreenTriangle full_screen_triangle_;
    render::RenderPipeline pipeline_;
    render::FrameUniforms frame_uniforms_;

    std::optional<resources::DemoManifest> demo_manifest_;
    resources::TextureCache texture_cache_;
    std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>> texture_bindings_;

    bool mouse_button_down_ = false;
    float mouse_current_x_ = 0.0F;
    float mouse_current_y_ = 0.0F;
    float mouse_click_x_ = 0.0F;
    float mouse_click_y_ = 0.0F;
};

} // namespace shaderdock::app
