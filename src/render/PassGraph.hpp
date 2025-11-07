#pragma once

#include <string>
#include <unordered_map>
#include <vector>

#include "resources/DemoManifest.hpp"

namespace shaderdock::render {

struct PassExecutionPlan {
    std::vector<const resources::RenderPass*> ordered_passes;
    std::unordered_map<const resources::RenderPass*, bool> uses_history;
    std::unordered_map<const resources::RenderPass*, std::string> buffer_ids;
    std::unordered_map<std::string, const resources::RenderPass*> buffer_sources;
};

bool BuildPassExecutionPlan(
    const resources::DemoManifest& manifest,
    PassExecutionPlan& out_plan);

} // namespace shaderdock::render
