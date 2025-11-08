#include "app/ShaderDockApp.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <csignal>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <string>
#include <utility>

#include <glad/glad.h>

#include "render/GlLoader.hpp"
#include "render/RenderPipeline.hpp"
#include "resources/AssetIO.hpp"
#include "resources/DemoCatalog.hpp"

namespace shaderdock::app {

namespace {

std::atomic_bool g_keep_running{true};

void HandleSigint(int)
{
    g_keep_running.store(false);
}

std::array<float, 4> BuildDateUniform()
{
    using Clock = std::chrono::system_clock;
    const auto now = Clock::now();
    const std::time_t seconds = Clock::to_time_t(now);
    std::tm local_time{};
#if defined(_WIN32)
    localtime_s(&local_time, &seconds);
#else
    localtime_r(&seconds, &local_time);
#endif

    const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000;
    const float seconds_today =
        static_cast<float>(local_time.tm_hour * 3600 + local_time.tm_min * 60 + local_time.tm_sec) +
        static_cast<float>(millis) * 0.001F;

    return {
        static_cast<float>(local_time.tm_year + 1900),
        static_cast<float>(local_time.tm_mon + 1),
        static_cast<float>(local_time.tm_mday),
        seconds_today};
}
} // namespace

ShaderDockApp::ShaderDockApp(AppOptions options)
    : options_(std::move(options))
{
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

bool ShaderDockApp::load_app_config()
{
    if (!LoadOrCreateAppConfig(config_, &config_path_)) {
        return false;
    }

    drawable_width_ = config_.window_width;
    drawable_height_ = config_.window_height;
    if (config_.target_fps > 0) {
        const double interval_ms = 1000.0 / static_cast<double>(config_.target_fps);
        frame_delay_ms_ = static_cast<Uint32>(std::max(0, static_cast<int>(std::llround(interval_ms))));
    } else {
        frame_delay_ms_ = 0;
    }
    SDL_Log(
        "Config active: %dx%d fullscreen=%s vsync=%s fps=%d (frame_delay_ms=%u)",
        config_.window_width,
        config_.window_height,
        config_.fullscreen ? "true" : "false",
        config_.vsync ? "true" : "false",
        config_.target_fps,
        frame_delay_ms_);
    return true;
}

bool ShaderDockApp::create_window_and_context()
{
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);

    const Uint32 window_flags = SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN |
        (config_.resizable ? SDL_WINDOW_RESIZABLE : 0);

    window_ = SDL_CreateWindow(
        "ShaderDock",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        config_.window_width,
        config_.window_height,
        window_flags);
    if (window_ == nullptr) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        return false;
    }

    SDL_SetWindowResizable(window_, config_.resizable ? SDL_TRUE : SDL_FALSE);

    gl_context_ = SDL_GL_CreateContext(window_);
    if (gl_context_ == nullptr) {
        SDL_Log("SDL_GL_CreateContext failed: %s", SDL_GetError());
        return false;
    }

    if (SDL_GL_MakeCurrent(window_, gl_context_) != 0) {
        SDL_Log("SDL_GL_MakeCurrent failed: %s", SDL_GetError());
        return false;
    }

    if (config_.fullscreen) {
        SDL_SetWindowFullscreen(window_, SDL_WINDOW_FULLSCREEN_DESKTOP);
    }

    const int swap_interval = config_.vsync ? 1 : 0;
    if (SDL_GL_SetSwapInterval(swap_interval) != 0) {
        SDL_Log("SDL_GL_SetSwapInterval failed: %s", SDL_GetError());
    }

    viewport_dirty_ = true;
    return true;
}

bool ShaderDockApp::load_demo_resources()
{
    if (!resolve_demo_selection()) {
        return false;
    }

    auto manifest = resources::LoadDemoManifest(selected_manifest_path_);
    if (!manifest) {
        SDL_Log("Failed to parse demo manifest: %s", selected_manifest_path_.string().c_str());
        return false;
    }

    demo_manifest_ = std::move(*manifest);
    const std::string label = selected_demo_name_.empty() ? demo_manifest_->info.name : selected_demo_name_;
    SDL_Log(
        "Demo '%s' manifest ready (%s).",
        label.c_str(),
        selected_manifest_path_.string().c_str());
    if (!preload_textures()) {
        return false;
    }
    return build_pipeline();
}

bool ShaderDockApp::resolve_demo_selection()
{
    auto demos = resources::EnumerateAvailableDemos();
    if (demos.empty()) {
        SDL_Log("No demos found under assets/demos.");
        return false;
    }

    auto select_with_token = [&demos](const std::string& token) -> std::optional<resources::DemoEntry> {
        if (token.empty()) {
            return std::nullopt;
        }
        return resources::FindDemoByToken(demos, token);
    };

    std::optional<resources::DemoEntry> selection;

    if (options_.demo_token) {
        selection = select_with_token(*options_.demo_token);
        if (!selection) {
            SDL_Log("Requested demo '%s' not found, falling back to defaults.", options_.demo_token->c_str());
        }
    }

    if (!selection && !config_.default_demo.empty()) {
        selection = select_with_token(config_.default_demo);
        if (!selection) {
            SDL_Log("Config default demo '%s' not found.", config_.default_demo.c_str());
        }
    }

    if (!selection) {
        selection = demos.front();
    }

    selected_manifest_path_ = selection->manifest_path;
    selected_demo_name_ = selection->display_name.empty() ? selection->folder_name : selection->display_name;
    SDL_Log(
        "Selected demo '%s' (%s).",
        selected_demo_name_.c_str(),
        selected_manifest_path_.string().c_str());
    return true;
}

bool ShaderDockApp::preload_textures()
{
    texture_bindings_.clear();
    if (!demo_manifest_) {
        SDL_Log("No demo manifest available, cannot preload textures.");
        return false;
    }

    for (const auto& pass : demo_manifest_->passes) {
        for (const auto& input : pass.inputs) {
            if (!input.resolved_path) {
                continue;
            }

            std::shared_ptr<resources::TextureHandle> handle;
            if (input.type == resources::PassInputType::kTexture) {
                handle = texture_cache_.load_texture_2d(*input.resolved_path, input.sampler);
            } else if (input.type == resources::PassInputType::kCubemap) {
                handle = texture_cache_.load_cubemap(*input.resolved_path, input.sampler);
            } else {
                continue;
            }

            if (!handle) {
                SDL_Log(
                    "Failed to preload texture for input %s (%s).",
                    input.id.c_str(),
                    input.filepath.c_str());
                return false;
            }

            texture_bindings_[input.id] = std::move(handle);
        }
    }

    SDL_Log(
        "Texture preload complete. GPU cache contains %zu entries.",
        texture_cache_.resident_texture_count());
    return true;
}

bool ShaderDockApp::build_pipeline()
{
    if (!demo_manifest_) {
        SDL_Log("Cannot build pipeline without a demo manifest.");
        return false;
    }

    if (!pipeline_.initialize(*demo_manifest_, texture_bindings_, &full_screen_triangle_)) {
        SDL_Log("Failed to build render pipeline.");
        return false;
    }

    pipeline_.resize_targets(drawable_width_, drawable_height_);
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

void ShaderDockApp::process_event(const SDL_Event& event)
{
    switch (event.type) {
        case SDL_QUIT:
            running_ = false;
            break;
        case SDL_KEYDOWN:
            if (event.key.keysym.sym == SDLK_ESCAPE) {
                running_ = false;
            }
            break;
        case SDL_MOUSEBUTTONDOWN:
            if (event.button.button == SDL_BUTTON_LEFT) {
                update_mouse_position(event.button.x, event.button.y);
                mouse_button_down_ = true;
                mouse_tap_pending_ = false;
                mouse_dragged_ = false;
                mouse_click_x_ = mouse_current_x_;
                mouse_click_y_ = mouse_current_y_;
            }
            break;
        case SDL_MOUSEBUTTONUP:
            if (event.button.button == SDL_BUTTON_LEFT) {
                update_mouse_position(event.button.x, event.button.y);
                mouse_button_down_ = false;
                mouse_release_x_ = mouse_current_x_;
                mouse_release_y_ = mouse_current_y_;
                mouse_tap_pending_ = !mouse_dragged_;
                mouse_dragged_ = false;
            }
            break;
        case SDL_MOUSEMOTION:
            update_mouse_position(event.motion.x, event.motion.y);
            break;
        case SDL_WINDOWEVENT:
            if (event.window.event == SDL_WINDOWEVENT_RESIZED ||
                event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                viewport_dirty_ = true;
            }
            break;
        default:
            break;
    }
}

void ShaderDockApp::update_viewport()
{
    if (!viewport_dirty_ || window_ == nullptr) {
        return;
    }

    SDL_GL_GetDrawableSize(window_, &drawable_width_, &drawable_height_);
    glViewport(0, 0, drawable_width_, drawable_height_);
    pipeline_.resize_targets(drawable_width_, drawable_height_);
    viewport_dirty_ = false;
}

void ShaderDockApp::render_frame(float elapsed_seconds, float delta_seconds)
{
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    frame_uniforms_.time_seconds = elapsed_seconds;
    frame_uniforms_.delta_seconds = delta_seconds;
    if (delta_seconds > 0.0F) {
        frame_uniforms_.frame_rate = 1.0F / delta_seconds;
    }
    frame_uniforms_.frame_index = frame_index_++;
    frame_uniforms_.channel_time.fill(0.0F);
    frame_uniforms_.mouse = build_mouse_uniform();
    frame_uniforms_.date = BuildDateUniform();

    pipeline_.render(frame_uniforms_, drawable_width_, drawable_height_);
}

void ShaderDockApp::update_mouse_position(int window_x, int window_y)
{
    if (window_ == nullptr) {
        return;
    }

    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(window_, &window_width, &window_height);

    if (window_width <= 0 || window_height <= 0 || drawable_width_ <= 0 || drawable_height_ <= 0) {
        mouse_current_x_ = 0.0F;
        mouse_current_y_ = 0.0F;
        return;
    }

    const float scale_x = static_cast<float>(drawable_width_) / static_cast<float>(window_width);
    const float scale_y = static_cast<float>(drawable_height_) / static_cast<float>(window_height);

    float pixel_x = static_cast<float>(window_x) * scale_x;
    float pixel_y = static_cast<float>(window_y) * scale_y;

    pixel_x = std::clamp(pixel_x, 0.0F, static_cast<float>(drawable_width_));
    pixel_y = std::clamp(pixel_y, 0.0F, static_cast<float>(drawable_height_));

    mouse_current_x_ = pixel_x;
    mouse_current_y_ = static_cast<float>(drawable_height_) - pixel_y - 1.0F;
    mouse_current_y_ = std::clamp(mouse_current_y_, 0.0F, static_cast<float>(drawable_height_));

    if (mouse_button_down_ && !mouse_dragged_) {
        constexpr float drag_threshold = 1.0F;
        if (std::abs(mouse_current_x_ - mouse_click_x_) > drag_threshold ||
            std::abs(mouse_current_y_ - mouse_click_y_) > drag_threshold) {
            mouse_dragged_ = true;
        }
    }

    if (!mouse_button_down_ && !mouse_tap_pending_) {
        mouse_release_x_ = mouse_current_x_;
        mouse_release_y_ = mouse_current_y_;
    }
}

std::array<float, 4> ShaderDockApp::build_mouse_uniform()
{
    std::array<float, 4> mouse{0.0F, 0.0F, 0.0F, 0.0F};

    if (mouse_button_down_) {
        mouse[0] = mouse_current_x_;
        mouse[1] = mouse_current_y_;
        mouse[2] = mouse_click_x_;
        mouse[3] = -mouse_click_y_;

        // Track the most recent position so we can reference it after release.
        mouse_release_x_ = mouse_current_x_;
        mouse_release_y_ = mouse_current_y_;
    } else {
        mouse[0] = -mouse_release_x_;
        mouse[1] = -mouse_release_y_;
        mouse[2] = -mouse_release_x_;
        mouse[3] = mouse_tap_pending_ ? mouse_release_y_ : -mouse_release_y_;

        if (mouse_tap_pending_) {
            mouse_tap_pending_ = false;
        }
    }

    return mouse;
}

void ShaderDockApp::shutdown()
{
    running_ = false;

    texture_bindings_.clear();
    texture_cache_.clear();
    demo_manifest_.reset();

    pipeline_.shutdown();
    full_screen_triangle_.shutdown();

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
