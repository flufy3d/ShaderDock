#pragma once

#include <filesystem>
#include <string>

namespace shaderdock::resources {

std::string ReadTextFile(const std::string& path);
std::string LoadAssetText(const std::string& relative_path);
std::filesystem::path ResolveAssetPath(const std::string& relative_path);

} // namespace shaderdock::resources
