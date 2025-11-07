#pragma once

#include <SDL.h>

#include <memory>
#include <optional>
#include <string>
#include <unordered_map>

#include "render/FullscreenTriangle.hpp"
#include "render/ShaderProgram.hpp"
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
    bool load_shaders();
    bool load_demo_resources();
    bool preload_textures();
    void process_event(const SDL_Event& event);
    void update_viewport();
    void render_frame(float elapsed_seconds);

    SDL_Window* window_ = nullptr;
    SDL_GLContext gl_context_ = nullptr;
    bool sdl_initialized_ = false;
    bool running_ = false;
    bool viewport_dirty_ = false;
    int drawable_width_ = 720;
    int drawable_height_ = 480;
    Uint32 start_ticks_ = 0;

    render::ShaderProgram shader_program_;
    render::FullscreenTriangle full_screen_triangle_;
    GLint u_time_location_ = -1;
    GLint u_resolution_location_ = -1;

    std::optional<resources::DemoManifest> demo_manifest_;
    resources::TextureCache texture_cache_;
    std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>> texture_bindings_;
};

} // namespace shaderdock::app
