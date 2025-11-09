#pragma once

#include <glad/glad.h>

#include "bindings/PassInputBinding.hpp"
#include "manifest/ManifestTypes.hpp"
#include "render/PipelineTypes.hpp"

namespace shaderdock::bindings {

class BufferInputBinding final : public PassInputBinding
{
public:
    BufferInputBinding(
        int channel,
        render::BufferSurface* surface,
        const manifest::SamplerDesc& sampler);
    ~BufferInputBinding() override;

    void bind() const override;
    void unbind() const override;
    float width() const override;
    float height() const override;
    float last_updated_seconds() const override;

private:
    void apply_sampler_desc(const manifest::SamplerDesc& sampler);

    render::BufferSurface* surface_ = nullptr;
    GLuint sampler_object_ = 0;
};

} // namespace shaderdock::bindings
