#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace shaderdock::manifest {

enum class RenderPassType {
    kUnknown = 0,
    kImage,
    kBuffer,
    kCommon,
};

enum class PassInputType {
    kTexture = 0,
    kCubemap,
    kBuffer,
    kKeyboard,
};

enum class SamplerFilter {
    kNearest = 0,
    kLinear,
    kMipmap,
};

enum class SamplerWrap {
    kClamp = 0,
    kRepeat,
};

enum class SamplerInternalFormat {
    kByte = 0,
    kHalf,
    kFloat,
};

struct SamplerDesc {
    SamplerFilter filter = SamplerFilter::kNearest;
    SamplerWrap wrap = SamplerWrap::kClamp;
    SamplerInternalFormat internal = SamplerInternalFormat::kByte;
    bool vertical_flip = false;
    bool srgb = false;
};

struct PassInput {
    std::string id;
    PassInputType type = PassInputType::kTexture;
    int channel = 0;
    bool published = false;
    std::string filepath; // Value straight from JSON (may be empty).
    std::optional<std::filesystem::path> resolved_path;
    SamplerDesc sampler;
};

struct PassOutput {
    std::string id;
    int channel = 0;
};

struct RenderPass {
    std::string name;
    RenderPassType type = RenderPassType::kUnknown;
    std::string source_file;
    std::filesystem::path source_path;
    std::vector<PassInput> inputs;
    std::vector<PassOutput> outputs;
};

struct DemoInfo {
    std::string id;
    std::string name;
    std::string username;
    std::string description;
    std::vector<std::string> tags;
    int likes = 0;
    int published = 0;
};

struct DemoManifest {
    std::filesystem::path manifest_path;
    std::filesystem::path demo_directory;
    std::filesystem::path assets_root;
    std::string version;
    DemoInfo info;
    std::vector<RenderPass> passes;
};

std::string_view ToString(RenderPassType type);
std::string_view ToString(PassInputType type);

} // namespace shaderdock::manifest
