#pragma once

#include <memory>
#include <string>
#include <unordered_map>

#include "bindings/CubemapInputBinding.hpp"
#include "bindings/providers/InputProvider.hpp"
#include "resources/TextureLoader.hpp"

namespace shaderdock::bindings {

class CubemapInputProvider final : public InputProvider
{
public:
    explicit CubemapInputProvider(resources::TextureCache& cache);

    bool supports(manifest::PassInputType type) const override;
    std::unique_ptr<PassInputBinding> create_binding(const manifest::PassInput& input) override;

private:
    std::shared_ptr<resources::TextureHandle> resolve_texture(const manifest::PassInput& input);

    resources::TextureCache& cache_;
    std::unordered_map<std::string, std::weak_ptr<resources::TextureHandle>> bindings_;
};

} // namespace shaderdock::bindings
