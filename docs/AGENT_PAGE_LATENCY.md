# Agent 访问页切换延迟专项

**日期**：2026-11-14
**对象**：点击侧栏「Agent API 已启动」/「Agent 访问」→ AgentAccessView 可见
**样本**：1 003 pins 合成图库，M1 Max / macOS 26.6.2，release

---

## 1. 结论

切换逻辑本身很快：`select(section:)` 同步耗时 **0.2 ms**。慢在进入页面后的三件事：

1. 首帧要一次性布局整页（header + 渐变 hero + 终端预览 + 4 张面板，约百个节点），`body` 求值 12–18 ms、首帧 52–91 ms；
2. 页面 `onAppear` 里写 `portField` 触发**第二次整页 body 求值**；
3. `select(section:)` 用 `withAnimation(.snappy(0.28))` + 内容 `.transition(.opacity)`，页面淡入持续 **280 ms**，即使首帧已提交，看起来仍然慢。

优化后：

| 指标 | 优化前 | 优化后 |
|---|---:|---:|
| 切换同步 | 0.2 ms | 0.2 ms |
| 页面 `body`（warm） | 10–18 ms | **4.5–5.8 ms** |
| `onAppear`（warm） | 44–53 ms | **20–24 ms** |
| 首个显示帧（warm） | 49–60 ms | **24–38 ms** |
| 首个显示帧（首次） | 84–91 ms | **44–52 ms** |
| 页面淡入 | 280 ms | **无（瞬时切换）** |

面板内容在首帧后 40 ms 填入；用户先看到 header + hero，随后下方卡片出现，不再阻塞首帧。

---

## 2. 诊断方法

临时 `--agent-probe`：

- 启动后等待 2 s，连续 3 次从画廊切到 Agent 页；
- 记录 `select` 同步、`AgentAccessView.body` 次数/时刻、`onAppear`、`NSView.displayLink` 首个显示帧；
- 变量对照：去掉 hero 模糊、去掉 `portField` 的 onAppear 赋值、去掉 section 切换动画、面板分阶段。

诊断代码已移除。

---

## 3. 关键测量

| 变体 | body | onAppear（warm） | 首帧（warm） |
|---|---:|---:|---:|
| 原始 | 10–18 ms | 44–53 ms | 49–60 ms |
| 去掉 hero 模糊 | 9.8–17 ms | 48–49 ms | 52–53 ms |
| 去掉 `portField` onAppear 赋值 | 9.8–18 ms | 48–49 ms | 49 ms |
| 去掉 section 切换动画 | 14–22 ms | 48–53 ms | 56–61 ms |
| **面板分阶段 + 去 onAppear + 去动画** | **4.5–5.8 ms** | **20–24 ms** | **24–38 ms** |

- hero 的两个 `blur(80/90)` **不是**主因（去掉无改善），已保留设计；
- 单个优化收益都有限，组合后才把首帧从 ~50 ms 降到 ~25–35 ms；
- 首次打开仍比 warm 多 ~20 ms（AppKit 首次布局/滚动视图 warm-up），44–52 ms 可接受。

---

## 4. 已实现

1. **面板分阶段**：首帧只渲染 header + hero；40 ms 后填入 QUICKSTART / PROMPT / ENDPOINTS / SERVICE 四张卡片，之前显示同尺寸骨架，避免滚动条跳动。
2. **去掉 onAppear 的 portField 赋值**：端口输入框改为可选状态 `portField: String?`，未编辑时直接显示 `store.agentPort`；不再触发第二次整页渲染。
3. **去掉 section 切换动画**：`select(section:)` 不再包 `withAnimation(.snappy(0.28))`，页面瞬时出现；230–280 ms 的淡入消失。
4. 保留 hero 的渐变与模糊（实测不是瓶颈），保留所有卡片内容与端口编辑功能。

文件：`Sources/Lore/Views/AgentAccessView.swift`、`Sources/Lore/Store/LibraryStore.swift`。

---

## 5. 验收与验证

| 指标 | 目标 | 结果 |
|---|---:|---:|
| warm 首个显示帧 | ≤40 ms | 24–38 ms |
| 首次首个显示帧 | ≤60 ms | 44–52 ms |
| 页面 body（warm） | ≤8 ms | 4.5–5.8 ms |
| 切换后无二次整页渲染 | — | 是 |
| 页面淡入 | 无 | 是 |

- Release 构建通过；Agent 页截图正常（header、hero、四张面板、端口 4242）。
- `./scripts/perf-guard.sh --pins 1000` → PASS（数据层未受影响）。
- 端口编辑、Apply、API 状态切换逻辑保留；端口输入框首次显示正确，不再依赖 onAppear 状态。

---

## 6. 后续可选

- 若首次打开仍希望进一步压到 warm 水平，可在 launch 后离屏预热一次 Agent 页 header/hero（成本：启动期几十 ms）；
- 若以后页面继续增长，可把下方四张卡片改为真正的 `LazyVStack` 或分两批填入；
- 目前未做，因为 warm 24–38 ms、首次 44–52 ms 已达到交互预算。
