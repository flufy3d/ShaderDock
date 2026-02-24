# ShaderDock 架构概览

## 目录与模块

- `src/app/`
  - `ShaderDockApp.cpp` 负责应用生命周期（初始化、运行、关闭）。
  - `ShaderDockApp_Startup.cpp` 处理 SDL 窗口/GLES 上下文、Demo manifest 解析与管线搭建。
  - `ShaderDockApp_Render.cpp` 管理视口与帧渲染。
  - `ShaderDockApp_Input.cpp` 只做 SDL 输入事件与 provider 的桥接（鼠标更新 + 将键盘事件分发给 `KeyboardInputProvider`）。
  - `AppConfig.cpp` 独立处理用户配置文件的读取与写入（平台相关的 pref 路径定位及 JSON 解析）。
  - `main.cpp` 解析 CLI 参数（`--demo`、`--list-demos`、`--help`）并驱动 `ShaderDockApp`。
- `src/manifest/`  
  - `ManifestTypes.*` 描述 `DemoManifest`、`RenderPass`、`PassInput` 等不可知 JSON 的领域模型。  
  - `DemoManifestLoader.*` 负责解析 `demo.json`，只返回干净的数据结构。
- `src/bindings/`  
  - `PassInputBinding.*` 定义渲染期绑定接口。  
  - `TextureInputBinding.*`, `CubemapInputBinding.*`, `KeyboardInputBinding.*`, `BufferInputBinding.*` 将对应类型的 GL 绑定逻辑分离到独立 `.cpp`。  
  - `bindings/providers/` 下的 `TextureInputProvider`, `CubemapInputProvider`, `KeyboardInputProvider`, `BufferInputProvider` 负责资源装载/更新及绑定创建，`RenderPipeline` 只通过 provider 接口拿到 `PassInputBinding`。
- `src/render/`
  - `PassGraph.*` 纯粹计算拓扑与历史依赖。
  - `PassInstance.*` 只关心 shader 组装与输入绑定（通过 `bindings` 模块）。
  - `RenderPipeline.*` 负责 Graph 构建、目标缓冲管理与执行。
  - `GlLoader.*` 封装 GLAD 初始化与 OpenGL ES 函数指针加载，集中管理 GL 扩展查询与能力检测。
  - 其他文件 (`ShaderProgram`, `FullscreenTriangle`, `PipelineTypes`) 保持基础 GL 抽象。
- `src/resources/`
  - `TextureLoader.*` 只保留 `TextureHandle` 与缓存逻辑。
  - `TextureFactory.*` 提供纹理读取/上传细节。
  - `AssetIO`, `DemoCatalog` 等维持磁盘与外部资源交互。
  - `stb_image_impl.cpp` 作为单一编译单元实例化 STB Image，避免多重定义问题。
- `src/third_party/`
  - `glad/` — OpenGL ES 函数指针加载表（GLAD 生成，仅需 `GlLoader` 包含）。
  - `stb/stb_image.h` — 单头文件图像解码库（PNG / JPG / TGA 等格式）。
- `scripts/`
  - `parse_shadertoy.py` — 将 ShaderToy 导出的 JSON 转换为 ShaderDock `demo.json` 格式，便于将在线 shader 迁移到本地运行。

## 设计原则

1. **单一职责**：每个 `.cpp` 控制在 400 行以内，模块围绕明确责任划分（如输入绑定、图形执行、平台交互）。  
2. **分层依赖**：`manifest` → `bindings`/`resources` → `render` → `app`，避免循环引用，方便替换底层实现。  
3. **面向扩展**：`InputProvider` + `PassInputBinding` 的双层结构让每个输入类型拥有独立 `.cpp` 管理数据来源与绑定；新增类型只需新增 provider + binding，不需触碰 `RenderPipeline`/`PassInstance`。  
4. **数据即配置**：Manifest loader 只产出 POD 结构，不携带文件 I/O 或 GL 逻辑，便于单测与未来缓存。  
5. **最小 GL 接触面**：GL 相关调用集中在 `RenderPipeline`、`PassInstance`、`bindings` 与 `TextureFactory`，其余模块保持平台无关逻辑。

## 扩展指引

- **新增 demo 输入类型**：  
  1. 在 `manifest::PassInputType` 中声明新枚举，并在 Loader 中解析 JSON。  
  2. 创建 `NewInputBinding`（继承 `PassInputBinding`）封装 GL 绑定。  
  3. 实现 `NewInputProvider`（继承 `InputProvider`），在 `supports`/`create_binding` 中处理资源管理逻辑（可复用 `TextureCache` 或自定义数据源），并把 provider 注册到 `ShaderDockApp` 的 `input_providers_`。  
  4. `RenderPipeline` 会自动使用 provider 创建绑定，无需修改渲染代码。
  5. 若未来引入网络或动态资源（webcam/video），可在 `bindings/providers` 下新增 provider（维护摄像头/视频解码状态），并返回自定义 binding，即可插到现有管线。

- **新增渲染 pass 行为**：  
  - 只需修改 `RenderPipeline` 以识别额外 pass 类型，`PassGraph` 和 `PassInstance` 保持不变。

- **添加 Demo manifest 字段**：  
  - 在 `ManifestTypes` 中扩展结构，并在 `DemoManifestLoader` 中解析；其余模块只消费新字段而无需了解 JSON 细节。

