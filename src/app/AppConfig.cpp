#include "app/AppConfig.hpp"

#include <SDL.h>
#include <json/json.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>

namespace shaderdock::app {

namespace {

constexpr int kMinWindowSize = 320;
constexpr int kMaxWindowSize = 7680;
constexpr int kMinFrameDelay = 0;
constexpr int kMaxFrameDelay = 1000;
constexpr int kMinTargetFps = 0;
constexpr int kMaxTargetFps = 480;

std::filesystem::path DetermineConfigFilePath()
{
    char* pref_path = SDL_GetPrefPath("ShaderDock", "ShaderDock");
    if (pref_path == nullptr) {
        SDL_Log("AppConfig: SDL_GetPrefPath failed: %s", SDL_GetError());
        return {};
    }

    std::filesystem::path directory(pref_path);
    SDL_free(pref_path);

    std::error_code ec;
    if (!std::filesystem::exists(directory, ec)) {
        std::filesystem::create_directories(directory, ec);
        if (ec) {
            SDL_Log("AppConfig: failed to create config directory %s", directory.string().c_str());
            return {};
        }
    }

    return directory / "config.json";
}

Json::Value SerializeConfig(const AppConfig& config)
{
    Json::Value root(Json::objectValue);
    root["width"] = config.window_width;
    root["height"] = config.window_height;
    root["fullscreen"] = config.fullscreen;
    root["resizable"] = config.resizable;
    root["vsync"] = config.vsync;
    root["fps"] = config.target_fps;
    root["default_demo"] = config.default_demo;
    return root;
}

bool WriteConfigFile(const std::filesystem::path& path, const AppConfig& config)
{
    Json::StreamWriterBuilder builder;
    builder["indentation"] = "  ";
    const std::unique_ptr<Json::StreamWriter> writer(builder.newStreamWriter());

    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) {
        SDL_Log("AppConfig: failed to open %s for writing", path.string().c_str());
        return false;
    }

    writer->write(SerializeConfig(config), &file);
    file << std::endl;
    return true;
}

int ClampInt(int value, int min_value, int max_value)
{
    value = std::max(value, min_value);
    value = std::min(value, max_value);
    return value;
}

} // namespace

bool LoadOrCreateAppConfig(AppConfig& config, std::filesystem::path* out_path)
{
    config = AppConfig{};

    const std::filesystem::path config_path = DetermineConfigFilePath();
    if (config_path.empty()) {
        return false;
    }

    if (out_path != nullptr) {
        *out_path = config_path;
    }

    std::error_code ec;
    if (!std::filesystem::exists(config_path, ec) || ec) {
        if (!WriteConfigFile(config_path, config)) {
            return false;
        }
        SDL_Log("AppConfig: created default config at %s", config_path.string().c_str());
        return true;
    }

    std::ifstream file(config_path, std::ios::binary);
    if (!file.is_open()) {
        SDL_Log("AppConfig: failed to open %s for reading", config_path.string().c_str());
        return false;
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string data = buffer.str();

    Json::CharReaderBuilder builder;
    builder["collectComments"] = false;

    Json::Value root;
    std::string errs;
    const std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    if (!reader->parse(data.data(), data.data() + data.size(), &root, &errs)) {
        SDL_Log("AppConfig: failed to parse %s (%s)", config_path.string().c_str(), errs.c_str());
        return false;
    }

    if (root.isMember("width")) {
        config.window_width = ClampInt(root.get("width", config.window_width).asInt(), kMinWindowSize, kMaxWindowSize);
    }
    if (root.isMember("height")) {
        config.window_height = ClampInt(root.get("height", config.window_height).asInt(), kMinWindowSize, kMaxWindowSize);
    }
    if (root.isMember("fullscreen")) {
        config.fullscreen = root.get("fullscreen", config.fullscreen).asBool();
    }
    if (root.isMember("resizable")) {
        config.resizable = root.get("resizable", config.resizable).asBool();
    }
    if (root.isMember("vsync")) {
        config.vsync = root.get("vsync", config.vsync).asBool();
    }
    if (root.isMember("fps")) {
        config.target_fps = ClampInt(root.get("fps", config.target_fps).asInt(), kMinTargetFps, kMaxTargetFps);
    } else if (root.isMember("frame_delay_ms")) {
        const int legacy_delay =
            ClampInt(root.get("frame_delay_ms", kMinFrameDelay).asInt(), kMinFrameDelay, kMaxFrameDelay);
        if (legacy_delay > 0) {
            const int inferred_fps = static_cast<int>(std::llround(1000.0 / static_cast<double>(legacy_delay)));
            config.target_fps = ClampInt(inferred_fps, kMinTargetFps, kMaxTargetFps);
        } else {
            config.target_fps = 0;
        }
    }
    if (root.isMember("default_demo")) {
        config.default_demo = root.get("default_demo", "").asString();
    }

    SDL_Log("AppConfig: loaded settings from %s", config_path.string().c_str());
    return true;
}

} // namespace shaderdock::app
