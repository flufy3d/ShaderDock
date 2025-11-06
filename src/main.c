#include <SDL.h>
#include <stdio.h>
#include <signal.h>

static volatile int running = 1;

void handle_sigint(int sig)
{
    (void)sig;
    running = 0;
    SDL_Log("Caught Ctrl+C, exiting...");
}

int main(int argc, char *argv[])
{
    (void)argc;
    (void)argv;

    signal(SIGINT, handle_sigint);

    SDL_Log("simple-sdl2 start!!!");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return 1;
    }



    SDL_Window *window = SDL_CreateWindow(
        "simple-sdl2",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        720,
        480,
        SDL_WINDOW_SHOWN);
    if (!window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_SetWindowResizable(window, SDL_FALSE);

    SDL_Renderer *renderer = SDL_CreateRenderer(
        window,
        -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        SDL_Log("SDL_CreateRenderer failed: %s", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    SDL_Log("VideoDriver = %s", SDL_GetCurrentVideoDriver());
    SDL_RendererInfo info;
    SDL_GetRendererInfo(renderer, &info);
    SDL_Log("Renderer = %s", info.name);

    SDL_SetRenderDrawColor(renderer, 250, 25, 112, 255);
    SDL_RenderClear(renderer);
    SDL_RenderPresent(renderer);

    SDL_Event event;
    while (running) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT ||
                event.type == SDL_KEYDOWN ||
                event.type == SDL_MOUSEBUTTONDOWN) {
                running = 0;
                break;
            }
        }
        SDL_Delay(16);
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
