#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "bindings/providers/BufferInputProvider.hpp"
#include "bindings/providers/InputProvider.hpp"
#include "manifest/ManifestTypes.hpp"
#include "render/FullscreenTriangle.hpp"
#include "render/PassInstance.hpp"
#include "render/PipelineTypes.hpp"
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
        const manifest::DemoManifest& manifest,
        const std::vector<bindings::InputProviderPtr>& input_providers,
        FullscreenTriangle* fullscreen_triangle,
        int hardware_performance_level);

    void shutdown();

    bool resize_targets(int width, int height);
    void render(const FrameUniforms& frame, int drawable_width, int drawable_height);

private:
    bool build_common_source(const manifest::DemoManifest& manifest);
    bool prepare_passes(const manifest::DemoManifest& manifest);
    bool ensure_surface_size(BufferSurface& surface, int width, int height);
    std::unique_ptr<bindings::PassInputBinding> create_input_binding(const manifest::PassInput& input) const;

    FullscreenTriangle* fullscreen_triangle_ = nullptr;
    std::string common_source_;
    std::vector<PassInstance> execution_order_;
    std::unordered_map<std::string, BufferSurface> buffer_surfaces_;
    int hardware_performance_level_ = 0;
    std::vector<bindings::InputProviderPtr> input_providers_;
    bindings::BufferInputProviderPtr buffer_provider_;
};

} // namespace shaderdock::render
