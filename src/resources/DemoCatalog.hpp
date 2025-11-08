#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace shaderdock::resources {

struct DemoEntry {
    std::string folder_name;
    std::string display_name;
    std::filesystem::path manifest_path;
};

std::vector<DemoEntry> EnumerateAvailableDemos();
std::optional<DemoEntry> FindDemoByToken(const std::vector<DemoEntry>& demos, const std::string& token);

} // namespace shaderdock::resources
