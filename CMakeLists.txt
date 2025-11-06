cmake_minimum_required(VERSION 3.10)
project(ShaderDock C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED sdl2)

add_executable(ShaderDock src/main.c)
target_include_directories(ShaderDock PRIVATE ${SDL2_INCLUDE_DIRS})
target_link_libraries(ShaderDock ${SDL2_LIBRARIES})
target_compile_options(ShaderDock PRIVATE ${SDL2_CFLAGS_OTHER})
if(SDL2_LDFLAGS_OTHER)
    target_link_options(ShaderDock PRIVATE ${SDL2_LDFLAGS_OTHER})
endif()

find_library(GLESv2_LIB NAMES GLESv2 libGLESv2)
if(GLESv2_LIB)
    target_link_libraries(ShaderDock ${GLESv2_LIB})
else()
    message(WARNING "OpenGL ES 2/3 library not found; install libGLESv2 to link against OpenGL ES.")
endif()

install(TARGETS ShaderDock RUNTIME DESTINATION bin)
