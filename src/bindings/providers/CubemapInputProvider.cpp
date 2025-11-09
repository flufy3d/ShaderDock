#include "bindings/providers/CubemapInputProvider.hpp"

#include <SDL.h>

namespace shaderdock::bindings {

namespace {

std::string BuildKey(const manifest::PassInput& input)
{
    std::string key = input.id;
    key += '|';
    key += input.filepath;
    return key;
}

} // namespace

CubemapInputProvider::CubemapInputProvider(resources::TextureCache& cache)
    : cache_(cache)
{
}

bool CubemapInputProvider::supports(manifest::PassInputType type) const
{
    return type == manifest::PassInputType::kCubemap;
}

std::unique_ptr<PassInputBinding> CubemapInputProvider::create_binding(const manifest::PassInput& input)
{
    if (input.channel < 0 || input.channel > 3) {
        SDL_Log("CubemapInputProvider: channel %d invalid for %s.", input.channel, input.id.c_str());
        return nullptr;
    }

    auto texture = resolve_texture(input);
    if (!texture) {
        SDL_Log("CubemapInputProvider: failed to load cubemap for %s.", input.id.c_str());
        return nullptr;
    }

    return std::make_unique<CubemapInputBinding>(input.channel, std::move(texture));
}

std::shared_ptr<resources::TextureHandle> CubemapInputProvider::resolve_texture(const manifest::PassInput& input)
{
    if (!input.resolved_path) {
        SDL_Log("CubemapInputProvider: input %s missing resolved path.", input.id.c_str());
        return nullptr;
    }

    const std::string key = BuildKey(input);
    if (auto it = bindings_.find(key); it != bindings_.end()) {
        if (auto existing = it->second.lock()) {
            return existing;
        }
    }

    auto texture = cache_.load_cubemap(*input.resolved_path, input.sampler);
    if (texture) {
        bindings_[key] = texture;
    }
    return texture;
}

} // namespace shaderdock::bindings
