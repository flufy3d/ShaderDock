# ShaderDock 构建指南

## 1. 必备依赖
- CMake（建议 ≥ 3.22）
- Ninja（或 GNU Make，本文以 Ninja 为例）
- C/C++ 编译器（GCC、Clang 或 MSVC）
- pkg-config
- libsdl2 2.32.10
- libjsoncpp 1.9.5

> 如果发行版软件源/镜像中没有上述精确版本，可先尝试使用默认版本确认能否满足编译需求，再考虑自行编译或下载预编译包。

---

## 2. Windows（MSYS2 UCRT64）

### 2.1 安装 MSYS2
1. 访问 https://www.msys2.org/ 并下载 “Installer MSYS2 x86_64” 安装包（msys2-x86_64-YYYY-MM-DD.exe）。
2. 安装到默认目录 `C:\msys64`（路径不要包含空格）。
3. 安装完成后勾选 “Run MSYS2 now?” 并立即启动。

### 2.2 更新 MSYS2 基础环境
在首次打开的 MSYS2 MSYS 终端中执行：
```sh
pacman -Syu
```
终端提示重启后，重新打开 “MSYS2 MSYS” 终端继续执行：
```sh
pacman -Su
```

### 2.3 切换到 UCRT64 环境并安装依赖
1. 在开始菜单中启动 “MSYS2 MinGW UCRT64” 终端。
2. 安装工具链与库：
```sh
pacman -S --needed \
  mingw-w64-ucrt-x86_64-toolchain \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-SDL2 \
  mingw-w64-ucrt-x86_64-jsoncpp \
  mingw-w64-ucrt-x86_64-angleproject \
  git
```
> MSYS2 滚动更新，`mingw-w64-ucrt-x86_64-SDL2` 通常提供高于 2.32.10 的版本，可通过 `pacman -Qi mingw-w64-ucrt-x86_64-SDL2` 查询；若需精确版本，请改用本地构建或下载官方发布的开发包。

### 2.4 校验环境
```sh
gcc --version
cmake --version
pkg-config --modversion sdl2
pkg-config --modversion jsoncpp
```
若 `pkg-config` 能输出 `sdl2` ≥ 2.32.10、`jsoncpp` ≥ 1.9.5，即表示依赖满足要求。

### 2.5 构建与运行
```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```
编译完成后，可执行文件位于 `build/simple-sdl2.exe`。若运行时报错缺少 `SDL2.dll`，可将 `C:\msys64\ucrt64\bin\SDL2.dll` 拷贝到可执行文件同目录。

### 2.6 可选：配置 PATH
为了在任意终端中使用 UCRT64 工具链，可将 `C:\msys64\ucrt64\bin` 添加到系统 `PATH`。

---

## 3. Linux（以 Debian/Ubuntu 为例）

### 3.1 安装工具与依赖库
```sh
sudo apt update
sudo apt install build-essential cmake ninja-build pkg-config \
                 libsdl2-dev=2.32.10* \
                 libjsoncpp-dev=1.9.5-*
```
- 如果发行版仓库未提供指定版本，可去除版本号部分或使用第三方仓库/源码编译。
- 其它发行版请使用对应的包管理器安装相同依赖。

### 3.2 验证版本
```sh
cmake --version
ninja --version
pkg-config --modversion sdl2
pkg-config --modversion jsoncpp
```

### 3.3 构建与运行
```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/simple-sdl2
```

---

## 4. 常见问题
- **SDL2/JsonCPP 版本不满足要求**：使用 `pkg-config --variable=prefix <lib>` 查看安装路径，从源码或官方发布包安装指定版本，再更新 `PKG_CONFIG_PATH` 指向新的 `.pc` 文件。
- **链接阶段找不到库**：确认 `pkg-config` 输出包含 `-L` 与 `-l` 相关参数，可在 CMake 命令中追加 `-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON`，或在环境里设置 `CMAKE_PREFIX_PATH`。
- **运行缺少 SDL2.dll（Windows）**：确保 `SDL2.dll` 与 exe 放在同一目录，或将 UCRT64 的 `bin` 目录加入 `PATH`。
