#pragma once

#include <array>
#include <memory>
#include <optional>

#include <SDL.h>

#include "bindings/KeyboardInputBinding.hpp"
#include "bindings/providers/InputProvider.hpp"
#include "resources/TextureLoader.hpp"

namespace shaderdock::bindings {

class KeyboardInputProvider final : public InputProvider
{
public:
    KeyboardInputProvider();

    bool supports(manifest::PassInputType type) const override;
    std::unique_ptr<PassInputBinding> create_binding(const manifest::PassInput& input) override;
    void update(float delta_seconds) override;

    void handle_key_event(const SDL_KeyboardEvent& key_event);
    void handle_mouse_button_event(const SDL_MouseButtonEvent& button_event);
    void handle_mouse_wheel_event(const SDL_MouseWheelEvent& wheel_event);

private:
    struct KeyState {
        bool down = false;
        bool pending_press = false;
        float seconds_since_change = 0.0F;
    };

    static constexpr int kKeyboardTextureWidth = 256;
    static constexpr int kKeyboardTextureHeight = 3;
    static constexpr float kKeyboardMaxTime = 600.0F;

    bool ensure_keyboard_texture();
    void reset_keyboard_state();
    std::optional<int> map_dom_keycode(SDL_Keycode key_code) const;
    std::optional<int> map_mouse_button_code(uint8_t sdl_button) const;
    bool write_keyboard_pixel(int row, int column, uint8_t value);
    void press_key(int key_index);
    void release_key(int key_index);
    void pulse_key(int key_index);

    std::shared_ptr<resources::TextureHandle> texture_;
    std::array<KeyState, kKeyboardTextureWidth> key_state_{};
    std::array<uint8_t, kKeyboardTextureWidth * kKeyboardTextureHeight> pixels_{};
    bool texture_dirty_ = false;
};

using KeyboardInputProviderPtr = std::shared_ptr<KeyboardInputProvider>;

} // namespace shaderdock::bindings
