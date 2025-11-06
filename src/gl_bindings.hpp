#pragma once

#include <SDL.h>
#include <SDL_opengles2.h>

using PFNGLVIEWPORTPROC = void(GL_APIENTRY*)(GLint, GLint, GLsizei, GLsizei);
using PFNGLCLEARCOLORPROC = void(GL_APIENTRY*)(GLfloat, GLfloat, GLfloat, GLfloat);
using PFNGLCLEARPROC = void(GL_APIENTRY*)(GLbitfield);
using PFNGLCREATESHADERPROC = GLuint(GL_APIENTRY*)(GLenum);
using PFNGLSHADERSOURCEPROC = void(GL_APIENTRY*)(GLuint, GLsizei, const GLchar* const*, const GLint*);
using PFNGLCOMPILESHADERPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLGETSHADERIVPROC = void(GL_APIENTRY*)(GLuint, GLenum, GLint*);
using PFNGLGETSHADERINFOLOGPROC = void(GL_APIENTRY*)(GLuint, GLsizei, GLsizei*, GLchar*);
using PFNGLDELETESHADERPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLCREATEPROGRAMPROC = GLuint(GL_APIENTRY*)();
using PFNGLATTACHSHADERPROC = void(GL_APIENTRY*)(GLuint, GLuint);
using PFNGLLINKPROGRAMPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLGETPROGRAMIVPROC = void(GL_APIENTRY*)(GLuint, GLenum, GLint*);
using PFNGLGETPROGRAMINFOLOGPROC = void(GL_APIENTRY*)(GLuint, GLsizei, GLsizei*, GLchar*);
using PFNGLDELETEPROGRAMPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLUSEPROGRAMPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLGETUNIFORMLOCATIONPROC = GLint(GL_APIENTRY*)(GLuint, const GLchar*);
using PFNGLUNIFORM1FPROC = void(GL_APIENTRY*)(GLint, GLfloat);
using PFNGLUNIFORM2FPROC = void(GL_APIENTRY*)(GLint, GLfloat, GLfloat);
using PFNGLGENVERTEXARRAYSPROC = void(GL_APIENTRY*)(GLsizei, GLuint*);
using PFNGLBINDVERTEXARRAYPROC = void(GL_APIENTRY*)(GLuint);
using PFNGLDELETEVERTEXARRAYSPROC = void(GL_APIENTRY*)(GLsizei, const GLuint*);
using PFNGLDRAWARRAYSPROC = void(GL_APIENTRY*)(GLenum, GLint, GLsizei);

struct GLBindings
{
    PFNGLVIEWPORTPROC viewport = nullptr;
    PFNGLCLEARCOLORPROC clear_color = nullptr;
    PFNGLCLEARPROC clear = nullptr;
    PFNGLCREATESHADERPROC create_shader = nullptr;
    PFNGLSHADERSOURCEPROC shader_source = nullptr;
    PFNGLCOMPILESHADERPROC compile_shader = nullptr;
    PFNGLGETSHADERIVPROC get_shader_iv = nullptr;
    PFNGLGETSHADERINFOLOGPROC get_shader_info_log = nullptr;
    PFNGLDELETESHADERPROC delete_shader = nullptr;
    PFNGLCREATEPROGRAMPROC create_program = nullptr;
    PFNGLATTACHSHADERPROC attach_shader = nullptr;
    PFNGLLINKPROGRAMPROC link_program = nullptr;
    PFNGLGETPROGRAMIVPROC get_program_iv = nullptr;
    PFNGLGETPROGRAMINFOLOGPROC get_program_info_log = nullptr;
    PFNGLDELETEPROGRAMPROC delete_program = nullptr;
    PFNGLUSEPROGRAMPROC use_program = nullptr;
    PFNGLGETUNIFORMLOCATIONPROC get_uniform_location = nullptr;
    PFNGLUNIFORM1FPROC uniform_1f = nullptr;
    PFNGLUNIFORM2FPROC uniform_2f = nullptr;
    PFNGLGENVERTEXARRAYSPROC gen_vertex_arrays = nullptr;
    PFNGLBINDVERTEXARRAYPROC bind_vertex_array = nullptr;
    PFNGLDELETEVERTEXARRAYSPROC delete_vertex_arrays = nullptr;
    PFNGLDRAWARRAYSPROC draw_arrays = nullptr;
};

template <typename T>
inline T load_gl_function(const char* name)
{
    auto* const proc = reinterpret_cast<T>(SDL_GL_GetProcAddress(name));
    if (proc == nullptr) {
        SDL_Log("Failed to load GL function: %s", name);
    }
    return proc;
}

inline bool load_gl_bindings(GLBindings& gl)
{
    bool ok = true;
    gl.viewport = load_gl_function<PFNGLVIEWPORTPROC>("glViewport");
    gl.clear_color = load_gl_function<PFNGLCLEARCOLORPROC>("glClearColor");
    gl.clear = load_gl_function<PFNGLCLEARPROC>("glClear");
    gl.create_shader = load_gl_function<PFNGLCREATESHADERPROC>("glCreateShader");
    gl.shader_source = load_gl_function<PFNGLSHADERSOURCEPROC>("glShaderSource");
    gl.compile_shader = load_gl_function<PFNGLCOMPILESHADERPROC>("glCompileShader");
    gl.get_shader_iv = load_gl_function<PFNGLGETSHADERIVPROC>("glGetShaderiv");
    gl.get_shader_info_log = load_gl_function<PFNGLGETSHADERINFOLOGPROC>("glGetShaderInfoLog");
    gl.delete_shader = load_gl_function<PFNGLDELETESHADERPROC>("glDeleteShader");
    gl.create_program = load_gl_function<PFNGLCREATEPROGRAMPROC>("glCreateProgram");
    gl.attach_shader = load_gl_function<PFNGLATTACHSHADERPROC>("glAttachShader");
    gl.link_program = load_gl_function<PFNGLLINKPROGRAMPROC>("glLinkProgram");
    gl.get_program_iv = load_gl_function<PFNGLGETPROGRAMIVPROC>("glGetProgramiv");
    gl.get_program_info_log = load_gl_function<PFNGLGETPROGRAMINFOLOGPROC>("glGetProgramInfoLog");
    gl.delete_program = load_gl_function<PFNGLDELETEPROGRAMPROC>("glDeleteProgram");
    gl.use_program = load_gl_function<PFNGLUSEPROGRAMPROC>("glUseProgram");
    gl.get_uniform_location = load_gl_function<PFNGLGETUNIFORMLOCATIONPROC>("glGetUniformLocation");
    gl.uniform_1f = load_gl_function<PFNGLUNIFORM1FPROC>("glUniform1f");
    gl.uniform_2f = load_gl_function<PFNGLUNIFORM2FPROC>("glUniform2f");
    gl.gen_vertex_arrays = load_gl_function<PFNGLGENVERTEXARRAYSPROC>("glGenVertexArrays");
    gl.bind_vertex_array = load_gl_function<PFNGLBINDVERTEXARRAYPROC>("glBindVertexArray");
    gl.delete_vertex_arrays = load_gl_function<PFNGLDELETEVERTEXARRAYSPROC>("glDeleteVertexArrays");
    gl.draw_arrays = load_gl_function<PFNGLDRAWARRAYSPROC>("glDrawArrays");

    ok = ok && gl.viewport != nullptr;
    ok = ok && gl.clear_color != nullptr;
    ok = ok && gl.clear != nullptr;
    ok = ok && gl.create_shader != nullptr;
    ok = ok && gl.shader_source != nullptr;
    ok = ok && gl.compile_shader != nullptr;
    ok = ok && gl.get_shader_iv != nullptr;
    ok = ok && gl.get_shader_info_log != nullptr;
    ok = ok && gl.delete_shader != nullptr;
    ok = ok && gl.create_program != nullptr;
    ok = ok && gl.attach_shader != nullptr;
    ok = ok && gl.link_program != nullptr;
    ok = ok && gl.get_program_iv != nullptr;
    ok = ok && gl.get_program_info_log != nullptr;
    ok = ok && gl.delete_program != nullptr;
    ok = ok && gl.use_program != nullptr;
    ok = ok && gl.get_uniform_location != nullptr;
    ok = ok && gl.uniform_1f != nullptr;
    ok = ok && gl.uniform_2f != nullptr;
    ok = ok && gl.gen_vertex_arrays != nullptr;
    ok = ok && gl.bind_vertex_array != nullptr;
    ok = ok && gl.delete_vertex_arrays != nullptr;
    ok = ok && gl.draw_arrays != nullptr;
    return ok;
}
