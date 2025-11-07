#include "render/FullscreenTriangle.hpp"

#include <SDL.h>

namespace shaderdock::render {

bool FullscreenTriangle::initialize()
{
    if (vao_ != 0) {
        return true;
    }

    glGenVertexArrays(1, &vao_);
    if (vao_ == 0) {
        SDL_Log("glGenVertexArrays failed for fullscreen triangle.");
        return false;
    }

    return true;
}

void FullscreenTriangle::draw() const
{
    if (vao_ == 0) {
        return;
    }

    glBindVertexArray(vao_);
    glDrawArrays(GL_TRIANGLES, 0, 3);
}

void FullscreenTriangle::shutdown()
{
    if (vao_ != 0) {
        glDeleteVertexArrays(1, &vao_);
        vao_ = 0;
    }
}

} // namespace shaderdock::render
