#include <SDL.h>
#include <SDL_opengles2.h>

#include <array>
#include <csignal>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "gl_bindings.hpp"

namespace
{
constexpr int kWindowWidth = 720;
constexpr int kWindowHeight = 480;
constexpr Uint32 kFrameDelayMs = 16;

volatile std::sig_atomic_t running = 1;

void handle_sigint(int)
{
    running = 0;
    SDL_Log("Caught Ctrl+C, exiting...");
}

std::string read_text_file(const std::string& path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return {};
    }

    std::ostringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

std::string load_asset_source(const char* relative_path)
{
    std::string base_path_str;
    if (char* base_path = SDL_GetBasePath(); base_path != nullptr) {
        base_path_str = base_path;
        SDL_free(base_path);
    }

    const std::array<std::string, 3> search_paths = {
        std::string(relative_path),
        base_path_str.empty() ? std::string() : base_path_str + relative_path,
        base_path_str.empty() ? std::string() : base_path_str + "../" + relative_path};

    for (const std::string& candidate : search_paths) {
        if (candidate.empty()) {
            continue;
        }
        std::string data = read_text_file(candidate);
        if (!data.empty()) {
            SDL_Log("Loaded shader: %s", candidate.c_str());
            return data;
        }
    }

    SDL_Log("Failed to load shader asset: %s", relative_path);
    return {};
}

GLuint compile_shader(GLenum type, const char* debug_name, const GLBindings& gl, const char* source)
{
    const GLuint shader = gl.create_shader(type);
    if (shader == 0U) {
        SDL_Log("glCreateShader failed for %s", debug_name);
        return 0U;
    }

    gl.shader_source(shader, 1, &source, nullptr);
    gl.compile_shader(shader);

    GLint status = GL_FALSE;
    gl.get_shader_iv(shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE) {
        GLint info_len = 0;
        gl.get_shader_iv(shader, GL_INFO_LOG_LENGTH, &info_len);
        std::vector<GLchar> info(static_cast<std::size_t>(info_len > 1 ? info_len : 1), '\0');
        if (info_len > 1) {
            gl.get_shader_info_log(shader, info_len, nullptr, info.data());
        }
        SDL_Log("Shader compile error (%s): %s", debug_name, info.data());
        gl.delete_shader(shader);
        return 0U;
    }

    SDL_Log("Compiled shader: %s", debug_name);
    return shader;
}

GLuint link_program(GLuint vertex_shader, GLuint fragment_shader, const GLBindings& gl)
{
    const GLuint program = gl.create_program();
    if (program == 0U) {
        SDL_Log("glCreateProgram failed");
        return 0U;
    }

    gl.attach_shader(program, vertex_shader);
    gl.attach_shader(program, fragment_shader);
    gl.link_program(program);

    GLint status = GL_FALSE;
    gl.get_program_iv(program, GL_LINK_STATUS, &status);
    if (status != GL_TRUE) {
        GLint info_len = 0;
        gl.get_program_iv(program, GL_INFO_LOG_LENGTH, &info_len);
        std::vector<GLchar> info(static_cast<std::size_t>(info_len > 1 ? info_len : 1), '\0');
        if (info_len > 1) {
            gl.get_program_info_log(program, info_len, nullptr, info.data());
        }
        SDL_Log("Program link error: %s", info.data());
        gl.delete_program(program);
        return 0U;
    }

    SDL_Log("Linked shader program successfully.");
    return program;
}
} // namespace

int main(int argc, char** argv)
{
    static_cast<void>(argc);
    static_cast<void>(argv);

    std::signal(SIGINT, handle_sigint);

    SDL_Log("ShaderDock starting...");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return 1;
    }

    if (SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES) != 0) {
        SDL_Log("SDL_GL_SetAttribute PROFILE_ES failed: %s", SDL_GetError());
    }
    if (SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3) != 0) {
        SDL_Log("SDL_GL_SetAttribute MAJOR_VERSION failed: %s", SDL_GetError());
    }
    if (SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2) != 0) {
        SDL_Log("SDL_GL_SetAttribute MINOR_VERSION failed: %s", SDL_GetError());
    }
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);

    SDL_Window* window = SDL_CreateWindow(
        "ShaderDock",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        kWindowWidth,
        kWindowHeight,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (window == nullptr) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_SetWindowResizable(window, SDL_FALSE);

    SDL_GLContext gl_context = SDL_GL_CreateContext(window);
    if (gl_context == nullptr) {
        SDL_Log("SDL_GL_CreateContext failed: %s", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }
    if (SDL_GL_MakeCurrent(window, gl_context) != 0) {
        SDL_Log("SDL_GL_MakeCurrent failed: %s", SDL_GetError());
        SDL_GL_DeleteContext(gl_context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }
    if (SDL_GL_SetSwapInterval(1) != 0) {
        SDL_Log("SDL_GL_SetSwapInterval failed: %s", SDL_GetError());
    }

    SDL_Log("VideoDriver = %s", SDL_GetCurrentVideoDriver());

    int actual_major = 0;
    int actual_minor = 0;
    SDL_GL_GetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, &actual_major);
    SDL_GL_GetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, &actual_minor);
    SDL_Log("Requested GLES 3.2, acquired context %d.%d", actual_major, actual_minor);

    if (actual_major < 3 || (actual_major == 3 && actual_minor < 2)) {
        SDL_Log("Warning: OpenGL ES 3.2 context not available.");
    } else {
        SDL_Log("OpenGL ES 3.2 context created successfully.");
    }

    using PFNGLGETSTRINGPROC = const GLubyte*(GL_APIENTRY*)(GLenum);
    const auto glGetStringPtr = reinterpret_cast<PFNGLGETSTRINGPROC>(
        SDL_GL_GetProcAddress("glGetString"));

    const char* vendor = nullptr;
    const char* renderer = nullptr;
    const char* version = nullptr;
    if (glGetStringPtr != nullptr) {
        vendor = reinterpret_cast<const char*>(glGetStringPtr(GL_VENDOR));
        renderer = reinterpret_cast<const char*>(glGetStringPtr(GL_RENDERER));
        version = reinterpret_cast<const char*>(glGetStringPtr(GL_VERSION));
    } else {
        SDL_Log("glGetString not available via SDL_GL_GetProcAddress.");
    }

    if (vendor != nullptr) {
        SDL_Log("GL_VENDOR: %s", vendor);
    }
    if (renderer != nullptr) {
        SDL_Log("GL_RENDERER: %s", renderer);
    }
    if (version != nullptr) {
        SDL_Log("GL_VERSION: %s", version);
    }

    GLBindings gl{};
    if (!load_gl_bindings(gl)) {
        SDL_Log("Required GLES 3.2 functions missing, cannot continue.");
        SDL_GL_DeleteContext(gl_context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    const std::string vertex_source = load_asset_source("assets/test_triangle.vert");
    const std::string fragment_source = load_asset_source("assets/test_triangle.frag");
    if (vertex_source.empty() || fragment_source.empty()) {
        SDL_Log("Shader sources not available; aborting.");
        SDL_GL_DeleteContext(gl_context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    const GLuint vertex_shader = compile_shader(GL_VERTEX_SHADER, "test_triangle.vert", gl, vertex_source.c_str());
    const GLuint fragment_shader =
        compile_shader(GL_FRAGMENT_SHADER, "test_triangle.frag", gl, fragment_source.c_str());
    if (vertex_shader == 0U || fragment_shader == 0U) {
        if (vertex_shader != 0U) {
            gl.delete_shader(vertex_shader);
        }
        if (fragment_shader != 0U) {
            gl.delete_shader(fragment_shader);
        }
        SDL_GL_DeleteContext(gl_context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    const GLuint program = link_program(vertex_shader, fragment_shader, gl);
    gl.delete_shader(vertex_shader);
    gl.delete_shader(fragment_shader);

    if (program == 0U) {
        SDL_GL_DeleteContext(gl_context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    GLint u_time_location = gl.get_uniform_location(program, "uTime");
    GLint u_resolution_location = gl.get_uniform_location(program, "uResolution");
    SDL_Log("Program uniforms: uTime=%d, uResolution=%d", u_time_location, u_resolution_location);

    GLuint vao = 0U;
    gl.gen_vertex_arrays(1, &vao);
    gl.bind_vertex_array(vao);

    int drawable_width = kWindowWidth;
    int drawable_height = kWindowHeight;
    SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
    gl.viewport(0, 0, drawable_width, drawable_height);
    gl.clear_color(0.0F, 0.0F, 0.0F, 1.0F);

    const Uint32 start_ticks = SDL_GetTicks();

    SDL_Event event{};
    bool needs_viewport_update = false;
    while (running != 0) {
        while (SDL_PollEvent(&event) != 0) {
            if (event.type == SDL_QUIT ||
                event.type == SDL_KEYDOWN ||
                event.type == SDL_MOUSEBUTTONDOWN) {
                running = 0;
                break;
            }
            if (event.type == SDL_WINDOWEVENT &&
                (event.window.event == SDL_WINDOWEVENT_RESIZED ||
                 event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED)) {
                needs_viewport_update = true;
            }
        }

        if (needs_viewport_update) {
            SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
            gl.viewport(0, 0, drawable_width, drawable_height);
            needs_viewport_update = false;
        }

        const float elapsed_seconds = static_cast<float>(SDL_GetTicks() - start_ticks) * 0.001F;

        gl.clear(GL_COLOR_BUFFER_BIT);

        gl.use_program(program);
        if (u_time_location >= 0) {
            gl.uniform_1f(u_time_location, elapsed_seconds);
        }
        if (u_resolution_location >= 0) {
            gl.uniform_2f(u_resolution_location, static_cast<float>(drawable_width), static_cast<float>(drawable_height));
        }

        gl.bind_vertex_array(vao);
        gl.draw_arrays(GL_TRIANGLES, 0, 3);

        SDL_GL_SwapWindow(window);
        SDL_Delay(kFrameDelayMs);
    }

    if (vao != 0U) {
        gl.delete_vertex_arrays(1, &vao);
    }
    if (program != 0U) {
        gl.delete_program(program);
    }

    SDL_GL_DeleteContext(gl_context);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
