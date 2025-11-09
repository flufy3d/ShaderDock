#include "bindings/providers/TextureInputProvider.hpp"

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

TextureInputProvider::TextureInputProvider(resources::TextureCache& cache)
    : cache_(cache)
{
}

bool TextureInputProvider::supports(manifest::PassInputType type) const
{
    return type == manifest::PassInputType::kTexture;
}

std::unique_ptr<PassInputBinding> TextureInputProvider::create_binding(const manifest::PassInput& input)
{
    if (input.channel < 0 || input.channel > 3) {
        SDL_Log("TextureInputProvider: channel %d invalid for %s.", input.channel, input.id.c_str());
        return nullptr;
    }

    auto texture = resolve_texture(input);
    if (!texture) {
        SDL_Log("TextureInputProvider: failed to load texture for %s.", input.id.c_str());
        return nullptr;
    }

    return std::make_unique<TextureInputBinding>(input.channel, std::move(texture));
}

std::shared_ptr<resources::TextureHandle> TextureInputProvider::resolve_texture(const manifest::PassInput& input)
{
    if (!input.resolved_path) {
        SDL_Log("TextureInputProvider: input %s missing resolved path.", input.id.c_str());
        return nullptr;
    }

    const std::string key = BuildKey(input);
    if (auto it = bindings_.find(key); it != bindings_.end()) {
        if (auto existing = it->second.lock()) {
            return existing;
        }
    }

    auto texture = cache_.load_texture_2d(*input.resolved_path, input.sampler);
    if (texture) {
        bindings_[key] = texture;
    }
    return texture;
}

} // namespace shaderdock::bindings
