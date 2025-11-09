#include "resources/TextureLoader.hpp"

#include <SDL.h>

#include <filesystem>
#include <memory>
#include <sstream>
#include <string>
#include <utility>

#include "resources/TextureFactory.hpp"

namespace shaderdock::resources {

TextureHandle::TextureHandle(GLuint id, GLenum target, int width, int height, bool mipmapped)
    : id_(id)
    , target_(target)
    , width_(width)
    , height_(height)
    , mipmapped_(mipmapped)
{
}

TextureHandle::~TextureHandle()
{
    reset();
}

TextureHandle::TextureHandle(TextureHandle&& other) noexcept
{
    *this = std::move(other);
}

TextureHandle& TextureHandle::operator=(TextureHandle&& other) noexcept
{
    if (this == &other) {
        return *this;
    }

    reset();
    id_ = other.id_;
    target_ = other.target_;
    width_ = other.width_;
    height_ = other.height_;
    mipmapped_ = other.mipmapped_;

    other.id_ = 0;
    other.width_ = 0;
    other.height_ = 0;
    other.mipmapped_ = false;
    return *this;
}

void TextureHandle::reset()
{
    if (id_ != 0) {
        glDeleteTextures(1, &id_);
        id_ = 0;
    }
    target_ = GL_TEXTURE_2D;
    width_ = 0;
    height_ = 0;
    mipmapped_ = false;
}

std::shared_ptr<TextureHandle> TextureCache::load_texture_2d(
    const std::filesystem::path& path,
    const SamplerDesc& sampler)
{
    return load_or_create(path, sampler, manifest::PassInputType::kTexture);
}

std::shared_ptr<TextureHandle> TextureCache::load_cubemap(
    const std::filesystem::path& base_path,
    const SamplerDesc& sampler)
{
    return load_or_create(base_path, sampler, manifest::PassInputType::kCubemap);
}

void TextureCache::clear()
{
    cache_.clear();
}

std::size_t TextureCache::resident_texture_count() const
{
    std::size_t count = 0;
    for (const auto& entry : cache_) {
        if (!entry.second.expired()) {
            ++count;
        }
    }
    return count;
}

std::shared_ptr<TextureHandle> TextureCache::load_or_create(
    const std::filesystem::path& path,
    const SamplerDesc& sampler,
    manifest::PassInputType type)
{
    const std::string key = BuildCacheKey(path, sampler, type);
    if (auto it = cache_.find(key); it != cache_.end()) {
        if (auto cached = it->second.lock()) {
            return cached;
        }
    }

    std::shared_ptr<TextureHandle> created;
    switch (type) {
        case manifest::PassInputType::kTexture:
            created = detail::CreateTexture2D(path, sampler);
            break;
        case manifest::PassInputType::kCubemap:
            created = detail::CreateCubemap(path, sampler);
            break;
        default:
            SDL_Log("TextureCache: unsupported input type for %s", path.string().c_str());
            return nullptr;
    }

    if (created) {
        cache_[key] = created;
    }
    return created;
}

std::string TextureCache::BuildCacheKey(
    const std::filesystem::path& path,
    const SamplerDesc& sampler,
    manifest::PassInputType type)
{
    std::ostringstream oss;
    oss << static_cast<int>(type) << '|'
        << path.lexically_normal().generic_string() << '|'
        << static_cast<int>(sampler.filter) << '|'
        << static_cast<int>(sampler.wrap) << '|'
        << static_cast<int>(sampler.internal) << '|'
        << sampler.vertical_flip << '|'
        << sampler.srgb;
    return oss.str();
}

} // namespace shaderdock::resources
