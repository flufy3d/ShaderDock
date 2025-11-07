#pragma once

#include <array>
#include <memory>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "render/PipelineTypes.hpp"
#include "render/ShaderProgram.hpp"
#include "resources/DemoManifest.hpp"
#include "resources/TextureLoader.hpp"
#include <glad/glad.h>

namespace shaderdock::render {

class PassInstance
{
public:
    PassInstance() = default;
    ~PassInstance() = default;

    PassInstance(const PassInstance&) = delete;
    PassInstance& operator=(const PassInstance&) = delete;
    PassInstance(PassInstance&&) noexcept = default;
    PassInstance& operator=(PassInstance&&) noexcept = default;

    bool initialize(
        const resources::RenderPass& pass,
        bool uses_history,
        BufferSurface* target_buffer,
        const std::unordered_map<std::string, BufferSurface*>& buffer_sources,
        const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings,
        const std::string& common_source);

    const resources::RenderPass* manifest() const { return manifest_; }
    BufferSurface* target_buffer() const { return target_buffer_; }

    void use_program() const { program_.use(); }
    void bind_inputs() const;
    void unbind_inputs() const;
    void apply_uniforms(const FrameUniforms& frame, int target_width, int target_height) const;

private:
    struct InputBinding {
        int channel = 0;
        resources::PassInputType type = resources::PassInputType::kTexture;
        std::shared_ptr<resources::TextureHandle> texture;
        BufferSurface* buffer = nullptr;
    };

    struct UniformLocations {
        GLint iResolution = -1;
        GLint iTime = -1;
        GLint iTimeDelta = -1;
        GLint iFrameRate = -1;
        GLint iFrame = -1;
        GLint iMouse = -1;
        GLint iDate = -1;
        GLint iChannelTime = -1;
        GLint iChannelResolution = -1;
        std::array<GLint, 4> channel_samplers{ -1, -1, -1, -1 };
    };

    std::string load_pass_source(const resources::RenderPass& pass) const;
    std::string build_fragment_source(const resources::RenderPass& pass, std::string_view raw, const std::string& common_source) const;
    void cache_uniform_locations();
    bool build_input_bindings(
        const resources::RenderPass& pass,
        const std::unordered_map<std::string, BufferSurface*>& buffer_sources,
        const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings);

    const resources::RenderPass* manifest_ = nullptr;
    bool uses_history_ = false;
    BufferSurface* target_buffer_ = nullptr;
    ShaderProgram program_;
    std::vector<InputBinding> inputs_;
    UniformLocations uniforms_;
};

} // namespace shaderdock::render
