#pragma once

#include "bindings/PassInputBinding.hpp"
#include "render/PipelineTypes.hpp"

namespace shaderdock::bindings {

class BufferInputBinding final : public PassInputBinding
{
public:
    BufferInputBinding(int channel, render::BufferSurface* surface);

    void bind() const override;
    void unbind() const override;
    float width() const override;
    float height() const override;
    float last_updated_seconds() const override;

private:
    render::BufferSurface* surface_ = nullptr;
};

} // namespace shaderdock::bindings
