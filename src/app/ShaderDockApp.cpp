#include "app/ShaderDockApp.hpp"

#include <SDL.h>

#include <atomic>
#include <csignal>
#include <utility>

#include <glad/glad.h>

#include "render/GlLoader.hpp"

namespace shaderdock::app {

namespace {

std::atomic_bool g_keep_running{true};

void HandleSigint(int)
{
    g_keep_running.store(false);
}

} // namespace

ShaderDockApp::ShaderDockApp(AppOptions options)
    : options_(std::move(options))
{
    texture_input_provider_ = std::make_shared<bindings::TextureInputProvider>(texture_cache_);
    cubemap_input_provider_ = std::make_shared<bindings::CubemapInputProvider>(texture_cache_);
    keyboard_input_provider_ = std::make_shared<bindings::KeyboardInputProvider>();
    input_providers_.push_back(texture_input_provider_);
    input_providers_.push_back(cubemap_input_provider_);
    input_providers_.push_back(keyboard_input_provider_);
}

bool ShaderDockApp::initialize()
{
    if (sdl_initialized_) {
        return true;
    }

    SDL_Log("ShaderDock starting...");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return false;
    }
    sdl_initialized_ = true;

    std::signal(SIGINT, HandleSigint);

    if (!load_app_config()) {
        SDL_Log("Failed to load application config.");
        return false;
    }

    if (!create_window_and_context()) {
        return false;
    }

    if (!render::LoadGLESBindings()) {
        SDL_Log("Failed to load OpenGL ES bindings via GLAD.");
        return false;
    }

    render::LogGLInfo();
    hardware_performance_level_ = render::GuessHardwarePerformanceLevel();
    SDL_Log(
        "Hardware performance level detected: %s (%d).",
        hardware_performance_level_ > 0 ? "high" : "low",
        hardware_performance_level_);

    if (!full_screen_triangle_.initialize()) {
        SDL_Log("Failed to create fullscreen triangle geometry.");
        return false;
    }

    if (!load_demo_resources()) {
        return false;
    }

    SDL_GL_GetDrawableSize(window_, &drawable_width_, &drawable_height_);
    glViewport(0, 0, drawable_width_, drawable_height_);
    pipeline_.resize_targets(drawable_width_, drawable_height_);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_BLEND);
    glClearColor(0.0F, 0.0F, 0.0F, 1.0F);

    return true;
}

void ShaderDockApp::run()
{
    if (!window_ || !gl_context_) {
        SDL_Log("ShaderDockApp::initialize must succeed before run().");
        return;
    }

    running_ = true;
    start_ticks_ = SDL_GetTicks();
    last_frame_ticks_ = start_ticks_;
    frame_index_ = 0;

    SDL_Event event{};
    bool sigint_reported = false;

    while (running_) {
        while (SDL_PollEvent(&event) != 0) {
            process_event(event);
        }

        if (!g_keep_running.load(std::memory_order_relaxed)) {
            if (!sigint_reported) {
                SDL_Log("SIGINT received, shutting down gracefully.");
                sigint_reported = true;
            }
            running_ = false;
        }

        if (!running_) {
            break;
        }

        update_viewport();

        const Uint32 now = SDL_GetTicks();
        const float elapsed_seconds = static_cast<float>(now - start_ticks_) * 0.001F;
        const float delta_seconds = static_cast<float>(now - last_frame_ticks_) * 0.001F;
        last_frame_ticks_ = now;

        render_frame(elapsed_seconds, delta_seconds);
        SDL_GL_SwapWindow(window_);
        if (frame_delay_ms_ > 0) {
            SDL_Delay(frame_delay_ms_);
        }
    }
}

void ShaderDockApp::shutdown()
{
    SDL_Log("ShaderDock shutting down...");

    running_ = false;

    pipeline_.shutdown();
    full_screen_triangle_.shutdown();

    texture_cache_.clear();
    demo_manifest_.reset();
    input_providers_.clear();
    texture_input_provider_.reset();
    cubemap_input_provider_.reset();
    keyboard_input_provider_.reset();

    if (gl_context_ != nullptr) {
        SDL_GL_DeleteContext(gl_context_);
        gl_context_ = nullptr;
    }

    if (window_ != nullptr) {
        SDL_DestroyWindow(window_);
        window_ = nullptr;
    }

    if (sdl_initialized_) {
        SDL_Quit();
        sdl_initialized_ = false;
    }

    g_keep_running.store(true, std::memory_order_relaxed);
}

} // namespace shaderdock::app
