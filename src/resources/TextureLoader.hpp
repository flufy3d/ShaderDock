#pragma once

#include <cstddef>
#include <filesystem>
#include <memory>
#include <string>
#include <unordered_map>

#include <glad/glad.h>

#include "resources/DemoManifest.hpp"

namespace shaderdock::resources {

class TextureHandle
{
public:
    TextureHandle() = default;
    TextureHandle(GLuint id, GLenum target, int width, int height, bool mipmapped);
    ~TextureHandle();

    TextureHandle(const TextureHandle&) = delete;
    TextureHandle& operator=(const TextureHandle&) = delete;

    TextureHandle(TextureHandle&& other) noexcept;
    TextureHandle& operator=(TextureHandle&& other) noexcept;

    GLuint id() const { return id_; }
    GLenum target() const { return target_; }
    int width() const { return width_; }
    int height() const { return height_; }
    bool has_mipmaps() const { return mipmapped_; }

private:
    void reset();

    GLuint id_ = 0;
    GLenum target_ = GL_TEXTURE_2D;
    int width_ = 0;
    int height_ = 0;
    bool mipmapped_ = false;
};

class TextureCache
{
public:
    std::shared_ptr<TextureHandle> load_texture_2d(
        const std::filesystem::path& path,
        const SamplerDesc& sampler);

    std::shared_ptr<TextureHandle> load_cubemap(
        const std::filesystem::path& base_path,
        const SamplerDesc& sampler);

    void clear();
    [[nodiscard]] std::size_t resident_texture_count() const;

private:
    std::shared_ptr<TextureHandle> load_or_create(
        const std::filesystem::path& path,
        const SamplerDesc& sampler,
        PassInputType type);

    static std::string BuildCacheKey(
        const std::filesystem::path& path,
        const SamplerDesc& sampler,
        PassInputType type);

    std::unordered_map<std::string, std::weak_ptr<TextureHandle>> cache_;
};

} // namespace shaderdock::resources
