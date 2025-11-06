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