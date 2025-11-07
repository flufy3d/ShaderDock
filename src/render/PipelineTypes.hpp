#pragma once

#include <array>
#include <string>

#include <glad/glad.h>

namespace shaderdock::render {

struct FrameUniforms {
    float time_seconds = 0.0F;
    float delta_seconds = 0.0F;
    float frame_rate = 0.0F;
    int frame_index = 0;
    std::array<float, 4> mouse{0.0F, 0.0F, 0.0F, 0.0F};
    std::array<float, 4> date{0.0F, 0.0F, 0.0F, 0.0F};
    std::array<float, 4> channel_time{0.0F, 0.0F, 0.0F, 0.0F};
};

struct BufferSurface {
    std::string id;
    bool double_buffer = false;
    int width = 0;
    int height = 0;
    int front_index = 0;
    std::array<GLuint, 2> textures{0, 0};
    std::array<GLuint, 2> framebuffers{0, 0};

    [[nodiscard]] GLuint read_texture() const;
    [[nodiscard]] GLuint write_framebuffer() const;
    void swap();
    void reset();
};

} // namespace shaderdock::render
