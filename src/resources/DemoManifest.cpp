#include "resources/DemoManifest.hpp"

#include <SDL.h>
#include <json/json.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <memory>
#include <optional>
#include <sstream>
#include <string_view>
#include <system_error>
#include <utility>

#include "resources/AssetIO.hpp"

namespace shaderdock::resources {

namespace {

std::string ToLowerCopy(std::string_view value)
{
    std::string lowered(value);
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return lowered;
}

bool ParseBoolValue(const Json::Value& value, bool default_value = false)
{
    if (value.isBool()) {
        return value.asBool();
    }
    if (value.isInt()) {
        return value.asInt() != 0;
    }
    if (value.isString()) {
        const std::string lowered = ToLowerCopy(value.asString());
        return lowered == "true" || lowered == "1";
    }
    return default_value;
}

RenderPassType ParseRenderPassType(const std::string& value)
{
    const std::string lowered = ToLowerCopy(value);
    if (lowered == "image") {
        return RenderPassType::kImage;
    }
    if (lowered == "buffer") {
        return RenderPassType::kBuffer;
    }
    if (lowered == "common") {
        return RenderPassType::kCommon;
    }
    return RenderPassType::kUnknown;
}

PassInputType ParsePassInputType(const std::string& value)
{
    const std::string lowered = ToLowerCopy(value);
    if (lowered == "texture") {
        return PassInputType::kTexture;
    }
    if (lowered == "cubemap") {
        return PassInputType::kCubemap;
    }
    if (lowered == "buffer") {
        return PassInputType::kBuffer;
    }
    return PassInputType::kTexture;
}

SamplerFilter ParseSamplerFilter(const Json::Value& value)
{
    if (!value.isString()) {
        return SamplerFilter::kNearest;
    }
    const std::string lowered = ToLowerCopy(value.asString());
    if (lowered == "linear") {
        return SamplerFilter::kLinear;
    }
    if (lowered == "mipmap") {
        return SamplerFilter::kMipmap;
    }
    return SamplerFilter::kNearest;
}

SamplerWrap ParseSamplerWrap(const Json::Value& value)
{
    if (!value.isString()) {
        return SamplerWrap::kClamp;
    }
    const std::string lowered = ToLowerCopy(value.asString());
    if (lowered == "repeat") {
        return SamplerWrap::kRepeat;
    }
    return SamplerWrap::kClamp;
}

SamplerInternalFormat ParseSamplerInternal(const Json::Value& value)
{
    if (!value.isString()) {
        return SamplerInternalFormat::kByte;
    }
    const std::string lowered = ToLowerCopy(value.asString());
    if (lowered == "half") {
        return SamplerInternalFormat::kHalf;
    }
    if (lowered == "float") {
        return SamplerInternalFormat::kFloat;
    }
    return SamplerInternalFormat::kByte;
}

SamplerDesc ParseSamplerDesc(const Json::Value& sampler_json)
{
    SamplerDesc sampler;
    if (!sampler_json.isObject()) {
        return sampler;
    }

    sampler.filter = ParseSamplerFilter(sampler_json["filter"]);
    sampler.wrap = ParseSamplerWrap(sampler_json["wrap"]);
    sampler.vertical_flip = ParseBoolValue(sampler_json["vflip"]);
    sampler.srgb = ParseBoolValue(sampler_json["srgb"]);
    sampler.internal = ParseSamplerInternal(sampler_json["internal"]);
    return sampler;
}

std::filesystem::path DetermineAssetsRoot(const std::filesystem::path& demo_directory)
{
    const std::filesystem::path demos_dir = demo_directory.parent_path();
    const std::filesystem::path maybe_assets = demos_dir.parent_path();

    if (!maybe_assets.empty() && maybe_assets.filename() == "assets") {
        return maybe_assets;
    }
    if (!demos_dir.empty() && demos_dir.filename() == "assets") {
        return demos_dir;
    }
    if (!demo_directory.empty()) {
        return demo_directory.parent_path();
    }
    return {};
}

bool EnsureFileExists(const std::filesystem::path& path)
{
    if (path.empty()) {
        return false;
    }
    std::error_code ec;
    const bool exists = std::filesystem::exists(path, ec);
    if (!exists || ec) {
        SDL_Log("Manifest references missing file: %s", path.string().c_str());
        return false;
    }
    return true;
}

std::optional<std::filesystem::path> ResolveInputPath(
    const DemoManifest& manifest,
    const std::string& filepath)
{
    if (filepath.empty()) {
        return std::nullopt;
    }

    std::filesystem::path resolved;
    if (!filepath.empty() && filepath.front() == '/') {
        resolved = manifest.assets_root / filepath.substr(1);
    } else {
        resolved = manifest.demo_directory / filepath;
    }

    resolved = resolved.lexically_normal();
    if (!EnsureFileExists(resolved)) {
        return std::nullopt;
    }
    return resolved;
}

DemoInfo ParseDemoInfo(const Json::Value& info_json)
{
    DemoInfo info;
    if (!info_json.isObject()) {
        return info;
    }

    info.id = info_json.get("id", "").asString();
    info.name = info_json.get("name", "").asString();
    info.username = info_json.get("username", "").asString();
    info.description = info_json.get("description", "").asString();
    info.likes = info_json.get("likes", 0).asInt();
    info.published = info_json.get("published", 0).asInt();

    const Json::Value& tags = info_json["tags"];
    if (tags.isArray()) {
        info.tags.reserve(tags.size());
        for (const Json::Value& tag : tags) {
            if (tag.isString()) {
                info.tags.emplace_back(tag.asString());
            }
        }
    }

    return info;
}

} // namespace

std::optional<DemoManifest> LoadDemoManifest(const std::filesystem::path& manifest_path)
{
    std::filesystem::path resolved = manifest_path;
    std::error_code ec;
    if (resolved.empty() || !std::filesystem::exists(resolved, ec)) {
        resolved = ResolveAssetPath(manifest_path.string());
    }

    if (resolved.empty()) {
        SDL_Log("Demo manifest not found: %s", manifest_path.string().c_str());
        return std::nullopt;
    }

    std::string raw = ReadTextFile(resolved.string());
    if (raw.empty()) {
        SDL_Log("Failed to read manifest: %s", resolved.string().c_str());
        return std::nullopt;
    }

    Json::CharReaderBuilder builder;
    builder["collectComments"] = false;

    Json::Value root;
    std::string errs;
    const std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    if (!reader->parse(raw.data(), raw.data() + raw.size(), &root, &errs)) {
        SDL_Log("Failed to parse manifest JSON: %s (%s)", resolved.string().c_str(), errs.c_str());
        return std::nullopt;
    }

    if (!root.isObject()) {
        SDL_Log("Manifest root is not an object: %s", resolved.string().c_str());
        return std::nullopt;
    }

    DemoManifest manifest;
    manifest.manifest_path = resolved;
    manifest.demo_directory = resolved.parent_path();
    manifest.assets_root = DetermineAssetsRoot(manifest.demo_directory);
    manifest.version = root.get("ver", "").asString();
    manifest.info = ParseDemoInfo(root["info"]);

    const Json::Value& renderpasses = root["renderpass"];
    if (!renderpasses.isArray()) {
        SDL_Log("Manifest missing renderpass array: %s", resolved.string().c_str());
        return std::nullopt;
    }

    for (const Json::Value& pass_json : renderpasses) {
        if (!pass_json.isObject()) {
            continue;
        }

        RenderPass pass;
        pass.name = pass_json.get("name", "").asString();
        pass.type = ParseRenderPassType(pass_json.get("type", "").asString());
        pass.source_file = pass_json.get("source", "").asString();
        pass.source_path = manifest.demo_directory / pass.source_file;

        if (!pass.source_file.empty() && !EnsureFileExists(pass.source_path)) {
            SDL_Log("Render pass source missing (%s): %s", pass.name.c_str(), pass.source_path.string().c_str());
            return std::nullopt;
        }

        const Json::Value& inputs = pass_json["inputs"];
        if (inputs.isArray()) {
            pass.inputs.reserve(inputs.size());
            for (const Json::Value& input_json : inputs) {
                if (!input_json.isObject()) {
                    continue;
                }

                PassInput input;
                input.id = input_json.get("id", "").asString();
                input.type = ParsePassInputType(input_json.get("type", "").asString());
                input.channel = input_json.get("channel", 0).asInt();
                input.published = input_json.get("published", 0).asInt() != 0;
                input.filepath = input_json.get("filepath", "").asString();
                input.sampler = ParseSamplerDesc(input_json["sampler"]);

                if (input.type != PassInputType::kBuffer && !input.filepath.empty()) {
                    input.resolved_path = ResolveInputPath(manifest, input.filepath);
                    if (!input.resolved_path) {
                        SDL_Log("Failed to resolve resource path for input %s (%s).", input.id.c_str(), input.filepath.c_str());
                        return std::nullopt;
                    }
                }

                pass.inputs.emplace_back(std::move(input));
            }
        }

        manifest.passes.emplace_back(std::move(pass));
    }

    SDL_Log(
        "Demo manifest loaded: %s (passes=%zu)",
        manifest.info.name.c_str(),
        manifest.passes.size());
    return manifest;
}

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
        default:
            return "texture";
    }
}

} // namespace shaderdock::resources
