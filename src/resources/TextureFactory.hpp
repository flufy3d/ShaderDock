#pragma once

#include <filesystem>
#include <memory>

#include "manifest/ManifestTypes.hpp"

namespace shaderdock::resources {

class TextureHandle;

namespace detail {

std::shared_ptr<TextureHandle> CreateTexture2D(
    const std::filesystem::path& path,
    const manifest::SamplerDesc& sampler);

std::shared_ptr<TextureHandle> CreateCubemap(
    const std::filesystem::path& base_path,
    const manifest::SamplerDesc& sampler);

} // namespace detail
} // namespace shaderdock::resources
