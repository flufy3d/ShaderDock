#include "resources/AssetIO.hpp"

#include <SDL.h>

#include <filesystem>
#include <fstream>
#include <sstream>
#include <vector>

namespace shaderdock::resources {

namespace {

std::vector<std::filesystem::path> BuildSearchPaths(const std::string& relative_path)
{
    std::vector<std::filesystem::path> candidates;
    if (relative_path.empty()) {
        return candidates;
    }

    std::filesystem::path relative(relative_path);
    candidates.push_back(relative);

    std::string base_path;
    if (char* raw = SDL_GetBasePath(); raw != nullptr) {
        base_path = raw;
        SDL_free(raw);
    }
    if (!base_path.empty()) {
        const std::filesystem::path base(base_path);
        candidates.push_back(base / relative);
        candidates.push_back(base / ".." / relative);
    }
    return candidates;
}

} // namespace

std::string ReadTextFile(const std::string& path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return {};
    }

    std::ostringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

std::string LoadAssetText(const std::string& relative_path)
{
    const std::filesystem::path resolved = ResolveAssetPath(relative_path);
    if (resolved.empty()) {
        SDL_Log("Failed to resolve asset path: %s", relative_path.c_str());
        return {};
    }

    std::string data = ReadTextFile(resolved.string());
    if (!data.empty()) {
        SDL_Log("Loaded asset: %s", resolved.string().c_str());
        return data;
    }

    SDL_Log("Failed to read asset: %s", resolved.string().c_str());
    return {};
}

std::filesystem::path ResolveAssetPath(const std::string& relative_path)
{
    for (const auto& candidate : BuildSearchPaths(relative_path)) {
        std::error_code ec;
        if (std::filesystem::exists(candidate, ec) && !ec) {
            return candidate;
        }
    }
    return {};
}

} // namespace shaderdock::resources
