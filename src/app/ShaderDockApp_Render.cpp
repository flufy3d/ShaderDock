#include "app/ShaderDockApp.hpp"

#include <SDL.h>

#include <array>
#include <chrono>
#include <ctime>

#include <glad/glad.h>

namespace {

std::array<float, 4> BuildDateUniform()
{
    using Clock = std::chrono::system_clock;
    const auto now = Clock::now();
    const std::time_t seconds = Clock::to_time_t(now);
    std::tm local_time{};
#if defined(_WIN32)
    localtime_s(&local_time, &seconds);
#else
    localtime_r(&seconds, &local_time);
#endif

    const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count() % 1000;
    const float seconds_today =
        static_cast<float>(local_time.tm_hour * 3600 + local_time.tm_min * 60 + local_time.tm_sec) +
        static_cast<float>(millis) * 0.001F;

    return {
        static_cast<float>(local_time.tm_year + 1900),
        static_cast<float>(local_time.tm_mon + 1),
        static_cast<float>(local_time.tm_mday),
        seconds_today};
}

} // namespace

namespace shaderdock::app {

void ShaderDockApp::update_viewport()
{
    if (!viewport_dirty_ || window_ == nullptr) {
        return;
    }

    SDL_GL_GetDrawableSize(window_, &drawable_width_, &drawable_height_);
    glViewport(0, 0, drawable_width_, drawable_height_);
    pipeline_.resize_targets(drawable_width_, drawable_height_);
    viewport_dirty_ = false;
}

void ShaderDockApp::render_frame(float elapsed_seconds, float delta_seconds)
{
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    frame_uniforms_.time_seconds = elapsed_seconds;
    frame_uniforms_.delta_seconds = delta_seconds;
    if (delta_seconds > 0.0F) {
        frame_uniforms_.frame_rate = 1.0F / delta_seconds;
    }
    frame_uniforms_.frame_index = frame_index_++;
    frame_uniforms_.channel_time.fill(0.0F);
    frame_uniforms_.mouse = build_mouse_uniform();
    frame_uniforms_.date = BuildDateUniform();

    update_input_providers(delta_seconds);
    pipeline_.render(frame_uniforms_, drawable_width_, drawable_height_);
}

} // namespace shaderdock::app
