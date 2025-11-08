#include "app/ShaderDockApp.hpp"

#include <optional>
#include <string>
#include <vector>

#include <SDL.h>

#include "resources/DemoCatalog.hpp"

namespace {

struct CommandLineOptions {
    bool list_demos = false;
    bool show_help = false;
    bool parse_error = false;
    std::optional<std::string> demo_token;
};

void PrintUsage(const char* executable)
{
    SDL_Log(
        "Usage: %s [--demo <name|index>] [--list-demos] [--help]\n"
        "  --list-demos        List available demos with indices\n"
        "  --demo <token>      Select demo by folder/name or numeric index\n"
        "  --help              Show this message",
        executable);
}

void PrintDemoList()
{
    const auto demos = shaderdock::resources::EnumerateAvailableDemos();
    if (demos.empty()) {
        SDL_Log("No demos found under assets/demos.");
        return;
    }

    SDL_Log("Available demos (%zu):", demos.size());
    for (std::size_t i = 0; i < demos.size(); ++i) {
        const auto& entry = demos[i];
        const std::string label = entry.display_name.empty() ? entry.folder_name : entry.display_name;
        SDL_Log("  %zu. %s [%s]", i + 1, label.c_str(), entry.folder_name.c_str());
    }
}

CommandLineOptions ParseArgs(int argc, char** argv)
{
    CommandLineOptions options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--list-demos" || arg == "--list-demo") {
            options.list_demos = true;
            continue;
        }
        if (arg == "--help" || arg == "-h") {
            options.show_help = true;
            continue;
        }
        if (arg == "--demo") {
            if (i + 1 >= argc) {
                options.parse_error = true;
                break;
            }
            options.demo_token = argv[++i];
            continue;
        }
        if (arg.rfind("--demo=", 0) == 0) {
            options.demo_token = arg.substr(std::string("--demo=").size());
            continue;
        }

        SDL_Log("Unknown argument: %s", arg.c_str());
        options.parse_error = true;
    }
    return options;
}

} // namespace

int main(int argc, char** argv)
{
    const CommandLineOptions options = ParseArgs(argc, argv);
    if (options.parse_error) {
        PrintUsage(argv[0]);
        return 1;
    }
    if (options.show_help) {
        PrintUsage(argv[0]);
        return 0;
    }
    if (options.list_demos) {
        PrintDemoList();
        return 0;
    }

    shaderdock::app::AppOptions app_options;
    app_options.demo_token = options.demo_token;

    shaderdock::app::ShaderDockApp app(app_options);
    if (!app.initialize()) {
        app.shutdown();
        return 1;
    }

    app.run();
    app.shutdown();
    return 0;
}
