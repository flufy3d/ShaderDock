#include "render/PassGraph.hpp"

#include <SDL.h>

#include <queue>
#include <string>
#include <unordered_map>

namespace shaderdock::render {

namespace {

bool IsBufferPass(const manifest::RenderPass& pass)
{
    return pass.type == manifest::RenderPassType::kBuffer;
}

bool IsExecutablePass(const manifest::RenderPass& pass)
{
    return pass.type == manifest::RenderPassType::kBuffer ||
        pass.type == manifest::RenderPassType::kImage;
}

bool ValidateBufferOutputs(
    const manifest::RenderPass& pass,
    std::unordered_map<std::string, const manifest::RenderPass*>& buffer_sources,
    std::unordered_map<const manifest::RenderPass*, std::string>& pass_to_buffer_id)
{
    std::string declared_id;
    for (const auto& output : pass.outputs) {
        if (output.channel != 0) {
            SDL_Log(
                "PassGraph: buffer pass %s declares unsupported output channel %d.",
                pass.name.c_str(),
                output.channel);
            return false;
        }
        if (output.id.empty()) {
            SDL_Log(
                "PassGraph: buffer pass %s declares an empty output id.",
                pass.name.c_str());
            return false;
        }
        if (!declared_id.empty()) {
            SDL_Log(
                "PassGraph: buffer pass %s declares multiple outputs; only one is supported.",
                pass.name.c_str());
            return false;
        }
        declared_id = output.id;
        if (!buffer_sources.emplace(output.id, &pass).second) {
            SDL_Log(
                "PassGraph: duplicate buffer output id '%s' declared by pass %s.",
                output.id.c_str(),
                pass.name.c_str());
            return false;
        }
    }

    if (declared_id.empty()) {
        SDL_Log("PassGraph: buffer pass %s is missing an output declaration.", pass.name.c_str());
        return false;
    }

    pass_to_buffer_id.emplace(&pass, declared_id);
    return true;
}

} // namespace

bool BuildPassExecutionPlan(const manifest::DemoManifest& manifest, PassExecutionPlan& out_plan)
{
    out_plan = PassExecutionPlan{};

    std::vector<const manifest::RenderPass*> executable_passes;
    executable_passes.reserve(manifest.passes.size());

    std::unordered_map<const manifest::RenderPass*, std::string> pass_to_buffer_id;
    std::unordered_map<std::string, const manifest::RenderPass*> buffer_id_to_pass;
    pass_to_buffer_id.reserve(manifest.passes.size());

    for (const auto& pass : manifest.passes) {
        if (IsBufferPass(pass)) {
            if (!ValidateBufferOutputs(pass, buffer_id_to_pass, pass_to_buffer_id)) {
                return false;
            }
        }
        if (IsExecutablePass(pass)) {
            executable_passes.push_back(&pass);
        }
    }

    if (executable_passes.empty()) {
        out_plan.buffer_ids = std::move(pass_to_buffer_id);
        out_plan.buffer_sources = std::move(buffer_id_to_pass);
        return true;
    }

    std::unordered_map<const manifest::RenderPass*, std::size_t> index_lookup;
    for (std::size_t i = 0; i < executable_passes.size(); ++i) {
        index_lookup[executable_passes[i]] = i;
    }

    std::vector<std::vector<std::size_t>> adjacency(executable_passes.size());
    std::vector<int> indegree(executable_passes.size(), 0);
    std::unordered_map<const manifest::RenderPass*, bool> history_usage;

    for (std::size_t i = 0; i < executable_passes.size(); ++i) {
        const manifest::RenderPass* pass = executable_passes[i];
        history_usage[pass] = false;

        for (const auto& input : pass->inputs) {
            if (input.type != manifest::PassInputType::kBuffer || input.id.empty()) {
                continue;
            }

            auto src_it = buffer_id_to_pass.find(input.id);
            if (src_it == buffer_id_to_pass.end()) {
                SDL_Log(
                    "PassGraph: unresolved buffer input '%s' for pass %s.",
                    input.id.c_str(),
                    pass->name.c_str());
                return false;
            }

            const manifest::RenderPass* dependency = src_it->second;
            if (dependency == pass) {
                history_usage[pass] = true;
                continue;
            }

            auto dep_index_it = index_lookup.find(dependency);
            if (dep_index_it == index_lookup.end()) {
                SDL_Log(
                    "PassGraph: missing source pass for dependency '%s' -> %s.",
                    input.id.c_str(),
                    pass->name.c_str());
                return false;
            }

            adjacency[dep_index_it->second].push_back(i);
            indegree[i] += 1;
        }
    }

    std::queue<std::size_t> ready;
    for (std::size_t i = 0; i < indegree.size(); ++i) {
        if (indegree[i] == 0) {
            ready.push(i);
        }
    }

    std::vector<const manifest::RenderPass*> ordered_passes;
    ordered_passes.reserve(executable_passes.size());
    while (!ready.empty()) {
        std::size_t idx = ready.front();
        ready.pop();
        ordered_passes.push_back(executable_passes[idx]);

        for (std::size_t neighbor : adjacency[idx]) {
            indegree[neighbor] -= 1;
            if (indegree[neighbor] == 0) {
                ready.push(neighbor);
            }
        }
    }

    if (ordered_passes.size() != executable_passes.size()) {
        SDL_Log("PassGraph: cycle detected in render pass graph.");
        return false;
    }

    out_plan.ordered_passes = std::move(ordered_passes);
    out_plan.uses_history = std::move(history_usage);
    out_plan.buffer_ids = std::move(pass_to_buffer_id);
    out_plan.buffer_sources = std::move(buffer_id_to_pass);
    return true;
}

} // namespace shaderdock::render
