#pragma once

#include <memory>

#include "bindings/PassInputBinding.hpp"

namespace shaderdock::resources {
class TextureHandle;
}

namespace shaderdock::bindings {

class KeyboardInputBinding final : public PassInputBinding
{
public:
    KeyboardInputBinding(int channel, std::shared_ptr<resources::TextureHandle> texture);

    void bind() const override;
    void unbind() const override;
    float width() const override;
    float height() const override;

private:
    std::shared_ptr<resources::TextureHandle> texture_;
};

} // namespace shaderdock::bindings
