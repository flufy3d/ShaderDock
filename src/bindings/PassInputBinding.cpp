#include "bindings/PassInputBinding.hpp"

#include <algorithm>
#include <glad/glad.h>

namespace shaderdock::bindings {

PassInputBinding::PassInputBinding(int channel, manifest::PassInputType type)
    : channel_(channel)
    , type_(type)
{
}

void PassInputBinding::activate_texture_unit() const
{
    const int safe_channel = std::clamp(channel_, 0, 31);
    glActiveTexture(GL_TEXTURE0 + safe_channel);
}

} // namespace shaderdock::bindings
