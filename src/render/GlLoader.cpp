#include "render/GlLoader.hpp"

#include <SDL.h>

#include <glad/glad.h>

namespace shaderdock::render {

bool LoadGLESBindings()
{
    const int loaded = gladLoadGLES2Loader(reinterpret_cast<GLADloadproc>(SDL_GL_GetProcAddress));
    if (loaded == 0) {
        SDL_Log("gladLoadGLES2Loader failed.");
        return false;
    }
    return true;
}

void LogGLInfo()
{
    const GLubyte* vendor = glGetString(GL_VENDOR);
    const GLubyte* renderer = glGetString(GL_RENDERER);
    const GLubyte* version = glGetString(GL_VERSION);

    if (vendor != nullptr) {
        SDL_Log("GL_VENDOR: %s", vendor);
    }
    if (renderer != nullptr) {
        SDL_Log("GL_RENDERER: %s", renderer);
    }
    if (version != nullptr) {
        SDL_Log("GL_VERSION: %s", version);
    }
}

} // namespace shaderdock::render
