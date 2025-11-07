#include "app/ShaderDockApp.hpp"

#include <atomic>
#include <csignal>
#include <filesystem>
#include <string>
#include <utility>

#include <glad/glad.h>

#include "render/GlLoader.hpp"
#include "render/RenderPipeline.hpp"
#include "resources/AssetIO.hpp"

namespace shaderdock::app {

namespace {
constexpr int kWindowWidth = 720;
constexpr int kWindowHeight = 480;
constexpr Uint32 kFrameDelayMs = 16;

std::atomic_bool g_keep_running{true};

void HandleSigint(int)
{
    g_keep_running.store(false);
}
} // namespace

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

    window_ = SDL_CreateWindow(
        "ShaderDock",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        kWindowWidth,
        kWindowHeight,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (window_ == nullptr) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        return false;
    }

    SDL_SetWindowResizable(window_, SDL_FALSE);

    gl_context_ = SDL_GL_CreateContext(window_);
    if (gl_context_ == nullptr) {
        SDL_Log("SDL_GL_CreateContext failed: %s", SDL_GetError());
        return false;
    }

    if (SDL_GL_MakeCurrent(window_, gl_context_) != 0) {
        SDL_Log("SDL_GL_MakeCurrent failed: %s", SDL_GetError());
        return false;
    }

    if (SDL_GL_SetSwapInterval(1) != 0) {
        SDL_Log("SDL_GL_SetSwapInterval failed: %s", SDL_GetError());
    }

    viewport_dirty_ = true;
    return true;
}

bool ShaderDockApp::load_demo_resources()
{
    constexpr const char* kDefaultDemoManifest = "assets/demos/Texture_LOD/demo.json";
    const std::filesystem::path manifest_path = resources::ResolveAssetPath(kDefaultDemoManifest);
    if (manifest_path.empty()) {
        SDL_Log("Unable to locate demo manifest at %s", kDefaultDemoManifest);
        return false;
    }

    auto manifest = resources::LoadDemoManifest(manifest_path);
    if (!manifest) {
        SDL_Log("Failed to parse demo manifest: %s", manifest_path.string().c_str());
        return false;
    }

    demo_manifest_ = std::move(*manifest);
    SDL_Log("Demo '%s' manifest ready.", demo_manifest_->info.name.c_str());
    if (!preload_textures()) {
        return false;
    }
    return build_pipeline();
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
        SDL_Delay(kFrameDelayMs);
    }
}

void ShaderDockApp::process_event(const SDL_Event& event)
{
    switch (event.type) {
        case SDL_QUIT:
        case SDL_KEYDOWN:
        case SDL_MOUSEBUTTONDOWN:
            running_ = false;
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
    frame_uniforms_.frame_rate = (delta_seconds > 0.0F) ? (1.0F / delta_seconds) : 0.0F;
    frame_uniforms_.frame_index = frame_index_++;

    pipeline_.render(frame_uniforms_, drawable_width_, drawable_height_);
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
