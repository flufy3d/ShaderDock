#include "bindings/providers/KeyboardInputProvider.hpp"

#include <algorithm>

#include <glad/glad.h>

namespace shaderdock::bindings {

KeyboardInputProvider::KeyboardInputProvider()
{
    reset_keyboard_state();
}

bool KeyboardInputProvider::supports(manifest::PassInputType type) const
{
    return type == manifest::PassInputType::kKeyboard;
}

std::unique_ptr<PassInputBinding> KeyboardInputProvider::create_binding(const manifest::PassInput& input)
{
    if (input.channel < 0 || input.channel > 3) {
        SDL_Log("KeyboardInputProvider: channel %d invalid for %s.", input.channel, input.id.c_str());
        return nullptr;
    }

    if (!ensure_keyboard_texture()) {
        SDL_Log("KeyboardInputProvider: unable to allocate keyboard texture.");
        return nullptr;
    }

    return std::make_unique<KeyboardInputBinding>(input.channel, texture_);
}

void KeyboardInputProvider::update(float delta_seconds)
{
    if (!texture_) {
        return;
    }

    const float clamped_delta = std::max(delta_seconds, 0.0F);
    bool modified = texture_dirty_;

    for (int key = 0; key < kKeyboardTextureWidth; ++key) {
        KeyState& state = key_state_[static_cast<std::size_t>(key)];
        state.seconds_since_change = std::min(state.seconds_since_change + clamped_delta, kKeyboardMaxTime);

        const uint8_t down_value = state.down ? 255 : 0;
        modified |= write_keyboard_pixel(0, key, down_value);

        const uint8_t toggle_value = state.toggle ? 255 : 0;
        modified |= write_keyboard_pixel(1, key, toggle_value);

        const float normalized_time = state.seconds_since_change / kKeyboardMaxTime;
        const uint8_t time_value = static_cast<uint8_t>(std::clamp(normalized_time, 0.0F, 1.0F) * 255.0F + 0.5F);
        modified |= write_keyboard_pixel(2, key, time_value);
    }

    if (!modified) {
        return;
    }

    glBindTexture(GL_TEXTURE_2D, texture_->id());
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexSubImage2D(
        GL_TEXTURE_2D,
        0,
        0,
        0,
        kKeyboardTextureWidth,
        kKeyboardTextureHeight,
        GL_RED,
        GL_UNSIGNED_BYTE,
        pixels_.data());
    glBindTexture(GL_TEXTURE_2D, 0);
    texture_dirty_ = false;
}

void KeyboardInputProvider::handle_key_event(const SDL_KeyboardEvent& key_event)
{
    const auto mapped_code = map_dom_keycode(key_event.keysym.sym);
    if (!mapped_code) {
        return;
    }

    const int key_index = *mapped_code;
    if (key_index < 0 || key_index >= kKeyboardTextureWidth) {
        return;
    }

    KeyState& state = key_state_[static_cast<std::size_t>(key_index)];
    if (key_event.type == SDL_KEYDOWN) {
        if (key_event.repeat != 0) {
            return;
        }
        if (!state.down) {
            state.down = true;
            state.toggle = !state.toggle;
            state.seconds_since_change = 0.0F;
            texture_dirty_ = true;
        }
    } else if (key_event.type == SDL_KEYUP) {
        if (!state.down) {
            return;
        }
        state.down = false;
        state.seconds_since_change = 0.0F;
        texture_dirty_ = true;
    }
}

bool KeyboardInputProvider::ensure_keyboard_texture()
{
    if (texture_) {
        return true;
    }

    GLuint texture_id = 0;
    glGenTextures(1, &texture_id);
    if (texture_id == 0) {
        SDL_Log("KeyboardInputProvider: glGenTextures failed.");
        return false;
    }

    glBindTexture(GL_TEXTURE_2D, texture_id);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_R8,
        kKeyboardTextureWidth,
        kKeyboardTextureHeight,
        0,
        GL_RED,
        GL_UNSIGNED_BYTE,
        pixels_.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);

    texture_ = std::make_shared<resources::TextureHandle>(
        texture_id,
        GL_TEXTURE_2D,
        kKeyboardTextureWidth,
        kKeyboardTextureHeight,
        false);
    texture_dirty_ = true;
    return true;
}

void KeyboardInputProvider::reset_keyboard_state()
{
    for (auto& state : key_state_) {
        state.down = false;
        state.toggle = false;
        state.seconds_since_change = kKeyboardMaxTime;
    }
    pixels_.fill(0);
    texture_dirty_ = true;
}

std::optional<int> KeyboardInputProvider::map_dom_keycode(SDL_Keycode key_code) const
{
    if (key_code >= SDLK_a && key_code <= SDLK_z) {
        return 'A' + static_cast<int>(key_code - SDLK_a);
    }
    if (key_code >= SDLK_0 && key_code <= SDLK_9) {
        return '0' + static_cast<int>(key_code - SDLK_0);
    }
    if (key_code >= SDLK_KP_0 && key_code <= SDLK_KP_9) {
        return '0' + static_cast<int>(key_code - SDLK_KP_0);
    }
    if (key_code >= SDLK_F1 && key_code <= SDLK_F12) {
        return 112 + static_cast<int>(key_code - SDLK_F1);
    }

    switch (key_code) {
        case SDLK_SPACE:
            return 32;
        case SDLK_RETURN:
        case SDLK_RETURN2:
        case SDLK_KP_ENTER:
            return 13;
        case SDLK_ESCAPE:
            return 27;
        case SDLK_BACKSPACE:
            return 8;
        case SDLK_TAB:
            return 9;
        case SDLK_DELETE:
            return 46;
        case SDLK_INSERT:
            return 45;
        case SDLK_HOME:
            return 36;
        case SDLK_END:
            return 35;
        case SDLK_PAGEUP:
            return 33;
        case SDLK_PAGEDOWN:
            return 34;
        case SDLK_LEFT:
            return 37;
        case SDLK_UP:
            return 38;
        case SDLK_RIGHT:
            return 39;
        case SDLK_DOWN:
            return 40;
        case SDLK_LSHIFT:
        case SDLK_RSHIFT:
            return 16;
        case SDLK_LCTRL:
        case SDLK_RCTRL:
            return 17;
        case SDLK_LALT:
        case SDLK_RALT:
            return 18;
        case SDLK_CAPSLOCK:
            return 20;
        case SDLK_LGUI:
        case SDLK_RGUI:
            return 91;
        case SDLK_SEMICOLON:
            return ';';
        case SDLK_COMMA:
            return ',';
        case SDLK_PERIOD:
            return '.';
        case SDLK_SLASH:
            return '/';
        case SDLK_BACKSLASH:
            return '\\';
        case SDLK_LEFTBRACKET:
            return '[';
        case SDLK_RIGHTBRACKET:
            return ']';
        case SDLK_MINUS:
            return '-';
        case SDLK_EQUALS:
            return '=';
        case SDLK_QUOTE:
            return '\'';
        default:
            break;
    }

    if (key_code >= 32 && key_code <= 126) {
        unsigned char ch = static_cast<unsigned char>(key_code);
        if (std::isalpha(ch)) {
            ch = static_cast<unsigned char>(std::toupper(ch));
        }
        return static_cast<int>(ch);
    }

    return std::nullopt;
}

bool KeyboardInputProvider::write_keyboard_pixel(int row, int column, uint8_t value)
{
    const int index = row * kKeyboardTextureWidth + column;
    uint8_t& current = pixels_[static_cast<std::size_t>(index)];
    if (current == value) {
        return false;
    }
    current = value;
    return true;
}

} // namespace shaderdock::bindings
