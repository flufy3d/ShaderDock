#include "bindings/providers/KeyboardInputProvider.hpp"

#include <algorithm>

#include <glad/glad.h>

namespace {

constexpr int kButtonLeftCode = 245;
constexpr int kButtonMiddleCode = 246;
constexpr int kButtonRightCode = 247;
constexpr int kScrollUpCode = 250;
constexpr int kScrollDownCode = 251;

} // namespace

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

        const uint8_t press_value = state.press_latched ? 255 : 0;
        modified |= write_keyboard_pixel(1, key, press_value);
        if (state.press_latched) {
            state.press_latched = false;
        }

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
    const auto mapped_codes = map_dom_keycodes(key_event.keysym.sym);
    if (mapped_codes.empty()) {
        return;
    }

    if (key_event.type == SDL_KEYDOWN) {
        if (key_event.repeat != 0) {
            return;
        }
        for (int code : mapped_codes) {
            press_key(code);
        }
    } else if (key_event.type == SDL_KEYUP) {
        for (int code : mapped_codes) {
            release_key(code);
        }
    }
}

void KeyboardInputProvider::handle_mouse_button_event(const SDL_MouseButtonEvent& button_event)
{
    const auto mapped_code = map_mouse_button_code(button_event.button);
    if (!mapped_code) {
        return;
    }

    if (button_event.type == SDL_MOUSEBUTTONDOWN) {
        press_key(*mapped_code);
    } else if (button_event.type == SDL_MOUSEBUTTONUP) {
        release_key(*mapped_code);
    }
}

void KeyboardInputProvider::handle_mouse_wheel_event(const SDL_MouseWheelEvent& wheel_event)
{
    int vertical = wheel_event.y;
    if (wheel_event.direction == SDL_MOUSEWHEEL_FLIPPED) {
        vertical = -vertical;
    }

    if (vertical > 0) {
        pulse_key(kScrollUpCode);
    } else if (vertical < 0) {
        pulse_key(kScrollDownCode);
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
        state.press_latched = false;
        state.seconds_since_change = kKeyboardMaxTime;
    }
    pixels_.fill(0);
    texture_dirty_ = true;
}

std::vector<int> KeyboardInputProvider::map_dom_keycodes(SDL_Keycode key_code) const
{
    std::vector<int> codes;
    codes.reserve(3);

    if (key_code >= SDLK_a && key_code <= SDLK_z) {
        codes.push_back('A' + static_cast<int>(key_code - SDLK_a));
        return codes;
    }
    if (key_code >= SDLK_0 && key_code <= SDLK_9) {
        codes.push_back('0' + static_cast<int>(key_code - SDLK_0));
        return codes;
    }
    if (key_code >= SDLK_KP_0 && key_code <= SDLK_KP_9) {
        codes.push_back('0' + static_cast<int>(key_code - SDLK_KP_0));
        return codes;
    }
    if (key_code >= SDLK_F1 && key_code <= SDLK_F12) {
        codes.push_back(112 + static_cast<int>(key_code - SDLK_F1));
        return codes;
    }

    switch (key_code) {
        case SDLK_SPACE:
            codes.push_back(32);
            break;
        case SDLK_RETURN:
        case SDLK_RETURN2:
        case SDLK_KP_ENTER:
            codes.push_back(13);
            break;
        case SDLK_ESCAPE:
            codes.push_back(27);
            break;
        case SDLK_BACKSPACE:
            codes.push_back(8);
            break;
        case SDLK_TAB:
            codes.push_back(9);
            break;
        case SDLK_DELETE:
            codes.push_back(46);
            break;
        case SDLK_INSERT:
            codes.push_back(45);
            break;
        case SDLK_HOME:
            codes.push_back(36);
            break;
        case SDLK_END:
            codes.push_back(35);
            break;
        case SDLK_PAGEUP:
            codes.push_back(33);
            break;
        case SDLK_PAGEDOWN:
            codes.push_back(34);
            break;
        case SDLK_LEFT:
            codes.push_back(37);
            break;
        case SDLK_UP:
            codes.push_back(38);
            break;
        case SDLK_RIGHT:
            codes.push_back(39);
            break;
        case SDLK_DOWN:
            codes.push_back(40);
            break;
        case SDLK_LSHIFT:
        case SDLK_RSHIFT:
            codes.push_back(16);
            break;
        case SDLK_LCTRL:
        case SDLK_RCTRL:
            codes.push_back(17);
            break;
        case SDLK_LALT:
        case SDLK_RALT:
            codes.push_back(18);
            break;
        case SDLK_CAPSLOCK:
            codes.push_back(20);
            break;
        case SDLK_LGUI:
        case SDLK_RGUI:
            codes.push_back(91);
            break;
        case SDLK_SEMICOLON:
            codes.push_back(';');
            break;
        case SDLK_COMMA:
            codes.push_back(',');
            break;
        case SDLK_PERIOD:
            codes.push_back('.');
            break;
        case SDLK_SLASH:
            codes.push_back('/');
            break;
        case SDLK_BACKSLASH:
            codes.push_back('\\');
            break;
        case SDLK_LEFTBRACKET:
            codes.push_back('[');
            break;
        case SDLK_RIGHTBRACKET:
            codes.push_back(']');
            break;
        case SDLK_MINUS:
            codes.push_back('-');
            codes.push_back(173);
            break;
        case SDLK_EQUALS:
            codes.push_back('=');
            break;
        case SDLK_KP_PLUS:
            codes.push_back(107);
            codes.push_back('+');
            break;
        case SDLK_KP_MINUS:
            codes.push_back(109);
            codes.push_back('-');
            codes.push_back(173);
            break;
        case SDLK_QUOTE:
            codes.push_back('\'');
            break;
        default:
            break;
    }

    if (!codes.empty()) {
        return codes;
    }

    if (key_code >= 32 && key_code <= 126) {
        unsigned char ch = static_cast<unsigned char>(key_code);
        if (std::isalpha(ch)) {
            ch = static_cast<unsigned char>(std::toupper(ch));
        }
        codes.push_back(static_cast<int>(ch));
    }

    return codes;
}

std::optional<int> KeyboardInputProvider::map_mouse_button_code(uint8_t sdl_button) const
{
    switch (sdl_button) {
        case SDL_BUTTON_LEFT:
            return kButtonLeftCode;
        case SDL_BUTTON_MIDDLE:
            return kButtonMiddleCode;
        case SDL_BUTTON_RIGHT:
            return kButtonRightCode;
        default:
            break;
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

void KeyboardInputProvider::press_key(int key_index)
{
    if (key_index < 0 || key_index >= kKeyboardTextureWidth) {
        return;
    }

    KeyState& state = key_state_[static_cast<std::size_t>(key_index)];
    if (state.down) {
        return;
    }

    state.down = true;
    state.press_latched = true;
    state.seconds_since_change = 0.0F;
    texture_dirty_ = true;
}

void KeyboardInputProvider::release_key(int key_index)
{
    if (key_index < 0 || key_index >= kKeyboardTextureWidth) {
        return;
    }

    KeyState& state = key_state_[static_cast<std::size_t>(key_index)];
    if (!state.down) {
        return;
    }

    state.down = false;
    state.press_latched = false;
    state.seconds_since_change = 0.0F;
    texture_dirty_ = true;
}

void KeyboardInputProvider::pulse_key(int key_index)
{
    if (key_index < 0 || key_index >= kKeyboardTextureWidth) {
        return;
    }

    KeyState& state = key_state_[static_cast<std::size_t>(key_index)];
    state.press_latched = true;
    state.seconds_since_change = 0.0F;
    texture_dirty_ = true;
}

} // namespace shaderdock::bindings
