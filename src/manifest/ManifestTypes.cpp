#include "manifest/ManifestTypes.hpp"

namespace shaderdock::manifest {

std::string_view ToString(RenderPassType type)
{
    switch (type) {
        case RenderPassType::kImage:
            return "image";
        case RenderPassType::kBuffer:
            return "buffer";
        case RenderPassType::kCommon:
            return "common";
        default:
            return "unknown";
    }
}

std::string_view ToString(PassInputType type)
{
    switch (type) {
        case PassInputType::kTexture:
            return "texture";
        case PassInputType::kCubemap:
            return "cubemap";
        case PassInputType::kBuffer:
            return "buffer";
        case PassInputType::kKeyboard:
            return "keyboard";
        default:
            return "unknown";
    }
}

} // namespace shaderdock::manifest
