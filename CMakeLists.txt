cmake_minimum_required(VERSION 3.10)
project(ShaderDock VERSION 0.1 LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)

add_executable(${PROJECT_NAME}
    src/main.cpp
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
        PkgConfig::SDL2
)

find_library(GLESv2_LIB NAMES GLESv2 libGLESv2)
if(GLESv2_LIB)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${GLESv2_LIB})
else()
    message(WARNING "OpenGL ES 2/3 library not found; install libGLESv2 to link against OpenGL ES.")
endif()

install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION bin)
install(DIRECTORY assets DESTINATION .)
