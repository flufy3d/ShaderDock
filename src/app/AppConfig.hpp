#pragma once

#include <filesystem>
#include <string>

namespace shaderdock::app {

struct AppConfig {
    int window_width = 1280;
    int window_height = 720;
    bool fullscreen = false;
    bool resizable = false;
    bool vsync = true;
    int target_fps = 60; // 0 = uncapped
    std::string default_demo;
};

bool LoadOrCreateAppConfig(AppConfig& config, std::filesystem::path* out_path = nullptr);

} // namespace shaderdock::app
