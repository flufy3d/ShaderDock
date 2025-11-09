#pragma once

#include <filesystem>
#include <optional>

#include "manifest/ManifestTypes.hpp"

namespace shaderdock::manifest {

class DemoManifestLoader
{
public:
    DemoManifestLoader() = default;

    std::optional<DemoManifest> load(const std::filesystem::path& manifest_path) const;
};

} // namespace shaderdock::manifest
