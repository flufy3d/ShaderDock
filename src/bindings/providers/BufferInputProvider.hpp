#pragma once

#include <string>
#include <unordered_map>

#include "bindings/BufferInputBinding.hpp"
#include "bindings/providers/InputProvider.hpp"

namespace shaderdock::bindings {

class BufferInputProvider final : public InputProvider
{
public:
    BufferInputProvider() = default;

    void set_buffer_surfaces(std::unordered_map<std::string, render::BufferSurface>* surfaces);

    bool supports(manifest::PassInputType type) const override;
    std::unique_ptr<PassInputBinding> create_binding(const manifest::PassInput& input) override;

private:
    std::unordered_map<std::string, render::BufferSurface>* buffer_surfaces_ = nullptr;
};

using BufferInputProviderPtr = std::shared_ptr<BufferInputProvider>;

} // namespace shaderdock::bindings
