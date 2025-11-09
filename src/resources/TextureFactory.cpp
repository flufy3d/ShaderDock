#include "resources/TextureFactory.hpp"

#include <SDL.h>

#include <array>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

#include <glad/glad.h>

#include "resources/TextureLoader.hpp"
#include "third_party/stb/stb_image.h"

namespace shaderdock::resources::detail {

namespace {

struct LoadedImage {
    using BufferPtr = std::unique_ptr<void, void (*)(void*)>;

    LoadedImage()
        : pixels(nullptr, stbi_image_free)
    {
    }

    LoadedImage(
        void* data,
        int w,
        int h,
        int c,
        GLenum fmt,
        GLenum type)
        : pixels(data, stbi_image_free)
        , width(w)
        , height(h)
        , channels(c)
        , format(fmt)
        , data_type(type)
    {
    }

    LoadedImage(LoadedImage&&) noexcept = default;
    LoadedImage& operator=(LoadedImage&&) noexcept = default;

    LoadedImage(const LoadedImage&) = delete;
    LoadedImage& operator=(const LoadedImage&) = delete;

    BufferPtr pixels{nullptr, stbi_image_free};
    int width = 0;
    int height = 0;
    int channels = 0;
    GLenum format = GL_RGBA;
    GLenum data_type = GL_UNSIGNED_BYTE;
};

GLenum ChannelsToFormat(int channels)
{
    switch (channels) {
        case 1:
            return GL_RED;
        case 2:
            return GL_RG;
        case 3:
            return GL_RGB;
        case 4:
        default:
            return GL_RGBA;
    }
}

GLint ChooseInternalFormat(int channels, const manifest::SamplerDesc& sampler)
{
    const bool srgb_capable = sampler.srgb &&
        sampler.internal == manifest::SamplerInternalFormat::kByte &&
        (channels == 3 || channels == 4);

    if (srgb_capable) {
        return (channels == 4) ? GL_SRGB8_ALPHA8 : GL_SRGB8;
    }

    switch (sampler.internal) {
        case manifest::SamplerInternalFormat::kByte:
            switch (channels) {
                case 1:
                    return GL_R8;
                case 2:
                    return GL_RG8;
                case 3:
                    return GL_RGB8;
                case 4:
                default:
                    return GL_RGBA8;
            }
        case manifest::SamplerInternalFormat::kHalf:
            switch (channels) {
                case 1:
                    return GL_R16F;
                case 2:
                    return GL_RG16F;
                case 3:
                    return GL_RGB16F;
                case 4:
                default:
                    return GL_RGBA16F;
            }
        case manifest::SamplerInternalFormat::kFloat:
            switch (channels) {
                case 1:
                    return GL_R32F;
                case 2:
                    return GL_RG32F;
                case 3:
                    return GL_RGB32F;
                case 4:
                default:
                    return GL_RGBA32F;
            }
        default:
            break;
    }

    return 0;
}

bool ShouldGenerateMipmaps(const manifest::SamplerDesc& sampler)
{
    return sampler.filter == manifest::SamplerFilter::kMipmap;
}

void ApplySamplerState(GLenum target, const manifest::SamplerDesc& sampler)
{
    GLint min_filter = GL_NEAREST;
    GLint mag_filter = GL_NEAREST;

    switch (sampler.filter) {
        case manifest::SamplerFilter::kLinear:
            min_filter = GL_LINEAR;
            mag_filter = GL_LINEAR;
            break;
        case manifest::SamplerFilter::kMipmap:
            min_filter = GL_LINEAR_MIPMAP_LINEAR;
            mag_filter = GL_LINEAR;
            break;
        case manifest::SamplerFilter::kNearest:
        default:
            break;
    }

    const GLint wrap = sampler.wrap == manifest::SamplerWrap::kRepeat ? GL_REPEAT : GL_CLAMP_TO_EDGE;

    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, min_filter);
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, mag_filter);
    glTexParameteri(target, GL_TEXTURE_WRAP_S, wrap);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, wrap);
    if (target == GL_TEXTURE_CUBE_MAP) {
        glTexParameteri(target, GL_TEXTURE_WRAP_R, wrap);
    }
}

std::optional<LoadedImage> LoadImageFromDisk(
    const std::filesystem::path& path,
    const manifest::SamplerDesc& sampler)
{
    if (path.empty()) {
        return std::nullopt;
    }

    const std::string path_string = path.string();
    stbi_set_flip_vertically_on_load_thread(sampler.vertical_flip ? 1 : 0);

    const bool wants_float = sampler.internal != manifest::SamplerInternalFormat::kByte;
    const bool hdr_source = stbi_is_hdr(path_string.c_str()) == 1;
    const bool load_as_float = wants_float || hdr_source;

    int width = 0;
    int height = 0;
    int channels = 0;
    void* pixels = nullptr;

    if (load_as_float) {
        pixels = stbi_loadf(path_string.c_str(), &width, &height, &channels, 0);
    } else {
        pixels = stbi_load(path_string.c_str(), &width, &height, &channels, 0);
    }

    if (pixels == nullptr) {
        SDL_Log("Failed to load texture %s: %s", path_string.c_str(), stbi_failure_reason());
        return std::nullopt;
    }

    if (channels <= 0) {
        SDL_Log("Texture %s reported invalid channel count %d.", path_string.c_str(), channels);
        stbi_image_free(pixels);
        return std::nullopt;
    }

    LoadedImage image(
        pixels,
        width,
        height,
        channels,
        ChannelsToFormat(channels),
        load_as_float ? GL_FLOAT : GL_UNSIGNED_BYTE);
    return image;
}

std::filesystem::path CubemapFacePath(const std::filesystem::path& base_path, int face_index)
{
    if (face_index == 0) {
        return base_path;
    }

    const std::filesystem::path directory = base_path.parent_path();
    const std::string stem = base_path.stem().string();
    const std::string extension = base_path.extension().string();
    std::string filename = stem;
    filename += "_";
    filename += std::to_string(face_index);
    filename += extension;

    return directory / filename;
}

} // namespace

std::shared_ptr<TextureHandle> CreateTexture2D(
    const std::filesystem::path& path,
    const manifest::SamplerDesc& sampler)
{
    auto image = LoadImageFromDisk(path, sampler);
    if (!image) {
        return nullptr;
    }

    const GLint internal_format = ChooseInternalFormat(image->channels, sampler);
    if (internal_format == 0) {
        SDL_Log("Unsupported channel/internal format combination for %s.", path.string().c_str());
        return nullptr;
    }

    GLuint texture_id = 0;
    glGenTextures(1, &texture_id);
    if (texture_id == 0) {
        SDL_Log("glGenTextures failed for %s.", path.string().c_str());
        return nullptr;
    }

    glBindTexture(GL_TEXTURE_2D, texture_id);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        internal_format,
        image->width,
        image->height,
        0,
        image->format,
        image->data_type,
        image->pixels.get());

    if (ShouldGenerateMipmaps(sampler)) {
        glGenerateMipmap(GL_TEXTURE_2D);
    }

    ApplySamplerState(GL_TEXTURE_2D, sampler);
    glBindTexture(GL_TEXTURE_2D, 0);

    SDL_Log(
        "Texture2D loaded: %s (%dx%d, channels=%d)",
        path.string().c_str(),
        image->width,
        image->height,
        image->channels);

    return std::make_shared<TextureHandle>(
        texture_id,
        GL_TEXTURE_2D,
        image->width,
        image->height,
        ShouldGenerateMipmaps(sampler));
}

std::shared_ptr<TextureHandle> CreateCubemap(
    const std::filesystem::path& base_path,
    const manifest::SamplerDesc& sampler)
{
    std::array<LoadedImage, 6> faces{};
    for (int face = 0; face < 6; ++face) {
        const std::filesystem::path face_path = CubemapFacePath(base_path, face);
        auto image = LoadImageFromDisk(face_path, sampler);
        if (!image) {
            SDL_Log("Failed to load cubemap face %d at %s.", face, face_path.string().c_str());
            return nullptr;
        }

        if (face > 0) {
            if (image->width != faces[0].width || image->height != faces[0].height || image->channels != faces[0].channels) {
                SDL_Log("Cubemap face dimension mismatch at %s.", face_path.string().c_str());
                return nullptr;
            }
        }

        faces[face] = std::move(*image);
    }

    const GLint internal_format = ChooseInternalFormat(faces[0].channels, sampler);
    if (internal_format == 0) {
        SDL_Log("Unsupported cubemap format: %s", base_path.string().c_str());
        return nullptr;
    }

    GLuint texture_id = 0;
    glGenTextures(1, &texture_id);
    if (texture_id == 0) {
        SDL_Log("glGenTextures failed for cubemap %s.", base_path.string().c_str());
        return nullptr;
    }

    glBindTexture(GL_TEXTURE_CUBE_MAP, texture_id);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    for (int face = 0; face < 6; ++face) {
        const GLenum target = GL_TEXTURE_CUBE_MAP_POSITIVE_X + face;
        glTexImage2D(
            target,
            0,
            internal_format,
            faces[face].width,
            faces[face].height,
            0,
            faces[face].format,
            faces[face].data_type,
            faces[face].pixels.get());
    }

    if (ShouldGenerateMipmaps(sampler)) {
        glGenerateMipmap(GL_TEXTURE_CUBE_MAP);
    }

    ApplySamplerState(GL_TEXTURE_CUBE_MAP, sampler);
    glBindTexture(GL_TEXTURE_CUBE_MAP, 0);

    SDL_Log(
        "Cubemap loaded: %s (%dx%d)",
        base_path.string().c_str(),
        faces[0].width,
        faces[0].height);

    return std::make_shared<TextureHandle>(
        texture_id,
        GL_TEXTURE_CUBE_MAP,
        faces[0].width,
        faces[0].height,
        ShouldGenerateMipmaps(sampler));
}

} // namespace shaderdock::resources::detail
