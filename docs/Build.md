# ShaderDock 构建指南

## 1. 必备依赖
- CMake ≥ 3.16（建议 ≥ 3.22）
- Ninja（或 GNU Make，本文以 Ninja 为例）
- C/C++ 编译器（GCC、Clang 或 MSVC，需支持 C++20）
- pkg-config
- libsdl2 ≥ 2.0（测试于 2.32.10）
- libjsoncpp ≥ 1.9.5
- libGLESv2（OpenGL ES 2/3 实现；Windows 下由 ANGLE 提供，Linux 下通常随驱动或 Mesa 安装）

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

### 2.5 配置 PATH
为了在任意终端中使用 UCRT64 工具链 和 动态库，可将 `C:\msys64\ucrt64\bin` 添加到系统 `PATH`。


### 2.6 构建与运行
```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```
### 2.7 可选： wsl里运行

```
# 从msys2 shell里启动

cmd.exe /c "C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c 'cmake --build build'"

# 或者直接创建别名更方便 下面内容添加到 ~/.bashrc
msys_exec() {
    local cmd_string="$*"
    cmd.exe /c "C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c '$cmd_string'"
}

msys_exec 'cmake --build build'

```

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
./build/ShaderDock
```

---

## 4. 运行与 CLI 用法

构建成功后，可执行文件为 `build/ShaderDock`（Linux）或 `build/ShaderDock.exe`（Windows）。

```sh
# 列出所有可用 demo（含编号和文件夹名）
ShaderDock --list-demos

# 按文件夹名或显示名加载指定 demo
ShaderDock --demo Chinese_Go
ShaderDock --demo "Happy Moomin v2"

# 按编号加载（编号来自 --list-demos 输出）
ShaderDock --demo 2

# 查看帮助
ShaderDock --help
```

不带任何参数启动时，将加载 `config.json` 中记录的上次使用的 demo；若配置不存在则加载第一个可用 demo。

---

## 5. 常见问题
- **SDL2/JsonCPP 版本不满足要求**：使用 `pkg-config --variable=prefix <lib>` 查看安装路径，从源码或官方发布包安装指定版本，再更新 `PKG_CONFIG_PATH` 指向新的 `.pc` 文件。
- **链接阶段找不到库**：确认 `pkg-config` 输出包含 `-L` 与 `-l` 相关参数，可在 CMake 命令中追加 `-DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=ON`，或在环境里设置 `CMAKE_PREFIX_PATH`。
- **运行缺少 SDL2.dll（Windows）**：确保 `SDL2.dll` 与 exe 放在同一目录，或将 UCRT64 的 `bin` 目录加入 `PATH`。
- **双显卡笔记本启动闪退（Windows）**：系统会默认分配省电的核心显卡（如 Intel 核显）运行程序，但部分核显驱动对 OpenGL ES 3.2 标准支持不佳，会导致初始化失败并静默退出。请在系统设置的“显示 -> 图形”中，或在显卡控制面板里，手动将 `ShaderDock.exe` 添加并设为“高性能”模式，强制使用独立显卡加载。
