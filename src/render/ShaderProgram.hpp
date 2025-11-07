#pragma once

#include <glad/glad.h>

namespace shaderdock::render {

class ShaderProgram
{
public:
    ShaderProgram() = default;
    ~ShaderProgram();

    ShaderProgram(const ShaderProgram&) = delete;
    ShaderProgram& operator=(const ShaderProgram&) = delete;
    ShaderProgram(ShaderProgram&& other) noexcept;
    ShaderProgram& operator=(ShaderProgram&& other) noexcept;

    bool compile_from_source(const char* vertex_source, const char* fragment_source);
    void use() const;
    GLint uniform_location(const char* name) const;
    void reset();

private:
    bool compile_stage(GLenum type, const char* debug_name, GLuint& out_shader, const char* source);

    GLuint program_ = 0;
};

} // namespace shaderdock::render
