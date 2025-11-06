# ShaderDock
ShaderDock 是一个使用 SDL2 与 OpenGL ES 3.2 构建的轻量级跨平台渲染器， 可在本地运行 ShaderToy 风格的多通道 Fragment Shader。 它从 JSON 配置中读取渲染管线，自动解析通道依赖、管理 ping-pong 双缓冲，并按拓扑顺序执行所有 Pass——实现与 ShaderToy 接近的多帧渲染逻辑。
