# Canta

**简体中文** · [English](README.en.md)

**属于人类与 Agent 的安静视觉图库。**

Canta 是一个原生 macOS 应用，用来快速收录 UI 截图、在 Pinterest 风格的画廊中浏览、补充有用元数据，并通过本地 HTTP API 把整个图库变成编程 Agent 可读取的设计参考。收藏一个喜欢的界面，Agent 就能在写下一个屏幕时获取它的色板、尺寸、标签和原图。

![Canta 图库](docs/screenshots/gallery.png)

<p align="center">
  <img src="docs/screenshots/detail.png" width="49%" alt="灵感详情：元数据与色板" />
  <img src="docs/screenshots/agent.png" width="49%" alt="Agent 访问页面与本地 API 端点" />
</p>

## 为什么是 Canta

设计参考通常散落在截图文件夹、聊天记录或十几个浏览器标签页里。Agent 看不到这些东西。Canta 是一个小巧、本地优先的“视觉品味记忆”：

- **快速收录**：拖入文件、粘贴剪贴板（⇧⌘V），或截取屏幕区域（⇧⌘2）。
- **属于参考的 Pinterest**：平衡的瀑布流画廊，悬停收藏、画板、搜索、最近添加与收藏夹。
- **有用的元数据**：可编辑标题、设计笔记、标签、画板、来源、尺寸、文件大小、主色板与时间。
- **默认对 Agent 友好**：只读本地 API 提供增强 JSON、原图/缩略图流、Markdown 设计上下文、OpenAPI 3.1、`llms.txt`，以及应用内文档页。
- **本地且私密**：图片和元数据始终留在这台 Mac 上，服务只绑定 `127.0.0.1`。
- **中英双语**：默认跟随 macOS 系统语言，可在设置中随时切换中文或 English。

## 快速收录

| 操作 | 快捷键 |
| --- | --- |
| 打开快速收录面板 | ⌘N |
| 导入图片 | ⌘O |
| 粘贴剪贴板图片 | ⇧⌘V |
| 截取屏幕区域 | ⇧⌘2 |
| 搜索灵感 | ⌘F |
| 打开 Agent 访问 | ⌘4 |

![快速收录](docs/screenshots/capture.png)

也可以把文件拖到窗口任意位置。Canta 会自动读取像素尺寸、文件大小和最多五色调色板；标题由文件名生成，可在灵感详情中修改。

> 区域截图使用 macOS 自带的 `screencapture -i`。首次使用时系统可能请求屏幕录制权限。

## Agent 接入

应用运行时，API 默认位于 **http://127.0.0.1:4242**。

```bash
# 获取整个增强图库 JSON
curl -s http://127.0.0.1:4242/api/v1/library | jq

# 筛选灵感
curl -s "http://127.0.0.1:4242/api/v1/pins?board=Web%20dashboards&favorite=true" | jq

# 获取可直接粘贴给 Agent 的 Markdown 设计上下文
curl -s http://127.0.0.1:4242/api/v1/context

# 打开文档站
open http://127.0.0.1:4242/docs
```

每个灵感都包含 `imageURL` 和 `thumbnailURL`，Agent 可以直接读取真实图片，而不只是阅读描述。

发现端点：

- `/docs` — 供人与 Agent 阅读的样式化文档
- `/openapi.json` — OpenAPI 3.1 规范
- `/llms.txt` — 供机器读取的索引
- `/api/v1/context` — 用于提示词的 Markdown 设计上下文

服务可以在侧栏的 **Agent 访问** 或 **设置** 中停止、重启或更换端口。`/docs` 是应用内的一等界面：

[![Canta Agent API 文档](docs/screenshots/api-docs.png)](docs/screenshots/api-docs.png)

完整参考见 [docs/AGENT_API.md](docs/AGENT_API.md)。

## 构建与运行

要求：macOS 14 或更新版本，Swift 6 工具链（Xcode 或 Command Line Tools）。

```bash
./scripts/build-app.sh release
open dist/Canta.app
```

构建脚本会打包 SwiftPM 资源包、用 1024px 母版生成应用图标、写入 `Info.plist`，并对 `dist/Canta.app` 做 ad-hoc 签名。

日常开发：

```bash
swift build
swift run Canta
```

在只有 Command Line Tools（无 Xcode）的机器上，SwiftPM 的嵌套沙盒可能被宿主沙盒拦截，可以这样构建：

```bash
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache/clang"
export SWIFT_MODULECACHE_PATH="$PWD/.build/cache/swift"
swift build --disable-sandbox --manifest-cache local --cache-path .build/spm-cache --scratch-path .build
```

## 数据模型

所有内容都是普通文件，保存在：

```
~/Library/Application Support/Canta/
├── library.json      # 灵感与元数据
├── Images/           # 原始截图
└── Thumbnails/       # 1200px JPEG 缩略图
```

`library.json` 是唯一数据源，API 每次请求都会重新读取。字段定义见 [docs/AGENT_API.md](docs/AGENT_API.md)。开发时可通过 `CANTA_HOME` 指向其他图库。

## 项目结构

```
Sources/
├── Canta/                      SwiftUI macOS 应用
│   ├── CantaApp.swift          应用入口、命令、菜单
│   ├── Design/                 主题、组件、图片加载
│   ├── Localization/           中英文本地化
│   ├── Store/                  持久化、图片处理、种子图库
│   └── Views/                  画廊、详情、快速收录、Agent 访问
├── CantaAgentKit/              本地 HTTP API、文档、OpenAPI、llms.txt
└── Canta/Resources/Seed/       HTML 渲染的示例图库
Tests/                          API 测试
docs/                           API 参考与截图
scripts/                        打包与截图脚本
```

API 目标没有第三方依赖，只使用 Network.framework 与 Foundation；应用使用 SwiftUI、AppKit、ImageIO 和 UniformTypeIdentifiers。

## 设计语言

Canta 借用了 Pinterest 的自信——图片优先、留白充分、标志性的红色、不会显得机械的瀑布流——再把它变成一座更温暖的图库：纸张质感的表面、编辑感的字体、克制的动效，以及随时可触达的元数据。

应用的主红色为 `#E60023`；画布是纸白色，搭配温暖的羊皮纸色块。卡片使用 18px 连续圆角，详情浮层使用 30px 圆角，状态切换采用短促的缓动弹簧。

## 语言

应用内置 **简体中文** 与 **English** 两套界面。默认跟随 macOS 系统语言；在 **设置 → 语言** 中可随时切换，选择会被记住。界面切换立即生效。

## 验证

- `./scripts/build-app.sh release` 生成自包含的应用包。
- Agent API 有一套黑盒冒烟测试，使用临时 fixture 图库：

  ```bash
  ./scripts/agent-smoke-test.sh
  ```

  脚本会在临时端口启动真实服务，覆盖所有端点族、HEAD/OPTIONS/CORS 行为、JSON 结构、筛选、图片字节与路径穿越防护。
- `Tests/CantaAgentKitTests` 中有 35 个 Swift Testing 用例。在本机纯 Command Line Tools 环境下编译通过，但缺少 XCTest runner 无法执行；因此上述 smoke test 是本地权威验证。
- 截图可复现：`./scripts/screenshot-app.sh gallery|agent|capture|detail`，支持 `SCREENSHOT_LANG=en|zh`。

## 状态

Canta 1.0 是一个完整的本地优先 macOS 应用。示例图库全部由手写 HTML/CSS 渲染生成，运行时不请求任何外部资源或网络。