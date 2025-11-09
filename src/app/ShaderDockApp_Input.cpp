#include "app/ShaderDockApp.hpp"

#include <SDL.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>

#include <glad/glad.h>

namespace shaderdock::app {

void ShaderDockApp::process_event(const SDL_Event& event)
{
    switch (event.type) {
        case SDL_QUIT:
            running_ = false;
            break;
        case SDL_KEYDOWN:
            handle_key_event(event.key);
            if (event.key.keysym.sym == SDLK_ESCAPE) {
                running_ = false;
            }
            break;
        case SDL_KEYUP:
            handle_key_event(event.key);
            break;
        case SDL_MOUSEBUTTONDOWN:
            if (event.button.button == SDL_BUTTON_LEFT) {
                update_mouse_position(event.button.x, event.button.y);
                mouse_button_down_ = true;
                mouse_tap_pending_ = false;
                mouse_dragged_ = false;
                mouse_click_x_ = mouse_current_x_;
                mouse_click_y_ = mouse_current_y_;
            }
            if (keyboard_input_provider_) {
                keyboard_input_provider_->handle_mouse_button_event(event.button);
            }
            break;
        case SDL_MOUSEBUTTONUP:
            if (event.button.button == SDL_BUTTON_LEFT) {
                update_mouse_position(event.button.x, event.button.y);
                mouse_button_down_ = false;
                mouse_release_x_ = mouse_current_x_;
                mouse_release_y_ = mouse_current_y_;
                mouse_tap_pending_ = !mouse_dragged_;
                mouse_dragged_ = false;
            }
            if (keyboard_input_provider_) {
                keyboard_input_provider_->handle_mouse_button_event(event.button);
            }
            break;
        case SDL_MOUSEMOTION:
            update_mouse_position(event.motion.x, event.motion.y);
            break;
        case SDL_MOUSEWHEEL:
            if (keyboard_input_provider_) {
                keyboard_input_provider_->handle_mouse_wheel_event(event.wheel);
            }
            break;
        case SDL_WINDOWEVENT:
            if (event.window.event == SDL_WINDOWEVENT_RESIZED ||
                event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                viewport_dirty_ = true;
            }
            break;
        default:
            break;
    }
}

void ShaderDockApp::update_mouse_position(int window_x, int window_y)
{
    if (window_ == nullptr) {
        return;
    }

    int window_width = 0;
    int window_height = 0;
    SDL_GetWindowSize(window_, &window_width, &window_height);

    if (window_width <= 0 || window_height <= 0 || drawable_width_ <= 0 || drawable_height_ <= 0) {
        mouse_current_x_ = 0.0F;
        mouse_current_y_ = 0.0F;
        return;
    }

    const float scale_x = static_cast<float>(drawable_width_) / static_cast<float>(window_width);
    const float scale_y = static_cast<float>(drawable_height_) / static_cast<float>(window_height);

    float pixel_x = static_cast<float>(window_x) * scale_x;
    float pixel_y = static_cast<float>(window_y) * scale_y;

    pixel_x = std::clamp(pixel_x, 0.0F, static_cast<float>(drawable_width_));
    pixel_y = std::clamp(pixel_y, 0.0F, static_cast<float>(drawable_height_));

    mouse_current_x_ = pixel_x;
    mouse_current_y_ = static_cast<float>(drawable_height_) - pixel_y - 1.0F;
    mouse_current_y_ = std::clamp(mouse_current_y_, 0.0F, static_cast<float>(drawable_height_));

    if (mouse_button_down_ && !mouse_dragged_) {
        constexpr float drag_threshold = 1.0F;
        if (std::abs(mouse_current_x_ - mouse_click_x_) > drag_threshold ||
            std::abs(mouse_current_y_ - mouse_click_y_) > drag_threshold) {
            mouse_dragged_ = true;
        }
    }
}

std::array<float, 4> ShaderDockApp::build_mouse_uniform()
{
    std::array<float, 4> mouse{0.0F, 0.0F, 0.0F, 0.0F};

    if (mouse_button_down_) {
        mouse[0] = mouse_current_x_;
        mouse[1] = mouse_current_y_;
        mouse[2] = mouse_click_x_;
        mouse[3] = -mouse_click_y_;

        // Track the most recent position so we can reference it after release.
        mouse_release_x_ = mouse_current_x_;
        mouse_release_y_ = mouse_current_y_;
    } else {
        mouse[0] = mouse_release_x_;
        mouse[1] = mouse_release_y_;
        mouse[2] = -mouse_release_x_;
        mouse[3] = mouse_tap_pending_ ? mouse_release_y_ : -mouse_release_y_;

        if (mouse_tap_pending_) {
            mouse_tap_pending_ = false;
        }
    }

    return mouse;
}

void ShaderDockApp::handle_key_event(const SDL_KeyboardEvent& key_event)
{
    if (keyboard_input_provider_) {
        keyboard_input_provider_->handle_key_event(key_event);
    }
}

void ShaderDockApp::update_input_providers(float delta_seconds)
{
    for (const auto& provider : input_providers_) {
        if (provider) {
            provider->update(delta_seconds);
        }
    }
}

} // namespace shaderdock::app
