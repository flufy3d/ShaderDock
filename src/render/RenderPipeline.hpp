#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "render/FullscreenTriangle.hpp"
#include "render/PassInstance.hpp"
#include "render/PipelineTypes.hpp"
#include "resources/DemoManifest.hpp"
#include "resources/TextureLoader.hpp"

namespace shaderdock::render {

class RenderPipeline
{
public:
    RenderPipeline() = default;
    ~RenderPipeline();

    RenderPipeline(const RenderPipeline&) = delete;
    RenderPipeline& operator=(const RenderPipeline&) = delete;

    bool initialize(
        const resources::DemoManifest& manifest,
        const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings,
        FullscreenTriangle* fullscreen_triangle,
        int hardware_performance_level);

    void shutdown();

    bool resize_targets(int width, int height);
    void render(const FrameUniforms& frame, int drawable_width, int drawable_height);

private:
    bool build_common_source(const resources::DemoManifest& manifest);
    bool prepare_passes(
        const resources::DemoManifest& manifest,
        const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings);

    bool ensure_surface_size(BufferSurface& surface, int width, int height);

    FullscreenTriangle* fullscreen_triangle_ = nullptr;
    std::string common_source_;
    std::vector<PassInstance> execution_order_;
    std::unordered_map<std::string, BufferSurface> buffer_surfaces_;
    int hardware_performance_level_ = 0;
};

} // namespace shaderdock::render
