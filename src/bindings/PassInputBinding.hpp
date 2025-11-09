#pragma once

#include <memory>
#include <string>
#include <unordered_map>

#include <glad/glad.h>

#include "manifest/ManifestTypes.hpp"

namespace shaderdock::bindings {

class PassInputBinding
{
public:
    PassInputBinding(int channel, manifest::PassInputType type);
    virtual ~PassInputBinding() = default;

    PassInputBinding(const PassInputBinding&) = delete;
    PassInputBinding& operator=(const PassInputBinding&) = delete;

    int channel() const { return channel_; }
    manifest::PassInputType type() const { return type_; }

    virtual void bind() const = 0;
    virtual void unbind() const = 0;
    virtual float width() const = 0;
    virtual float height() const = 0;
    virtual float last_updated_seconds() const { return 0.0F; }

protected:
    void activate_texture_unit() const;

private:
    int channel_ = 0;
    manifest::PassInputType type_ = manifest::PassInputType::kTexture;
};

} // namespace shaderdock::bindings
