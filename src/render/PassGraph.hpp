#pragma once

#include <string>
#include <unordered_map>
#include <vector>

#include "manifest/ManifestTypes.hpp"

namespace shaderdock::render {

struct PassExecutionPlan {
    std::vector<const manifest::RenderPass*> ordered_passes;
    std::unordered_map<const manifest::RenderPass*, bool> uses_history;
    std::unordered_map<const manifest::RenderPass*, std::string> buffer_ids;
    std::unordered_map<std::string, const manifest::RenderPass*> buffer_sources;
};

bool BuildPassExecutionPlan(
    const manifest::DemoManifest& manifest,
    PassExecutionPlan& out_plan);

} // namespace shaderdock::render
