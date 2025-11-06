#include <SDL.h>
#include <SDL_opengles2.h>
#include <signal.h>
#include <stdio.h>

static volatile int running = 1;

void handle_sigint(int sig)
{
    (void)sig;
    running = 0;
    SDL_Log("Caught Ctrl+C, exiting...");
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    signal(SIGINT, handle_sigint);

    SDL_Log("simple-sdl2 start!!!");

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

    SDL_Window *window = SDL_CreateWindow(
        "simple-sdl2",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        720,
        480,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (!window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_SetWindowResizable(window, SDL_FALSE);

    SDL_GLContext gl_context = SDL_GL_CreateContext(window);
    if (!gl_context) {
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

    typedef const GLubyte *(GL_APIENTRY *PFNGLGETSTRINGPROC)(GLenum);
    PFNGLGETSTRINGPROC glGetStringPtr =
        (PFNGLGETSTRINGPROC)SDL_GL_GetProcAddress("glGetString");

    const char *vendor = NULL;
    const char *renderer = NULL;
    const char *version = NULL;
    if (glGetStringPtr) {
        vendor = (const char *)glGetStringPtr(GL_VENDOR);
        renderer = (const char *)glGetStringPtr(GL_RENDERER);
        version = (const char *)glGetStringPtr(GL_VERSION);
    } else {
        SDL_Log("glGetString not available via SDL_GL_GetProcAddress.");
    }

    if (vendor) {
        SDL_Log("GL_VENDOR: %s", vendor);
    }
    if (renderer) {
        SDL_Log("GL_RENDERER: %s", renderer);
    }
    if (version) {
        SDL_Log("GL_VERSION: %s", version);
    }

    typedef void(GL_APIENTRY *PFNGLVIEWPORTPROC)(GLint, GLint, GLsizei, GLsizei);
    typedef void(GL_APIENTRY *PFNGLCLEARCOLORPROC)(GLfloat, GLfloat, GLfloat, GLfloat);
    typedef void(GL_APIENTRY *PFNGLCLEARPROC)(GLbitfield);

    PFNGLVIEWPORTPROC glViewportPtr =
        (PFNGLVIEWPORTPROC)SDL_GL_GetProcAddress("glViewport");
    PFNGLCLEARCOLORPROC glClearColorPtr =
        (PFNGLCLEARCOLORPROC)SDL_GL_GetProcAddress("glClearColor");
    PFNGLCLEARPROC glClearPtr =
        (PFNGLCLEARPROC)SDL_GL_GetProcAddress("glClear");

    if (!glViewportPtr || !glClearColorPtr || !glClearPtr) {
        SDL_Log("Basic GLES functions missing (viewport/clear), rendering disabled.");
    }

    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(window, &window_width, &window_height);
    if (glViewportPtr) {
        glViewportPtr(0, 0, window_width, window_height);
    }

    if (glClearColorPtr && glClearPtr) {
        glClearColorPtr(0.1f, 0.2f, 0.3f, 1.0f);
        glClearPtr(GL_COLOR_BUFFER_BIT);
        SDL_GL_SwapWindow(window);
    }

    SDL_Event event;
    while (running) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT ||
                event.type == SDL_KEYDOWN ||
                event.type == SDL_MOUSEBUTTONDOWN) {
                running = 0;
                break;
            }
        }
        if (glClearColorPtr && glClearPtr) {
            glClearColorPtr(0.1f, 0.2f, 0.3f, 1.0f);
            glClearPtr(GL_COLOR_BUFFER_BIT);
            SDL_GL_SwapWindow(window);
        }
        SDL_Delay(16);
    }

    SDL_GL_DeleteContext(gl_context);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
