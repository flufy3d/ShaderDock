#include "render/PipelineTypes.hpp"

namespace shaderdock::render {

GLuint BufferSurface::read_texture() const
{
    return textures[front_index];
}

GLuint BufferSurface::write_framebuffer() const
{
    const int target_index = double_buffer ? 1 - front_index : front_index;
    return framebuffers[target_index];
}

void BufferSurface::swap()
{
    if (double_buffer) {
        front_index = 1 - front_index;
    }
}

void BufferSurface::reset()
{
    if (textures[0] != 0) {
        glDeleteTextures(1, &textures[0]);
        textures[0] = 0;
    }
    if (textures[1] != 0) {
        glDeleteTextures(1, &textures[1]);
        textures[1] = 0;
    }
    if (framebuffers[0] != 0) {
        glDeleteFramebuffers(1, &framebuffers[0]);
        framebuffers[0] = 0;
    }
    if (framebuffers[1] != 0) {
        glDeleteFramebuffers(1, &framebuffers[1]);
        framebuffers[1] = 0;
    }
    width = 0;
    height = 0;
    front_index = 0;
}

} // namespace shaderdock::render
