cmake_minimum_required(VERSION 3.16)
project(ShaderDock VERSION 0.1 LANGUAGES C CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
pkg_check_modules(JSONCPP REQUIRED IMPORTED_TARGET jsoncpp)

file(GLOB_RECURSE SHADERDOCK_SOURCES CONFIGURE_DEPENDS
    src/*.cpp
    src/*.c
)

add_executable(${PROJECT_NAME} ${SHADERDOCK_SOURCES})

target_include_directories(${PROJECT_NAME}
    PRIVATE
        src
        src/third_party/glad/include
        src/third_party/stb
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
        PkgConfig::SDL2
        PkgConfig::JSONCPP
)

if(CMAKE_DL_LIBS)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${CMAKE_DL_LIBS})
endif()

find_library(GLESv2_LIB NAMES GLESv2 libGLESv2)
if(GLESv2_LIB)
    target_link_libraries(${PROJECT_NAME} PRIVATE ${GLESv2_LIB})
else()
    message(WARNING "OpenGL ES 2/3 library not found; install libGLESv2 to link against OpenGL ES.")
endif()

install(TARGETS ${PROJECT_NAME} RUNTIME DESTINATION bin)
install(DIRECTORY assets DESTINATION .)
