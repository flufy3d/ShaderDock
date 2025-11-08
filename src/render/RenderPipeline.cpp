#include "render/RenderPipeline.hpp"

#include <SDL.h>

#include <algorithm>
#include <cctype>
#include <sstream>
#include <string>
#include <string_view>

#include <glad/glad.h>

#include "render/PassGraph.hpp"
#include "resources/AssetIO.hpp"

namespace shaderdock::render {

namespace {

std::string StripVersionPragmas(std::string_view source)
{
    std::ostringstream oss;
    std::istringstream iss{std::string(source)};
    std::string line;
    while (std::getline(iss, line)) {
        std::string trimmed = line;
        trimmed.erase(trimmed.begin(), std::find_if(trimmed.begin(), trimmed.end(), [](unsigned char ch) {
            return !std::isspace(ch);
        }));
        if (trimmed.rfind("#version", 0) == 0) {
            continue;
        }
        oss << line << '\n';
    }
    return oss.str();
}

} // namespace

RenderPipeline::~RenderPipeline()
{
    shutdown();
}

bool RenderPipeline::initialize(
    const resources::DemoManifest& manifest,
    const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings,
    FullscreenTriangle* fullscreen_triangle,
    int hardware_performance_level)
{
    shutdown();

    fullscreen_triangle_ = fullscreen_triangle;
    if (fullscreen_triangle_ == nullptr) {
        SDL_Log("RenderPipeline: fullscreen triangle is null.");
        return false;
    }
    hardware_performance_level_ = hardware_performance_level;

    if (!build_common_source(manifest)) {
        return false;
    }

    if (!prepare_passes(manifest, texture_bindings)) {
        return false;
    }

    return true;
}

void RenderPipeline::shutdown()
{
    execution_order_.clear();
    fullscreen_triangle_ = nullptr;
    hardware_performance_level_ = 0;

    for (auto& surface_entry : buffer_surfaces_) {
        surface_entry.second.reset();
    }
    buffer_surfaces_.clear();

    common_source_.clear();
}

bool RenderPipeline::resize_targets(int width, int height)
{
    bool success = true;
    for (auto& [_, surface] : buffer_surfaces_) {
        success &= ensure_surface_size(surface, width, height);
    }
    return success;
}

void RenderPipeline::render(const FrameUniforms& frame, int drawable_width, int drawable_height)
{
    if (execution_order_.empty() || fullscreen_triangle_ == nullptr) {
        return;
    }

    for (auto& pass : execution_order_) {
        BufferSurface* target_surface = pass.target_buffer();
        const bool rendering_to_buffer = target_surface != nullptr;

        int target_width = drawable_width;
        int target_height = drawable_height;

        if (rendering_to_buffer) {
            if (!ensure_surface_size(*target_surface, drawable_width, drawable_height)) {
                continue;
            }
            target_width = target_surface->width;
            target_height = target_surface->height;
            glBindFramebuffer(GL_FRAMEBUFFER, target_surface->write_framebuffer());
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        }

        glViewport(0, 0, target_width, target_height);

        pass.use_program();
        pass.apply_uniforms(frame, target_width, target_height);
        pass.bind_inputs();

        fullscreen_triangle_->draw();

        pass.unbind_inputs();

        if (rendering_to_buffer) {
            target_surface->swap();
            target_surface->last_updated_seconds = frame.time_seconds;
        }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

bool RenderPipeline::build_common_source(const resources::DemoManifest& manifest)
{
    common_source_.clear();
    for (const auto& pass : manifest.passes) {
        if (pass.type != resources::RenderPassType::kCommon) {
            continue;
        }

        std::string source = resources::ReadTextFile(pass.source_path.string());
        if (source.empty()) {
            SDL_Log("RenderPipeline: failed to load common shader source %s.", pass.source_file.c_str());
            return false;
        }

        common_source_ += "\n// ---- Common: " + pass.name + " ----\n";
        common_source_ += StripVersionPragmas(source);
        common_source_ += "\n";
    }
    return true;
}

bool RenderPipeline::prepare_passes(
    const resources::DemoManifest& manifest,
    const std::unordered_map<std::string, std::shared_ptr<resources::TextureHandle>>& texture_bindings)
{
    execution_order_.clear();
    buffer_surfaces_.clear();

    PassExecutionPlan plan;
    if (!BuildPassExecutionPlan(manifest, plan)) {
        return false;
    }

    for (const auto& entry : plan.buffer_sources) {
        const std::string& buffer_id = entry.first;
        buffer_surfaces_[buffer_id] = BufferSurface{.id = buffer_id};
    }

    execution_order_.reserve(plan.ordered_passes.size());

    std::unordered_map<std::string, BufferSurface*> id_to_surface;
    for (auto& [id, surface] : buffer_surfaces_) {
        id_to_surface[id] = &surface;
    }

    for (const resources::RenderPass* pass : plan.ordered_passes) {
        BufferSurface* target_surface = nullptr;
        const auto history_it = plan.uses_history.find(pass);
        const bool uses_history = history_it != plan.uses_history.end() && history_it->second;

        if (pass->type == resources::RenderPassType::kBuffer) {
            auto id_it = plan.buffer_ids.find(pass);
            if (id_it == plan.buffer_ids.end()) {
                SDL_Log("RenderPipeline: buffer pass %s missing assigned ID.", pass->name.c_str());
                return false;
            }

            auto surface_it = id_to_surface.find(id_it->second);
            if (surface_it == id_to_surface.end()) {
                SDL_Log("RenderPipeline: surface missing for buffer %s.", id_it->second.c_str());
                return false;
            }

            surface_it->second->double_buffer = uses_history;
            target_surface = surface_it->second;
        }

        PassInstance instance;
        if (!instance.initialize(
                *pass,
                uses_history,
                target_surface,
                id_to_surface,
                texture_bindings,
                common_source_,
                hardware_performance_level_)) {
            return false;
        }

        execution_order_.emplace_back(std::move(instance));
    }

    return true;
}

bool RenderPipeline::ensure_surface_size(BufferSurface& surface, int width, int height)
{
    if (width <= 0 || height <= 0) {
        SDL_Log("RenderPipeline: invalid surface size %dx%d.", width, height);
        return false;
    }

    if (surface.width == width && surface.height == height && surface.textures[0] != 0) {
        return true;
    }

    surface.reset();
    surface.width = width;
    surface.height = height;

    const int target_count = surface.double_buffer ? 2 : 1;
    for (int i = 0; i < target_count; ++i) {
        glGenTextures(1, &surface.textures[i]);
        glBindTexture(GL_TEXTURE_2D, surface.textures[i]);
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            GL_RGBA16F,
            width,
            height,
            0,
            GL_RGBA,
            GL_HALF_FLOAT,
            nullptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glGenFramebuffers(1, &surface.framebuffers[i]);
        glBindFramebuffer(GL_FRAMEBUFFER, surface.framebuffers[i]);
        glFramebufferTexture2D(
            GL_FRAMEBUFFER,
            GL_COLOR_ATTACHMENT0,
            GL_TEXTURE_2D,
            surface.textures[i],
            0);

        const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            SDL_Log("RenderPipeline: framebuffer incomplete for buffer '%s'.", surface.id.c_str());
            surface.reset();
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glBindTexture(GL_TEXTURE_2D, 0);
            return false;
        }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);

    surface.front_index = 0;
    return true;
}

} // namespace shaderdock::render
