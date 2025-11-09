#include "bindings/providers/BufferInputProvider.hpp"

#include <SDL.h>

namespace shaderdock::bindings {

void BufferInputProvider::set_buffer_surfaces(std::unordered_map<std::string, render::BufferSurface>* surfaces)
{
    buffer_surfaces_ = surfaces;
}

bool BufferInputProvider::supports(manifest::PassInputType type) const
{
    return type == manifest::PassInputType::kBuffer;
}

std::unique_ptr<PassInputBinding> BufferInputProvider::create_binding(const manifest::PassInput& input)
{
    if (buffer_surfaces_ == nullptr) {
        SDL_Log("BufferInputProvider: buffer sources unavailable for %s.", input.id.c_str());
        return nullptr;
    }
    if (input.channel < 0 || input.channel > 3) {
        SDL_Log("BufferInputProvider: channel %d invalid for %s.", input.channel, input.id.c_str());
        return nullptr;
    }
    if (input.id.empty()) {
        SDL_Log("BufferInputProvider: input %s missing buffer id.", input.filepath.c_str());
        return nullptr;
    }

    auto it = buffer_surfaces_->find(input.id);
    if (it == buffer_surfaces_->end()) {
        SDL_Log("BufferInputProvider: buffer '%s' not found.", input.id.c_str());
        return nullptr;
    }

    return std::make_unique<BufferInputBinding>(input.channel, &it->second, input.sampler);
}

} // namespace shaderdock::bindings
