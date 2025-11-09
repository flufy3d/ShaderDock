#include "bindings/TextureInputBinding.hpp"

#include <glad/glad.h>

#include "resources/TextureLoader.hpp"

namespace shaderdock::bindings {

TextureInputBinding::TextureInputBinding(int channel, std::shared_ptr<resources::TextureHandle> texture)
    : PassInputBinding(channel, manifest::PassInputType::kTexture)
    , texture_(std::move(texture))
{
}

void TextureInputBinding::bind() const
{
    if (!texture_) {
        return;
    }
    activate_texture_unit();
    glBindTexture(texture_->target(), texture_->id());
}

void TextureInputBinding::unbind() const
{
    activate_texture_unit();
    const GLenum target = texture_ ? texture_->target() : GL_TEXTURE_2D;
    glBindTexture(target, 0);
}

float TextureInputBinding::width() const
{
    return texture_ ? static_cast<float>(texture_->width()) : 0.0F;
}

float TextureInputBinding::height() const
{
    return texture_ ? static_cast<float>(texture_->height()) : 0.0F;
}

} // namespace shaderdock::bindings
