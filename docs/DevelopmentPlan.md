# ShaderDock 开发计划

## 1. 目标与现状
- **项目目标**：离线重现 ShaderToy 管线（Common + Buffer A–D + Image），可加载 JSON 清单、图片/立方体贴图资源，并在 SDL2 + OpenGL ES 3.2 上运行。
- **当前状态**：阶段 A 与阶段 B 均已完成，阶段 C（时间/鼠标/iDate 等 ShaderToy uniform 与交互）也已经交付；当前准备进入阶段 D，集中验证 Demo 并完善调试工具。
- **必备第三方库**：解析 `demo.json` 计划使用 JsonCPP；纹理/立方体贴图载入使用 stb_image（含 HDR/8bit 支持）。
- **运行环境**：Windows或者Linux。

## 2. ShaderToy Shader Inputs（WebGL → OpenGL ES 3.2 映射）
> ShaderToy 着色器入口为 `void mainImage(out vec4 fragColor, in vec2 fragCoord);`，我们在编译阶段注入统一的 ES 3.2 包装（`main` 调用 `mainImage`）并提供以下 uniform。  
> OpenGL ES 3.2 完全兼容 WebGL2 所需的 uniform 精度，只需注意：整数 uniform 需要 `glUniform1i` 族、采样器区分 2D/Cube，纹理单元绑定要与 `iChannelX` 索引一致。

| Uniform | 含义 & 数据来源 | GLES 3.2 实现细节 |
| --- | --- | --- |
| `uniform vec3 iResolution` | 画布像素尺寸（width, height, 1.0）。| 每帧读取窗口 drawable size，Z 通道固定 1.0。 |
| `uniform float iTime` | 播放时间秒。 | `SDL_GetTicks()` 差值 × 0.001。 |
| `uniform float iTimeDelta` | 单帧渲染耗时秒。 | 当前帧耗时缓存，作为 `glUniform1f` 发送。 |
| `uniform float iFrameRate` | FPS（1.0 / iTimeDelta，若首帧则回退上次数值）。 | 防止除零，可做滑动平均。 |
| `uniform int iFrame` | 自启动以来的帧序号。 | 循环计数 `uint64_t` → `GLint`。 |
| `uniform float iChannelTime[4]` | 各通道运行时间。 | Buffer/FBO pass 与 Image pass 共用；无输入则置 0。 |
| `uniform vec3 iChannelResolution[4]` | 各通道分辨率。 | 对应纹理/FBO 真实尺寸，Z = 1。 |
| `uniform vec4 iMouse` | 鼠标像素坐标（xy 实时，zw 按下时的 click）。 | SDL mouse 事件维护状态；未按下时 xy = 0。 |
| `uniform sampler2D iChannel0..3` / `samplerCube` | 输入纹理/缓冲。 | 根据 `demo.json` 中 `type` 和 `sampler` 设置纹理对象，附加到固定纹理单元。 |
| `uniform vec4 iDate` | `(year, month, day, seconds)`。 | 使用 `std::chrono` 读取本地时间，seconds = (hour*3600+...)。 |

## 3. Demo 覆盖需求与能力矩阵

| 能力 | Halloween Radiosity | Image Based PBR Material | Texture LOD | 说明 |
| --- | --- | --- | --- | --- |
| 多 Pass & Common 拼接 | ✅ Buffer A–D + Common | ✅ Buffer A/B + Image | ❌ | 构建执行图 + Common 注入。 |
| Ping-Pong / 自引用 | ✅ Buffer A 反馈自身 | ✅ Buffer A | ❌ | 需要双 FBO 切换与历史帧纹理。 |
| 多通道输入（Buffer/Cubemap/Texture） | ✅ 4 个 buffer 输入 | ✅ 2 cubemap + 2 texture + buffers | ✅ 1 texture | 解析 `inputs` 节点，按 `channel` 绑定。 |
| Cubemap 采样 & mipmap | ❌ | ✅ | ❌ | stb_image + OpenGL ES `glTexImage2D` six faces + `glGenerateMipmap`。 |
| 纹理 wrap/filter/vflip | ✅（clamp/nearest） | ✅（repeat/mipmap） | ✅（repeat/mipmap） | 根据 `sampler` 生成状态。 |
| iMouse 交互 | ✅（Orbit 控制） | ❌ | ❌ | SDL 事件驱动 uniform。 |
| JSON 管线装载 | ✅ | ✅ | ✅ | JsonCPP 解析 manifest。 |

## 4. 开发阶段与任务

### 阶段 A：运行时基础
1. **CMake 更新**：引入 JsonCPP、stb_image（或直接编译 `stb_image.cpp`），配置头文件路径，保证 MSYS2/UCRT64 & Linux 构建通过。
2. **GL 绑定扩展**：在 `gl_bindings.hpp` 补充 VBO/FBO/Texture/Renderbuffer/Mipmap/Uniform 族函数；提供全屏三角形顶点数据。
3. **资源加载层**：
   - JSON：封装 `DemoManifest`，解析 renderpass、inputs、sampler、资源路径。
   - 纹理：实现 2D/立方体贴图加载、垂直翻转、sRGB → 线性选项、mipmap 生成、缓存复用。

### 阶段 B：渲染管线
1. **Shader 预处理**：读取 Common + Pass GLSL，注入宏（`#define SHADER_PASS_BUFFER_A` 等）、提供统一的 `main()` 包装和 uniform 声明。
2. **Pass 拓扑排序**：根据 `inputs` 依赖构建 DAG，支持 Buffer 自引用 → Ping-Pong（两套 FBO 轮换）；每个 Pass 记录目标尺寸（默认窗口，可允许 JSON override）。
3. **执行框架**：每帧按拓扑遍历 Pass，绑定目标 FBO，设置 viewport/canvas，配置通道纹理后调用 draw call。

### 阶段 C：ShaderToy Uniform & 交互
1. **时间系统**：记录 Δt/FPS、各通道运行时、帧计数。
2. **鼠标输入**：SDL 事件更新 `iMouse`，支持按下、松开、拖拽状态。
3. **日期与帧率**：本地时间填充 `iDate`，并在 UI 或日志中曝光。
4. **通道 Uniform**：把 Buffer FBO 纹理、外部 texture/cubemap 分配到 `iChannel0..3`，并同步 `iChannelResolution`。

### 阶段 D：Demo 验证与工具
1. **Demo 选择**：支持命令行参数或简单菜单加载 `assets/demos/<name>/demo.json`。
2. **Halloween Radiosity 回归**：验证多 Buffer & ping-pong；记录帧稳定时间（前 12 帧）。
3. **Image Based PBR Material**：验证 cubemap 方向、mipmap、纹理 repeat；确保 Buffer B 的纹理输入可热加载。
4. **Texture LOD**：验证单纹理 + `textureLod` 函数行为。
5. **调试辅助**：增加日志/ImGui overlay（可选）显示当前 Pass、FPS、Uniform 值，方便回归其它 ShaderToy demo。


---
完成以上阶段即可覆盖三个示例 Demo 的需求，也为引入更多 ShaderToy 作品奠定基础。
