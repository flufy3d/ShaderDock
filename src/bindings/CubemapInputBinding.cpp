#include "bindings/CubemapInputBinding.hpp"

#include <glad/glad.h>

#include "resources/TextureLoader.hpp"

namespace shaderdock::bindings {

CubemapInputBinding::CubemapInputBinding(int channel, std::shared_ptr<resources::TextureHandle> texture)
    : PassInputBinding(channel, manifest::PassInputType::kCubemap)
    , texture_(std::move(texture))
{
}

void CubemapInputBinding::bind() const
{
    if (!texture_) {
        return;
    }
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_CUBE_MAP, texture_->id());
}

void CubemapInputBinding::unbind() const
{
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
}

float CubemapInputBinding::width() const
{
    return texture_ ? static_cast<float>(texture_->width()) : 0.0F;
}

float CubemapInputBinding::height() const
{
    return texture_ ? static_cast<float>(texture_->height()) : 0.0F;
}

} // namespace shaderdock::bindings
