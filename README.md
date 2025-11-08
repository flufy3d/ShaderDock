# 🧩 ShaderDock

**A Cross-Platform Local ShaderToy Renderer**

ShaderDock is a lightweight, cross-platform shader runtime built with **SDL2** and **OpenGL ES 3.2**,  
designed to locally run and visualize **ShaderToy-style multi-pass fragment shaders**.

It loads shader pipeline definitions from JSON, automatically builds the dependency graph,  
manages **ping-pong feedback buffers**, and executes passes in proper order —  
just like ShaderToy, but fully offline and portable.

---

## ✨ Features

- 🧠 **ShaderToy-compatible pipeline** – Supports Common, Buffer A–D, and Image passes  
- 🔄 **Automatic dependency resolution** – JSON-defined passes sorted via topological graph analysis  
- ♻️ **Ping-pong rendering** – Self-referencing buffers handled with double-FBO swap  
- 🧱 **Modern graphics stack** – Powered by SDL2 + OpenGL ES 3.2  
- ⚡ **Lightweight and fast** – Minimal dependencies, instant startup  
- 💻 **Cross-platform** – Runs on Linux and Windows (planned macOS support)

---

## 🚀 Usage

### Build

Full build prerequisites and configuration steps live in [`Build.md`](Build.md).

### Run

After completing the steps in [`Build.md`](Build.md), launch demos via:

```bash
./build/ShaderDock.exe --list-demos
./build/ShaderDock.exe --demo 2      # or name, e.g. --demo Halloween_Radiosity
```

- `--list-demos` / `--list-demo`: enumerate every manifest under `assets/demos` (with index + folder name).  
- `--demo <token>`: launch by index, folder, or display name; falls back to config default or the first entry.  
- `--help`: print available options.

### Configuration

On first launch ShaderDock writes `config.json` under SDL’s pref path (editable):

| Platform | Location |
| --- | --- |
| Windows | `%APPDATA%\ShaderDock\ShaderDock\config.json` |
| Linux | `~/.local/share/ShaderDock/ShaderDock/config.json` |

Config keys:

| Key | Description | Default |
| --- | --- | --- |
| `width` / `height` | SDL window size (pixels) | 1280 / 720 |
| `fullscreen` | `true` = borderless desktop fullscreen | `false` |
| `resizable` | allow resize by dragging window edges | `false` |
| `vsync` | request vsync via `SDL_GL_SetSwapInterval` | `true` |
| `fps` | target frame rate (0 = uncapped) | `60` |
| `default_demo` | default demo token (index/name/folder) | `""` |

CLI flags override the config; edit and restart to take effect.

---

## 🎯 Preparing Demos from ShaderToy Dumps

1. Download the ShaderToy JSON (the POST `https://www.shadertoy.com/shadertoy` response) and save it locally.  
2. Run the helper to unpack it:
   ```bash
   python3 scripts/parse_shadertoy.py "My Shader.json"
   ```
3. The script creates `assets/demos/<shader_name>/` containing:
   - One GLSL file per render pass (e.g., `image.glsl`, `buffer_a.glsl`, …).
   - `demo.json`, a cleaned manifest ready for ShaderDock.
   - `resource_urls.txt`, grouped `[TEXTURES]` / `[CUBEMAPS]` lists formatted as
     ```text
     [TEXTURES]
     [
       "https://www.shadertoy.com/media/a/xxxx.png",
       "https://www.shadertoy.com/media/a/yyyy.png"
     ].forEach(url => window.open(url));
     ```
     Paste each block into a browser console to open all download tabs at once, then store the files under `assets/textures` or `assets/cubemaps` using the same filenames referenced in `demo.json`.

---

## 🎛 Shader Inputs

ShaderDock injects the full ShaderToy uniform set into every pass:

```glsl
uniform vec3      iResolution;            // viewport resolution (pixels)
uniform float     iTime;                  // playback time (seconds)
uniform float     iTimeDelta;             // render time of last frame (seconds)
uniform float     iFrameRate;             // instantaneous FPS
uniform int       iFrame;                 // frame counter
uniform float     iChannelTime[4];        // per-channel time (seconds)
uniform vec3      iChannelResolution[4];  // per-channel resolution (pixels)
uniform vec4      iMouse;                 // xy=current (if LMB down), zw=click position
uniform sampler2D iChannel0;
uniform sampler2D iChannel1;
uniform sampler2D iChannel2;
uniform sampler2D iChannel3;
uniform vec4      iDate;                  // (year, month, day, seconds)
```

`iChannelX` automatically switches between 2D and cubemap samplers and binds buffers/FBOs or textures based on `demo.json`.

### Supported Channel Types

ShaderDock currently supports the following `demo.json` input types:

- `texture` – Binds a regular 2D texture using the provided sampler settings.
- `cubemap` – Binds a cubemap texture and switches to `samplerCube`.
- `buffer` – Binds the output of another render pass (ping-pong FBO).

### Performance Macros

Every fragment shader also receives `#define HW_PERFORMANCE <0|1>` at the top of its generated source.  
ShaderDock inspects the reported GL vendor/renderer: desktop-class RTX/GTX/Radeon RX/Arc cards get `1` (high), while everything else—including mobile GPUs and most integrated parts—defaults to `0`.  
Use this macro to branch between reduced/expensive paths in ported ShaderToy code (many originals already check it).

---

## ⚠️ Disclaimer

- This tooling is intended for personal/offline experimentation only.  
- ShaderToy assets remain the property of their respective authors—obey their licenses and ShaderToy’s terms of service.  
- You must manually download resources via the provided URLs; the script does not bypass any protections or perform automated scraping.
