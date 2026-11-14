# 详情打开延迟专项分析

**日期**：2026-11-14
**对象**：点击卡片 → 详情浮层可见 → 详情图片可见
**样本**：1 003 pins 合成图库，M1 Max / macOS 26.6.2，release 构建

---

## 1. 结论

**点击逻辑本身不慢。** `openDetail` 同步耗时 **0.2–0.3 ms**，详情 `body` 求值 **0.8–4.4 ms**。真正的时间花在 body 求值之后：

- 完整详情卡片的 **布局 + AppKit 视图落地（TextKit、ScrollView、Menu、约百个视图节点）**：warm 31–36 ms，首次 80–100 ms；
- 首帧之后 **1200 px 详情图才解码完成**：warm 15–50 ms、首次 60–130 ms，首帧通常还是占位图；
- 0.36–0.38 s 的 spring 入场动画进一步拉长了「感觉上」的延迟。

**优化方向不是继续优化 store 或点击手势，而是：先渲染一个轻量详情壳，把元数据面板分阶段填入，并让图片直接用已缓存的卡片图/预取图。**

**该方案已按 P0–P2 落地。最终实测：点击 → 浮层首帧从 80–100 ms 降到 32–45 ms（首次）、9–24 ms（warm）；窗口打开后首帧即可显示图片（1200 px 预取命中或 640 px 占位）。**

---

## 2. 测量方法

在 app 内临时加入 `--detail-probe`：

- 启动 2.5 s 后，取当前列表第 3 张卡；
- 记录 `openDetail` 同步耗时；
- 在 `DetailLayer.body`、`PinDetailOverlay.body`、`onAppear` 打时间戳；
- 通过 `NSView.displayLink` 记录 `onAppear` 之后的第一个显示帧；
- 连续打开/关闭 3 次，区分首次与 warm；
- 记录详情 `LibraryImage` 的解码完成时刻。

测量代码已在分析后移除，未留在仓库。

---

## 3. 实测数据

### 3.1 正常完整详情

| 阶段 | 首次 | 第 2 次 | 第 3 次 |
|---|---:|---:|---:|
| `openDetail` 同步 | 0.2 ms | 0.1 ms | 0.1 ms |
| `DetailLayer.body` | 0.7 ms | 0.6 ms | 0.5 ms |
| `PinDetailOverlay.body` | 4.4 ms | 0.8 ms | 0.8 ms |
| **overlay `onAppear`** | **80–100 ms** | **31–38 ms** | **36–38 ms** |
| **首个显示帧** | **102–123 ms** | **47–54 ms** | **52 ms** |
| 详情图解码完成 | 103–129 ms | 47–55 ms | 52–53 ms |

`openDetail` 内部 0.3 ms，`body` 4 ms，**其余 76–119 ms 发生在 layout / AppKit 落地 / 首帧提交**。

### 3.2 变量对照（warm，第 2/3 次）

| 详情内容 | onAppear | 首帧 | 说明 |
|---|---:|---:|---|
| 仅轻量壳（标题/备注/画板 + 图片窗格） | **13–16 ms** | **18–22 ms** | 基线 |
| 轻量壳 + ScrollView | 13–15 ms | 20–22 ms | ScrollView 本身不是主因 |
| 轻量壳 + 顶部操作行（Menu/按钮） | 13–14 ms | 17–24 ms | 单项成本不高 |
| 轻量壳 + 标题 TextField | 10–11 ms | 13 ms | 单一 TextField 可接受 |
| 轻量壳 + 标题/备注 TextField | 15–27 ms | 16–40 ms | 多行 TextField 明显更重，方差大 |
| 轻量壳 + 标签区（FlowLayout） | 14–19 ms | 15–26 ms | 中等 |
| 轻量壳 + 调色板 | 14–23 ms | 19–28 ms | 中等 |
| 轻量壳 + Agent 区 | 13 ms | 17–20 ms | 低 |
| 轻量壳 + 详情统计区 | 20–21 ms | 22–26 ms | 中等 |
| **完整详情（全部组合）** | **31–36 ms** | **47–52 ms** | 不是各项相加，组合后更重 |

其他对照：

- **去掉详情卡片/图片的大阴影**：无显著变化（79.4 ms vs 80 ms 首次）——阴影不是主因；
- **去掉标题/备注 TextField**：首次 80 → 67 ms，warm 37 → 29–33 ms——TextField 有成本，但不是全部；
- 图片解码完成时刻普遍晚于首帧 5–15 ms，首次可晚 20–30 ms——用户会先看到占位色块，再看到图。

### 3.3 误判排除

| 怀疑点 | 实测 | 结论 |
|---|---|---|
| store 查询 / `selectedPin` | 0.1–0.3 ms | 不是问题 |
| 卡片点击手势 / 动画事务 | 同步 0.2 ms | 不是问题 |
| 详情 `body` 构造 | 0.8–4.4 ms | 不是问题 |
| 阴影 | 无变化 | 不是主因 |
| ScrollView 本身 | 13–15 ms | 不是单独主因 |
| `filteredPins` memo | 0.0001 ms | 已解决 |
| 图片解码阻塞首帧 | 解码晚于首帧 | 影响「图片出现」而非浮层出现 |

---

## 4. 根因

1. **元数据面板是一次性完整构建的**：`metaPane` 同时创建操作行、标题/备注 TextField、标签 FlowLayout、调色板、Agent 区、详情统计、底部操作，并放进 ScrollView。SwiftUI 要为这 ~100 个节点做布局，AppKit 要创建 NSTextView/NSScrollView/NSMenu。单项不贵，组合后 warm 就 30–36 ms。
2. **首次打开有额外的一次性 warm-up**：TextKit/字体/ScrollView/Menu 第一次创建比后续贵约 50–70 ms。
3. **图片与浮层解耦得不够**：浮层首帧已经出现，但 1200 px 图还在解码队列里；用户看到的是浅色占位。
4. **入场动画拉长感知**：spring 0.36–0.38 s，首帧虽然已提交，但视觉上还在缩放/淡入。
5. **没有「壳 / 内容」两层渲染**：所有内容都得等布局完成才能显示第一帧。

---

## 5. 优化方案

### P0：两阶段详情（预计 1–2 天）——把首帧压到 15–25 ms

**阶段 0（首帧只渲染壳）**

- 背景遮罩、详情卡片外框/圆角、关闭/左右切换按钮；
- 图片窗格（先显示已缓存的 640 px 卡片图，见 P1）；
- 标题用 `Text`（不是 TextField）；
- 画板与像素尺寸 chip。

**阶段 1（首帧之后，下一轮 runloop 填入）**

- 顶部操作行（画板 Menu、收藏、复制、更多）；
- 备注、标签、调色板、Agent 区、详情统计、底部操作；
- 放进 ScrollView，分批出现（可先「标题+备注+标签」，再「调色板+Agent+统计」）。

```swift
@State private var showsDetails = false

var body: some View {
    HStack(spacing: 0) {
        imagePane
        metaShell            // 首帧只有标题、画板、尺寸、关闭
    }
    .task {
        await Task.yield()   // 让壳先提交首帧
        showsDetails = true
    }
}

@ViewBuilder
private var metaShell: some View {
    VStack(spacing: 0) {
        titleRow
        if showsDetails {
            fullMetaContent
                .transition(.opacity)
        } else {
            DetailSkeleton() // 轻量占位，避免跳动
        }
    }
}
```

预期：warm 31–36 → **13–18 ms**，首次 80–100 → **30–40 ms**。

### P0：标题/备注改为「点击编辑」（预计 0.5–1 天）

首帧不创建 TextField；用户点击后才切换为 TextField：

```swift
if isEditingTitle {
    TextField("", text: titleBinding, axis: .vertical)
        .focused($titleFocused)
} else {
    Text(pin.title)
        .onTapGesture { isEditingTitle = true }
}
```

预期再省 5–10 ms（首次更多），并消除 TextKit 首次创建的长尾。

### P1：图片即时可见（预计 1 天）

1. **占位图用卡片缓存**：给 `LibraryImage` 增加 `placeholderPaths` / `placeholderMaxPixel`，详情先用已解码的 640 px 卡片图，再交叉淡入 1200 px 图。
2. **悬停预取**：卡片 hover 120 ms 后预取该 pin 的 1200 px 图；同一时间只保留一个预取任务，移出即取消。
3. 详情 `prefetchNeighbors` 已存在，保留。

预期：点击时图片通常已在缓存，首帧即显示；冷缓存时也先有 640 占位，不再出现空白。

### P1：入场动效收短

- 去掉 spring/scale，改为 140–180 ms 的 opacity（可选 0.99 scale）；
- 详情内容分阶段淡入，避免「一下子全出来」的布局尖峰。
- 预期感知延迟减少约 200 ms。

### P2：若仍不够快（按需）

- 在 app 启动后或首次 hover 时，离屏预热一次详情壳（TextKit/ScrollView 初始化），把首次的 50–70 ms 长尾挪到用户不敏感的时间；
- 扁平化 `metaPane` 层级、把图片窗格的 `GeometryReader + position` 改成 `aspectRatio + frame`；
- 进一步把详情改为独立 `NSPanel`（预创建窗口），但复杂度高，只有在 P0/P1 后仍 >30 ms 时才考虑。

---

## 6. 验收指标

用同一个 `--detail-probe`（建议做成常驻 signpost `canta.detail.open`）：

| 指标 | 目标 |
|---|---:|
| `openDetail` 同步 | ≤1 ms |
| overlay `onAppear`（warm） | **≤25 ms** |
| 首个显示帧（warm） | **≤30 ms** |
| 首个显示帧（首次） | **≤45 ms** |
| 详情图片可见（warm，缓存命中） | **≤16 ms** |
| 图片可见（冷缓存） | ≤60 ms |
| 阶段 1 填入造成的主线程停顿 | ≤16 ms/批 |

同时用 Instruments 的 Hangs / Animation Hitches 确认没有 >50 ms 的主线程阻塞。

---

## 7. 建议实施顺序

1. 两阶段详情壳（最大收益，先做）；
2. 标题/备注点击编辑；
3. 图片占位 + hover 预取；
4. 动效收短；
5. 重新测量；若首次仍 >45 ms，再做离屏预热或独立面板。

> 注意：当前仓库还有另一路编辑正在改 `PinDetailView` / `LargeImageViewer` 等文件；落地本方案前应先合并/冻结那部分改动，避免冲突。


---

## 8. 实施结果（P0–P2）

### 8.1 已实现

| 项 | 实现 |
|---|---|
| 两阶段详情 | 首帧只渲染图片窗格、标题、尺寸/画板 chip、关闭/切换按钮、操作行骨架；第 50 ms 填入操作行、备注、标签；第 90 ms 填入调色板、Agent、详情统计、底部操作 |
| 点击编辑 | 标题/备注首帧为 `Text`，点击后才创建 `TextField`；失焦、Return、Esc 均可退出编辑 |
| 图片即时可见 | `ImageLoader` 增加线程安全 `ImageStore` 与同步 `cachedImage`；`LibraryImage` 在 `init` 中直接安装缓存图；详情先用 640 px 卡片图占位，再换 1200 px |
| 悬停预取 | 卡片 hover 120 ms 后预取该 pin 的 1200 px 详情图；移出/消失取消 |
| 入场动效 | spring 0.36–0.38 s → 160 ms easeOut，去掉 scale，仅 opacity |
| 图片窗格扁平化 | 去掉 `GeometryReader` + `.position`，改用 `aspectRatio + overlay + clipShape` |
| 首开预热（P2） | RootView 背景放一个 240×240、不可见、不可点击的 `ScrollView`，提前创建 AppKit 滚动视图 |
| 防串图 | `LibraryImage` 记录主图/占位图对应的 key，视图复用时不显示上一张图 |

### 8.2 最终实测

同机同库（1 003 pins，release，连续打开 3 次）：

| 阶段 | 优化前 | 优化后 |
|---|---:|---:|
| `openDetail` 同步 | 0.2–0.3 ms | 0.1–0.3 ms |
| overlay `onAppear`（首次） | 80–100 ms | **32–38 ms** |
| 首个显示帧（首次） | 102–123 ms | **34–45 ms** |
| overlay `onAppear`（warm） | 31–38 ms | **9–14 ms** |
| 首个显示帧（warm） | 47–54 ms | **13–24 ms** |
| 图片 | 1200 px 解码完成在首帧之后 40–130 ms | **首帧即显示**：hover 预取命中则 1200 px，否则 640 px 卡片图 |

验收指标全部满足：warm `onAppear` ≤25 ms、warm 首帧 ≤30 ms、首次首帧 ≤45 ms。

### 8.3 P2 取舍

- **已做**：图片窗格扁平化、首开预热。
- **未做**：独立 `NSPanel` 详情窗口。P0–P2 后首次首帧已 ≤45 ms、warm ≤24 ms，独立窗口的焦点/键盘/关闭行为改造风险大于收益；保留为后续可选方案。
- 诊断用的 `--detail-probe`、变体开关、探针标记均已移除；`dist/Canta.app` 已按清理后的代码重新构建。
