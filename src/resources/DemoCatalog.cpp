#include "resources/DemoCatalog.hpp"

#include <SDL.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

#include <json/json.h>

#include "resources/AssetIO.hpp"

namespace shaderdock::resources {

namespace {

std::string ToLower(std::string_view value)
{
    std::string lowered(value);
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return lowered;
}

bool IsDigitsOnly(std::string_view value)
{
    return !value.empty() && std::all_of(value.begin(), value.end(), [](unsigned char c) {
               return std::isdigit(c) != 0;
           });
}

std::string DisplayLabel(const DemoEntry& entry)
{
    if (!entry.display_name.empty()) {
        return entry.display_name;
    }
    return entry.folder_name;
}

std::string ReadManifestDisplayName(const std::filesystem::path& manifest_path)
{
    std::error_code ec;
    if (!std::filesystem::exists(manifest_path, ec) || ec) {
        return {};
    }

    std::string raw = ReadTextFile(manifest_path.string());
    if (raw.empty()) {
        return {};
    }

    Json::CharReaderBuilder builder;
    builder["collectComments"] = false;

    Json::Value root;
    std::string errs;
    const std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
    if (!reader->parse(raw.data(), raw.data() + raw.size(), &root, &errs)) {
        return {};
    }

    if (!root.isObject()) {
        return {};
    }

    const Json::Value& info = root["info"];
    if (!info.isObject()) {
        return {};
    }

    return info.get("name", "").asString();
}

} // namespace

std::vector<DemoEntry> EnumerateAvailableDemos()
{
    std::vector<DemoEntry> demos;
    const std::filesystem::path demos_root = ResolveAssetPath("assets/demos");
    if (demos_root.empty()) {
        SDL_Log("DemoCatalog: unable to locate assets/demos directory.");
        return demos;
    }

    std::error_code ec;
    if (!std::filesystem::exists(demos_root, ec) || ec) {
        SDL_Log("DemoCatalog: demos root missing at %s", demos_root.string().c_str());
        return demos;
    }

    for (const auto& entry : std::filesystem::directory_iterator(demos_root)) {
        if (!entry.is_directory()) {
            continue;
        }

        const std::filesystem::path manifest = entry.path() / "demo.json";
        if (!std::filesystem::exists(manifest, ec) || ec) {
            continue;
        }

        DemoEntry demo;
        demo.folder_name = entry.path().filename().string();
        demo.manifest_path = manifest;

        demo.display_name = ReadManifestDisplayName(manifest);

        demos.emplace_back(std::move(demo));
    }

    std::sort(demos.begin(), demos.end(), [](const DemoEntry& a, const DemoEntry& b) {
        const std::string label_a = DisplayLabel(a);
        const std::string label_b = DisplayLabel(b);
        if (label_a == label_b) {
            return a.folder_name < b.folder_name;
        }
        return label_a < label_b;
    });

    return demos;
}

std::optional<DemoEntry> FindDemoByToken(const std::vector<DemoEntry>& demos, const std::string& token)
{
    if (demos.empty() || token.empty()) {
        return std::nullopt;
    }

    if (IsDigitsOnly(token)) {
        try {
            const std::size_t index = static_cast<std::size_t>(std::stoul(token));
            if (index >= 1 && index <= demos.size()) {
                return demos[index - 1];
            }
        } catch (...) {
        }
    }

    const std::string lowered = ToLower(token);
    for (const auto& demo : demos) {
        const std::string folder_lower = ToLower(demo.folder_name);
        const std::string label_lower = ToLower(DisplayLabel(demo));
        if (folder_lower == lowered || label_lower == lowered) {
            return demo;
        }
    }

    return std::nullopt;
}

} // namespace shaderdock::resources
