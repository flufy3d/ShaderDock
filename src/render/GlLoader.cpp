#include "render/GlLoader.hpp"

#include <SDL.h>

#include <cstring>
#include <string_view>

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

namespace {

bool ContainsToken(const char* text, std::string_view token)
{
    if (text == nullptr || token.empty()) {
        return false;
    }
    return std::strstr(text, token.data()) != nullptr;
}

} // namespace

int GuessHardwarePerformanceLevel()
{
    const char* vendor = reinterpret_cast<const char*>(glGetString(GL_VENDOR));
    const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));

    if (renderer == nullptr || vendor == nullptr) {
        SDL_Log("Hardware performance guess: missing GL vendor/renderer info, defaulting to low.");
        return 0;
    }

    if (ContainsToken(renderer, "RTX") || ContainsToken(renderer, "GTX") ||
        ContainsToken(renderer, "Radeon RX") || ContainsToken(renderer, "Arc")) {
        return 1;
    }

    if (ContainsToken(renderer, "Adreno") || ContainsToken(renderer, "Mali") ||
        ContainsToken(renderer, "PowerVR") || ContainsToken(renderer, "Apple")) {
        return 0;
    }

    if (ContainsToken(renderer, "Intel") || ContainsToken(renderer, "UHD") ||
        ContainsToken(renderer, "Iris") || ContainsToken(vendor, "Intel")) {
        return 0;
    }

    return 0;
}

} // namespace shaderdock::render
