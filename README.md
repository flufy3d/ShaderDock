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

## 🏗️ Example Usage

```bash
$ shaderdock project.json
```

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

## ⚠️ Disclaimer

- This tooling is intended for personal/offline experimentation only.  
- ShaderToy assets remain the property of their respective authors—obey their licenses and ShaderToy’s terms of service.  
- You must manually download resources via the provided URLs; the script does not bypass any protections or perform automated scraping.
