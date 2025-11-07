#pragma once

#include <string>

namespace shaderdock::resources {

std::string ReadTextFile(const std::string& path);
std::string LoadAssetText(const std::string& relative_path);

} // namespace shaderdock::resources
