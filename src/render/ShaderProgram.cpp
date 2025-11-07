#include "render/ShaderProgram.hpp"

#include <SDL.h>

#include <vector>

namespace shaderdock::render {

namespace {

bool CheckShaderStatus(GLuint shader, const char* debug_name)
{
    GLint status = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_TRUE) {
        return true;
    }

    GLint info_len = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &info_len);
    std::vector<GLchar> info(static_cast<std::size_t>(info_len > 1 ? info_len : 1), '\0');
    if (info_len > 1) {
        glGetShaderInfoLog(shader, info_len, nullptr, info.data());
    }

    SDL_Log("Shader compile error (%s): %s", debug_name, info.data());
    return false;
}

bool CheckProgramStatus(GLuint program)
{
    GLint status = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (status == GL_TRUE) {
        return true;
    }

    GLint info_len = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &info_len);
    std::vector<GLchar> info(static_cast<std::size_t>(info_len > 1 ? info_len : 1), '\0');
    if (info_len > 1) {
        glGetProgramInfoLog(program, info_len, nullptr, info.data());
    }

    SDL_Log("Program link error: %s", info.data());
    return false;
}

} // namespace

ShaderProgram::~ShaderProgram()
{
    reset();
}

ShaderProgram::ShaderProgram(ShaderProgram&& other) noexcept
{
    program_ = other.program_;
    other.program_ = 0;
}

ShaderProgram& ShaderProgram::operator=(ShaderProgram&& other) noexcept
{
    if (this != &other) {
        reset();
        program_ = other.program_;
        other.program_ = 0;
    }
    return *this;
}

bool ShaderProgram::compile_from_source(const char* vertex_source, const char* fragment_source)
{
    GLuint vertex_shader = 0;
    GLuint fragment_shader = 0;

    if (!compile_stage(GL_VERTEX_SHADER, "vertex", vertex_shader, vertex_source)) {
        return false;
    }
    if (!compile_stage(GL_FRAGMENT_SHADER, "fragment", fragment_shader, fragment_source)) {
        glDeleteShader(vertex_shader);
        return false;
    }

    GLuint program = glCreateProgram();
    if (program == 0) {
        SDL_Log("glCreateProgram failed");
        glDeleteShader(vertex_shader);
        glDeleteShader(fragment_shader);
        return false;
    }

    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);

    if (!CheckProgramStatus(program)) {
        glDeleteProgram(program);
        return false;
    }

    reset();
    program_ = program;
    return true;
}

bool ShaderProgram::compile_stage(GLenum type, const char* debug_name, GLuint& out_shader, const char* source)
{
    out_shader = glCreateShader(type);
    if (out_shader == 0) {
        SDL_Log("glCreateShader failed for %s stage", debug_name);
        return false;
    }

    glShaderSource(out_shader, 1, &source, nullptr);
    glCompileShader(out_shader);

    if (!CheckShaderStatus(out_shader, debug_name)) {
        glDeleteShader(out_shader);
        out_shader = 0;
        return false;
    }

    SDL_Log("Compiled %s shader.", debug_name);
    return true;
}

void ShaderProgram::use() const
{
    if (program_ != 0) {
        glUseProgram(program_);
    }
}

GLint ShaderProgram::uniform_location(const char* name) const
{
    if (program_ == 0) {
        return -1;
    }
    return glGetUniformLocation(program_, name);
}

void ShaderProgram::reset()
{
    if (program_ != 0) {
        glDeleteProgram(program_);
        program_ = 0;
    }
}

} // namespace shaderdock::render
