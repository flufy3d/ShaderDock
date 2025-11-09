#include "app/ShaderDockApp.hpp"

#include <SDL.h>

#include <algorithm>
#include <cmath>
#include <utility>

#include <glad/glad.h>

#include "manifest/DemoManifestLoader.hpp"
#include "resources/DemoCatalog.hpp"

namespace shaderdock::app {

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

    if (config_.fullscreen) {
        SDL_SetWindowFullscreen(window_, SDL_WINDOW_FULLSCREEN_DESKTOP);
    }

    gl_context_ = SDL_GL_CreateContext(window_);
    if (gl_context_ == nullptr) {
        SDL_Log("SDL_GL_CreateContext failed: %s", SDL_GetError());
        return false;
    }

    if (SDL_GL_MakeCurrent(window_, gl_context_) != 0) {
        SDL_Log("SDL_GL_MakeCurrent failed: %s", SDL_GetError());
        return false;
    }

    if (SDL_GL_SetSwapInterval(config_.vsync ? 1 : 0) != 0) {
        SDL_Log("Warning: SDL_GL_SetSwapInterval(%d) failed: %s", config_.vsync ? 1 : 0, SDL_GetError());
    }

    SDL_Log("Window created (%dx%d).", config_.window_width, config_.window_height);
    return true;
}

bool ShaderDockApp::load_demo_resources()
{
    if (!resolve_demo_selection()) {
        return false;
    }

    manifest::DemoManifestLoader loader;
    auto manifest = loader.load(selected_manifest_path_);
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

bool ShaderDockApp::build_pipeline()
{
    if (!demo_manifest_) {
        SDL_Log("Cannot build pipeline without a demo manifest.");
        return false;
    }

    if (!pipeline_.initialize(
            *demo_manifest_,
            input_providers_,
            &full_screen_triangle_,
            hardware_performance_level_)) {
        SDL_Log("Failed to build render pipeline.");
        return false;
    }

    pipeline_.resize_targets(drawable_width_, drawable_height_);
    return true;
}

} // namespace shaderdock::app
