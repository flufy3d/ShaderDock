#pragma once

#include <glad/glad.h>

namespace shaderdock::render {

class FullscreenTriangle
{
public:
    bool initialize();
    void draw() const;
    void shutdown();

private:
    GLuint vao_ = 0;
};

} // namespace shaderdock::render
