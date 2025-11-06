#include <SDL.h>
#include <SDL_opengles2.h>

#include <csignal>

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

    using PFNGLVIEWPORTPROC = void(GL_APIENTRY*)(GLint, GLint, GLsizei, GLsizei);
    using PFNGLCLEARCOLORPROC = void(GL_APIENTRY*)(GLfloat, GLfloat, GLfloat, GLfloat);
    using PFNGLCLEARPROC = void(GL_APIENTRY*)(GLbitfield);

    const auto glViewportPtr = reinterpret_cast<PFNGLVIEWPORTPROC>(
        SDL_GL_GetProcAddress("glViewport"));
    const auto glClearColorPtr = reinterpret_cast<PFNGLCLEARCOLORPROC>(
        SDL_GL_GetProcAddress("glClearColor"));
    const auto glClearPtr = reinterpret_cast<PFNGLCLEARPROC>(
        SDL_GL_GetProcAddress("glClear"));

    if (glViewportPtr == nullptr || glClearColorPtr == nullptr || glClearPtr == nullptr) {
        SDL_Log("Basic GLES functions missing (viewport/clear), rendering disabled.");
    }

    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(window, &window_width, &window_height);
    if (glViewportPtr != nullptr) {
        glViewportPtr(0, 0, window_width, window_height);
    }

    if (glClearColorPtr != nullptr && glClearPtr != nullptr) {
        glClearColorPtr(0.1F, 0.2F, 0.3F, 1.0F);
        glClearPtr(GL_COLOR_BUFFER_BIT);
        SDL_GL_SwapWindow(window);
    }

    SDL_Event event{};
    while (running != 0) {
        while (SDL_PollEvent(&event) != 0) {
            if (event.type == SDL_QUIT ||
                event.type == SDL_KEYDOWN ||
                event.type == SDL_MOUSEBUTTONDOWN) {
                running = 0;
                break;
            }
        }
        if (glClearColorPtr != nullptr && glClearPtr != nullptr) {
            glClearColorPtr(0.1F, 0.2F, 0.3F, 1.0F);
            glClearPtr(GL_COLOR_BUFFER_BIT);
            SDL_GL_SwapWindow(window);
        }
        SDL_Delay(kFrameDelayMs);
    }

    SDL_GL_DeleteContext(gl_context);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
