#include "resources/AssetIO.hpp"

#include <SDL.h>

#include <array>
#include <fstream>
#include <sstream>

namespace shaderdock::resources {

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
    std::string base_path;
    if (char* raw = SDL_GetBasePath(); raw != nullptr) {
        base_path = raw;
        SDL_free(raw);
    }

    const std::array<std::string, 3> search_paths = {
        relative_path,
        base_path.empty() ? std::string() : base_path + relative_path,
        base_path.empty() ? std::string() : base_path + "../" + relative_path};

    for (const std::string& candidate : search_paths) {
        if (candidate.empty()) {
            continue;
        }

        std::string data = ReadTextFile(candidate);
        if (!data.empty()) {
            SDL_Log("Loaded asset: %s", candidate.c_str());
            return data;
        }
    }

    SDL_Log("Failed to load asset: %s", relative_path.c_str());
    return {};
}

} // namespace shaderdock::resources
