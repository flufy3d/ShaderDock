#include "bindings/BufferInputBinding.hpp"

#include <glad/glad.h>

namespace shaderdock::bindings {

namespace {

GLint ToMinFilter(manifest::SamplerFilter filter)
{
    switch (filter) {
        case manifest::SamplerFilter::kLinear:
            return GL_LINEAR;
        case manifest::SamplerFilter::kMipmap:
            return GL_LINEAR;
        case manifest::SamplerFilter::kNearest:
        default:
            return GL_NEAREST;
    }
}

GLint ToMagFilter(manifest::SamplerFilter filter)
{
    switch (filter) {
        case manifest::SamplerFilter::kLinear:
        case manifest::SamplerFilter::kMipmap:
            return GL_LINEAR;
        case manifest::SamplerFilter::kNearest:
        default:
            return GL_NEAREST;
    }
}

GLint ToWrapMode(manifest::SamplerWrap wrap)
{
    return wrap == manifest::SamplerWrap::kRepeat ? GL_REPEAT : GL_CLAMP_TO_EDGE;
}

} // namespace

BufferInputBinding::BufferInputBinding(
    int channel,
    render::BufferSurface* surface,
    const manifest::SamplerDesc& sampler)
    : PassInputBinding(channel, manifest::PassInputType::kBuffer)
    , surface_(surface)
{
    apply_sampler_desc(sampler);
}

BufferInputBinding::~BufferInputBinding()
{
    if (sampler_object_ != 0) {
        glDeleteSamplers(1, &sampler_object_);
        sampler_object_ = 0;
    }
}

void BufferInputBinding::bind() const
{
    if (!surface_) {
        return;
    }
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, surface_->read_texture());
    if (sampler_object_ != 0) {
        glBindSampler(channel(), sampler_object_);
    }
}

void BufferInputBinding::unbind() const
{
    activate_texture_unit();
    glBindTexture(GL_TEXTURE_2D, 0);
    if (sampler_object_ != 0) {
        glBindSampler(channel(), 0);
    }
}

float BufferInputBinding::width() const
{
    return surface_ ? static_cast<float>(surface_->width) : 0.0F;
}

float BufferInputBinding::height() const
{
    return surface_ ? static_cast<float>(surface_->height) : 0.0F;
}

float BufferInputBinding::last_updated_seconds() const
{
    return surface_ ? surface_->last_updated_seconds : 0.0F;
}

void BufferInputBinding::apply_sampler_desc(const manifest::SamplerDesc& sampler)
{
    if (sampler_object_ == 0) {
        glGenSamplers(1, &sampler_object_);
    }
    if (sampler_object_ == 0) {
        return;
    }

    const GLint min_filter = ToMinFilter(sampler.filter);
    const GLint mag_filter = ToMagFilter(sampler.filter);
    const GLint wrap = ToWrapMode(sampler.wrap);

    glSamplerParameteri(sampler_object_, GL_TEXTURE_MIN_FILTER, min_filter);
    glSamplerParameteri(sampler_object_, GL_TEXTURE_MAG_FILTER, mag_filter);
    glSamplerParameteri(sampler_object_, GL_TEXTURE_WRAP_S, wrap);
    glSamplerParameteri(sampler_object_, GL_TEXTURE_WRAP_T, wrap);
}

} // namespace shaderdock::bindings
