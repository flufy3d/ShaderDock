#include "bindings/BufferInputBinding.hpp"

#include <glad/glad.h>

namespace shaderdock::bindings {

BufferInputBinding::BufferInputBinding(int channel, render::BufferSurface* surface)
    : PassInputBinding(channel, manifest::PassInputType::kBuffer)
    , surface_(surface)
{
}

void BufferInputBinding::bind() const
{
    if (!surface_) {
        return;
    }
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, surface_->read_texture());
}

void BufferInputBinding::unbind() const
{
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, 0);
}

float BufferInputBinding::width() const
{
    return surface_ ? static_cast<float>(surface_->width) : 0.0F;
}

float BufferInputBinding::height() const
{
    return surface_ ? static_cast<float>(surface_->height) : 0.0F;
}

float BufferInputBinding::last_updated_seconds() const
{
    return surface_ ? surface_->last_updated_seconds : 0.0F;
}

} // namespace shaderdock::bindings
