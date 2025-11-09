#include "bindings/KeyboardInputBinding.hpp"

#include <glad/glad.h>

#include "resources/TextureLoader.hpp"

namespace shaderdock::bindings {

KeyboardInputBinding::KeyboardInputBinding(int channel, std::shared_ptr<resources::TextureHandle> texture)
    : PassInputBinding(channel, manifest::PassInputType::kKeyboard)
    , texture_(std::move(texture))
{
}

void KeyboardInputBinding::bind() const
{
    if (!texture_) {
        return;
    }
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, texture_->id());
}

void KeyboardInputBinding::unbind() const
{
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, 0);
}

float KeyboardInputBinding::width() const
{
    return texture_ ? static_cast<float>(texture_->width()) : 0.0F;
}

float KeyboardInputBinding::height() const
{
    return texture_ ? static_cast<float>(texture_->height()) : 0.0F;
}

} // namespace shaderdock::bindings
