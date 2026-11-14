# 拉伸画廊宽度：卡顿分析与优化（已实施）

**适用** Lore 1.0（Swift 6 / SwiftUI / macOS 14+）

**结论**：卡顿不在图片解码、也不在数据查询，而在**窗口每移动一个像素，画廊就同步重排一遍布局**。现在拖动时栅格宽度按 16 pt 台阶跟随、松手对齐精确宽度：1000 张库每帧布局 **14.2 ms → 5.3 ms**，5000 张库 **16.4 ms → 6.4 ms**，整段拖动里网格真正重排的次数从 **1801 次降到 230 次**。

> 第一版实现曾经让"拉窄窗口时画廊不再响应式"。原因和修复见第 5 节——它值得单独记下来，因为那是这类"窗口宽度驱动布局"最容易踩的坑。

---

## 1. 结果

同一台机器、release 构建、内置种子图生成的合成图库，窗口固定 1440×900，宽度在 1120↔1720 pt 之间按 2 pt 步进来回扫（模拟一次连续拖动，600 个 resize 事件/轮），取三轮里最快的一轮：

| | 1000 张 | 5000 张 |
|---|---:|---:|
| 优化前 layout p50 / p95 / max | **14.22 / 16.58 / 30.21 ms** | **16.40 / 18.83 / 31.02 ms** |
| 优化后 layout p50 / p95 / max | **5.25 / 10.06 / 25.60 ms** | **6.43 / 12.14 / 25.03 ms** |
| 网格提交新宽度的次数（1806 帧） | 1801 → **230** | 1801 → **230** |
| `columns()` 每次宽度变化 | 0.11 ms（每帧重算） | 0.56 ms → **≈0（命中缓存）** |
| 每帧绘制 | 0.01–0.06 ms | 0.01–0.06 ms |

- 60 Hz 预算 16.7 ms：优化前 p95 贴着预算且有 30 ms 尖峰；优化后 p50 ≈ 5–6.4 ms、p95 ≈ 10–12 ms，**每一档都在预算内**。
- `grid-relayouts` 是网格真正提交新宽度的次数。600 pt 的拖动按 16 pt 台阶约 37 次/方向，两方向 × 三轮 ≈ 230 次，与实测吻合——这说明网格**确实在跟着窗口重排**，而不是靠"不响应式"换来的低耗时。
- 绘制（0.01 ms）始终不是瓶颈，所以图片、缩略图、缓存策略都不在这次范围内。

> 曾经测到过 3.3 ms/帧的数字：那是第一版（见第 5 节）在拉窄时根本没有重排造成的假象，已作废。

---

## 2. 测量方法（可复现）

```bash
./scripts/build-app.sh release            # 必须是 release
./scripts/resize-bench.sh --pins 1000     # 或 --pins 5000
```

脚本做三件事：

1. 用内置种子图生成一个 N 张的合成图库，通过 `-lore.debugHome` 启动应用；
2. 应用带 `--resize-bench` 启动时（`Sources/Lore/Performance/ResizeBench.swift`），把窗口固定成 1440×900，按 2 pt 步进扫宽度，并把布局和绘制分开计时：

   ```swift
   window.setFrame(rect, display: false)
   window.contentView?.layoutSubtreeIfNeeded()   // layout
   window.contentView?.displayIfNeeded()         // display
   ```

3. 每轮打印 `layout` 的 mean/p50/p95/max，以及负载无关的 `grid-relayouts`：网格真正提交新宽度（也就是真正重排卡片）的次数。

几条讲究：

- **取三轮最快值**：后台负载只会让某一轮变慢，最小值才是布局成本本身的估计。
- **`grid-relayouts` 与负载无关**，用来验证"网格是否真的在跟随窗口"——只看耗时会被"根本不重排"骗过去（第 5 节就是这么踩的）。
- 用 `open -n`（LaunchServices）启动而不是直接 exec：直接 exec 时 SwiftUI 偶尔不创建窗口（会话忙时会一直空等），脚本会两种方式都重试。
- 会话必须解锁/活跃，否则应用不会建窗口。

---

## 3. 根因

| # | 原因 | 机制 |
|---|---|---|
| R1 | **列宽是逐像素信号，直接驱动整片网格的布局失效** | 每帧用窗口宽度算 `columnWidth`，再给每张卡和每列 `.frame(width:)`。窗口动 1 pt → 每列 `LazyVStack` 的宽度约束变 → 该列布局缓存整体作废（`LazyVStack` 的"懒"只对**渲染**生效，对**布局**不生效），可见卡片全部重新排版：文本重新断行、圆角/描边/阴影重新合成 |
| R2 | **`columns()` 的缓存键含像素宽度** | 每像素一个新键 → 每帧一次 O(N) 的 `MasonryComposer.split`（1k 0.10 ms、5k 0.56 ms），并产出新数组，让 `ForEach` 每帧 diff N 个身份 |
| R3 | **每帧一次「布局 → 偏好值 → State → 再布局」往返** | 网格背景发 `GridWidthKey`，`onPreferenceChange` 几乎每帧写回 State，让整个滚动页再求值一遍；而该值只在极窄窗口下才会被用到 |
| R4 | **宽度从根节点下发，整棵左树跟着求值** | 根部 `GeometryReader` 每帧重跑，`SidebarView`/`TopBarView`/页头/筛选栏跟着重新求值；`DetailPrewarm`（隐藏的 240×240 `ScrollView`）常驻主树参与每次布局 |
| R5 | **跨列数阈值时全体重分列** | 1120–1720 pt 对应 3–5 列，跨带那一帧所有卡片换列、在 `LazyVStack` 之间迁移，等于可见区重建；实测尖峰 25–30 ms 就在这些帧 |
| R6 | **每张卡片的材质胶囊** | `metadataPill` / `gifBadge` 的 `.ultraThinMaterial` 在尺寸变化时要重新采样背板，且即使 `opacity(0)` 也留在树里 |

---

## 4. 已实施的优化

### 4.1 拖动中量化栅格宽度，松手对齐精确宽度（R1 的主刀）

`Sources/Lore/Views/LibraryView.swift`

```swift
private static let liveResizeQuantum: CGFloat = 16

private func applyGridWidth(_ raw: CGFloat) {
    guard raw.isFinite, raw > 0 else { return }
    let quantum = widthSettle.pending ? Self.liveResizeQuantum : 1
    setGridWidth((raw / quantum).rounded(.down) * quantum)
    scheduleWidthSettle(raw)      // 140 ms 内没有新变化 → 对齐 raw
}
```

- **连续变化才量化**：`TaskSlot.pending` 在每次变化时置位、140 ms 静默后清除。窗口在动（拖动、双击缩放动画）时它一直是 true，于是只按 16 pt 台阶重排；窗口停下后自动对齐到精确宽度，右侧不会留台阶缺口。
- **量化值走 `withTransaction(Transaction(animation: nil))`**：这条路径绝不叠动画。
- **状态与计时器都不参与观察**：`TaskSlot` 是普通 class（`Sources/Lore/Design/TaskSlot.swift`），放在 `@State` 里但每次改它不会让视图失效——否则每来一个 resize 事件就多一次 body 求值，正好抵消收益。

### 4.2 列分配只按「列数」缓存（R2）

`Sources/Lore/Store/LibraryStore.swift`

```swift
private struct ColumnsKey: Hashable {
    var query: GalleryQuery
    var columns: Int            // 不再包含 width
}
```

贪心分列只依赖相对高度（`width / aspectRatio + 常数题注高`），对整体等比缩放不敏感，所以同一列数带内复用上一次分列结果；换宽不会跳列。顺带把一次 miss 里的 `currentQuery` 从两次降到一次。

### 4.3 内容列必须由「窗口宽度」固定（R1/R4 的前提，也是第 5 节回归的修复）

`Sources/Lore/Views/RootView.swift`

```swift
HStack(spacing: 0) {
    SidebarView().frame(width: LoreLayout.sidebarWidth).padding(.top, LoreLayout.titlebarInset)

    GeometryReader { geometry in
        VStack(spacing: 0) {
            TopBarView()
            content(columnWidth: geometry.size.width)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .clipped()
    }
}
```

- **内容列按几何宽度固定**，画廊因此永远拿到一个由窗口决定、且一定在缩小的宽度。
- **侧栏留在 GeometryReader 之外**：拖动时侧栏树不参与每帧求值，这是 R4 的收益所在（代价是顶栏和画廊仍按帧求值，见第 1 节的实测数据）。
- 画廊不再自己测宽度，而是接收 `columnWidth`（`LibraryView(columnWidth:)`），只在量化值变化时重排网格。

### 4.4 删掉每帧的 Preference 回写（R3）

`GridWidthKey`、`onPreferenceChange`、网格背景里的 `.preference(...)` 全部删除；宽度由 4.3 传入，只有量化值变化才写 State。

### 4.5 单卡降本（R6）

`Sources/Lore/Views/PinCard.swift`：`metadataPill` / `gifBadge` 的 `.ultraThinMaterial` 换成同样的纯色胶囊底色（`Color.black.opacity(0.55)`），视觉几乎一致，省掉尺寸变化时的背板重采样。

### 4.6 预热层退出视图树（R4）

`DetailPrewarm` 只在启动后 1.5 s 内存在（`RootView.swift`），之后移出视图树，不再参与每次布局。

### 4.7 让回归可测

- `Perf.gridRelayouts`：网格提交新宽度的计数器，`--resize-bench` 直接读它，得到与机器负载无关的判据。
- `Sources/Lore/Performance/ResizeBench.swift` + `scripts/resize-bench.sh` 是常驻工具，和 `--bench` / `perf-guard.sh` 一样可随时复测。

---

## 5. 过程中出现的一次回归：拉窄时不再响应式

**现象**：窗口从 1440 拉窄到 1080，栅格仍保持 5 列，卡片被挤扁、内容被窗口裁切，侧栏也一半露在窗口外。

**原因有两层，都是"宽度来源"的问题**：

1. **量错了对象**。第一版让网格测量*自己的*宽度（背景 `GeometryReader`）。但网格的最小宽度就是它各列宽度之和——窗口变窄后，网格内容仍然要那么宽，于是测回来还是旧的大宽度，列数自然不降。**测量点落在被测量对象自己的下游，形成了自锁**。
2. **内容列没有钉在窗口上**。删掉根部的 `.frame(width: contentWidth)` 之后，内容列宽度由内容的最小宽度决定。网格撑着 5 列，内容列就比窗口还宽；`ZStack` 居中摆放，于是整棵树都溢出被裁切——连侧栏都被推出窗口。

**修复**（4.3 的结构）：内容列宽度只由窗口几何决定（`GeometryReader` 包内容列、`.frame(width: geometry.size.width)`），侧栏放在 reader 之外；画廊不再自测宽度，改为接收 `columnWidth`。这样窄窗口一定读数正确，而网格再怎么撑也只会溢出被 `clipped()` 裁掉、不会反过来把整棵树撑大。

**教训**：窗口驱动的布局里，宽度只能来自窗口（或从窗口派生的容器），不能来自内容自身的测量——否则"内容撑大容器、容器又决定内容"就是一个死循环，表现为"往小拉没反应，往大拉正常"。

---

## 6. 取舍与限制

- **拖动中右侧最多留 15 pt 空白**（栅格按 16 pt 台阶收缩）。松手 140 ms 内对齐，观感上只在拖动瞬间有一个可忽略的边距；想要更贴边可把 `liveResizeQuantum` 降到 8（重排次数翻倍、每次更小）。
- **跨列数带仍会重排一次**（3→4→5 列），这是瀑布流语义；实测 25–30 ms 的尖峰就在这些帧，每次拖动出现 4 次左右。
- **拖动中顶栏/页头仍按帧参与求值**：内容列在 `GeometryReader` 里（为了拿到窗口宽度），这是 5–6.4 ms/帧里的一部分；只有侧栏被移出了每帧求值。
- `gridRelayouts` 是给基准测试用的全局计数器，正常使用只做一次自增。

---

## 7. 还能再往下做（按收益排序）

1. **把顶栏/页头也移出每帧求值**：给内容列宽度做与网格相同的量化（16 pt），让 `VStack { TopBar; content }` 只在台阶上求值。需要接受 16 pt 的右侧留白（或只对画廊做、顶栏用精确值，但那就得分两层 GeometryReader）。预计再省 1–2 ms/帧。
2. **自建窗口化网格**：用列高前缀和 + 可见区间二分，只 `ForEach` 可见卡片，让每帧成本与 N 彻底无关。当前 5000 张 6.4 ms 已在预算内，这一项只在图库再大一个量级时才必要。
3. **卡片阴影条件化**：`.shadow` 现在以 `radius: 0 / alpha: 0` 常驻，只在悬停时需要。
4. **页头/筛选栏 `Equatable` 化**：量不大（~0.5 ms），可顺手做。

---

## 8. 复测清单

1. `./scripts/build-app.sh release && ./scripts/resize-bench.sh --pins 1000`：
   - `layout best` p50 ≤ 8 ms、p95 ≤ 12 ms；
   - `grid-relayouts` 约等于「拖动距离 / 16 pt × 来回 × 轮数」（1000/5000 张实测 230 / 1806），**明显小于帧数**但**不应接近 0**——接近 0 说明网格根本没跟随窗口（第 5 节的回归）。
2. `--pins 5000` 重复一次，确认与 1000 张同量级（当前 5.3–6.4 ms）。
3. 手动：把窗口从 1440 拖到 1080，列数应从 5 变到 3；再拖回 1680，应回到 4–5 列；两侧都不能出现内容被裁切。
4. `./scripts/agent-smoke-test.sh`：本机纯 Command Line Tools 环境缺 XCTest runner，`swift test` 只能编译不能执行；**冒烟测试是本地权威验证**（当前 192 项全部通过）。
5. `./scripts/perf-guard.sh`：数据层门禁，确认没有回退。

---

## 附录：改动位置

| 位置 | 内容 |
|---|---|
| `Sources/Lore/Views/RootView.swift` | 内容列按窗口几何固定（侧栏在 reader 外）；预热层退出视图树；`--resize-bench` 入口 |
| `Sources/Lore/Views/LibraryView.swift` | `columnWidth` 入参、量化宽度、松手对齐 |
| `Sources/Lore/Design/TaskSlot.swift` | 不触发视图失效的防抖任务槽 |
| `Sources/Lore/Store/LibraryStore.swift` | 列分配缓存键改为「查询 + 列数」 |
| `Sources/Lore/Views/PinCard.swift` | 材质胶囊改纯色 |
| `Sources/Lore/Performance/Perf.swift` | `gridRelayouts` 计数器 |
| `Sources/Lore/Performance/ResizeBench.swift` | `--resize-bench` 实现 |
| `scripts/resize-bench.sh` | 生成图库、启动、重试、打印结果 |
| `Sources/Lore/Design/LayoutMetrics.swift` | 删除 `loreContentWidth` 环境键 |
