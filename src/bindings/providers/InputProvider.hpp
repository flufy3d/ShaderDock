#pragma once

#include <memory>

#include "manifest/ManifestTypes.hpp"

namespace shaderdock::bindings {

class PassInputBinding;

class InputProvider
{
public:
    virtual ~InputProvider() = default;

    virtual bool supports(manifest::PassInputType type) const = 0;
    virtual std::unique_ptr<PassInputBinding> create_binding(const manifest::PassInput& input) = 0;
    virtual void update(float /*delta_seconds*/) {}
};

using InputProviderPtr = std::shared_ptr<InputProvider>;

} // namespace shaderdock::bindings
