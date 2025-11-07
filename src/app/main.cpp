#include "app/ShaderDockApp.hpp"

int main(int argc, char** argv)
{
    static_cast<void>(argc);
    static_cast<void>(argv);

    shaderdock::app::ShaderDockApp app;
    if (!app.initialize()) {
        app.shutdown();
        return 1;
    }

    app.run();
    app.shutdown();
    return 0;
}
