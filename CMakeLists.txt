cmake_minimum_required(VERSION 3.10)
project(simple_sdl2 C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED sdl2)

add_executable(simple-sdl2 src/main.c)
target_include_directories(simple-sdl2 PRIVATE ${SDL2_INCLUDE_DIRS})
target_link_libraries(simple-sdl2 ${SDL2_LIBRARIES})
target_compile_options(simple-sdl2 PRIVATE ${SDL2_CFLAGS_OTHER})
if(SDL2_LDFLAGS_OTHER)
    target_link_options(simple-sdl2 PRIVATE ${SDL2_LDFLAGS_OTHER})
endif()

install(TARGETS simple-sdl2 RUNTIME DESTINATION bin)
