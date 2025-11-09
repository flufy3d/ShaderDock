#include "render/PassGraph.hpp"

#include <SDL.h>

#include <algorithm>
#include <cctype>
#include <queue>
#include <string>
#include <unordered_set>

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

std::string GenerateSyntheticBufferId(
    const manifest::RenderPass& pass,
    const std::unordered_set<std::string>& existing_ids)
{
    std::string base = pass.name.empty() ? "buffer" : pass.name;
    std::string normalized;
    normalized.reserve(base.size());
    for (char c : base) {
        unsigned char uc = static_cast<unsigned char>(c);
        if (std::isalnum(uc)) {
            normalized.push_back(static_cast<char>(std::tolower(uc)));
        } else if (uc == ' ' || uc == '-' || uc == '_') {
            normalized.push_back('_');
        }
    }
    if (normalized.empty()) {
        normalized = "buffer";
    }

    std::string candidate = normalized;
    int suffix = 1;
    while (existing_ids.count(candidate) > 0) {
        candidate = normalized + "_" + std::to_string(suffix++);
    }
    return candidate;
}

} // namespace

bool BuildPassExecutionPlan(const manifest::DemoManifest& manifest, PassExecutionPlan& out_plan)
{
    out_plan = PassExecutionPlan{};

    std::vector<const manifest::RenderPass*> executable_passes;
    std::vector<const manifest::RenderPass*> buffer_passes;
    executable_passes.reserve(manifest.passes.size());

    std::vector<std::string> all_buffer_ids;
    std::unordered_set<std::string> unique_ids;

    for (const auto& pass : manifest.passes) {
        if (IsBufferPass(pass)) {
            buffer_passes.push_back(&pass);
        }
        if (IsExecutablePass(pass)) {
            executable_passes.push_back(&pass);
        }
        for (const auto& input : pass.inputs) {
            if (input.type == manifest::PassInputType::kBuffer && !input.id.empty()) {
                if (unique_ids.insert(input.id).second) {
                    all_buffer_ids.push_back(input.id);
                }
            }
        }
    }

    std::unordered_map<const manifest::RenderPass*, std::string> pass_to_buffer_id;
    std::unordered_map<std::string, const manifest::RenderPass*> buffer_id_to_pass;
    std::unordered_set<std::string> assigned_ids;
    assigned_ids.reserve(buffer_passes.size());

    for (const manifest::RenderPass* pass : buffer_passes) {
        std::string chosen_id;
        for (const auto& input : pass->inputs) {
            if (input.type != manifest::PassInputType::kBuffer || input.id.empty()) {
                continue;
            }
            if (assigned_ids.count(input.id) == 0) {
                chosen_id = input.id;
                break;
            }
        }

        if (chosen_id.empty()) {
            for (const auto& candidate : all_buffer_ids) {
                if (assigned_ids.count(candidate) == 0) {
                    chosen_id = candidate;
                    break;
                }
            }
        }

        if (chosen_id.empty()) {
            chosen_id = GenerateSyntheticBufferId(*pass, assigned_ids);
        }

        assigned_ids.insert(chosen_id);
        pass_to_buffer_id.emplace(pass, chosen_id);
        buffer_id_to_pass.emplace(chosen_id, pass);
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
