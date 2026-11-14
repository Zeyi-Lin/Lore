# Canta 交互性能优化方案

**版本** v1 · 2026-11 · 适用 Canta 1.0（Swift 6 / SwiftUI / macOS 14+）
**目标** 在不改变 `library.json` 数据格式、不改变 Agent API 契约、不引入第三方依赖的前提下：

1. 把「点详情 / ←→ 换图 / 换画板 / 搜索与编辑」类交互从 **150–300 ms（估算）** 降到 **一帧级（≤16.7 ms 起效，p95 ≤50 ms）**；
2. 让 **1 万张卡片的画板**仍然可滚动、可点击、内存可控；
3. 明确 **Rust 重构的边界**：哪些值得做、哪些不值得、什么时候再评估。

---

## 0. 结论摘要

**根因不在图片编解码，也不在「Swift 比 Rust 慢」。** 四个问题相乘，造成 N 越大越卡：

| # | 问题 | 机制 | 证据 |
|---|---|---|---|
| A | **观察粒度反了** | 17 个 `@Published` 字段，每张卡片都通过 `@EnvironmentObject` 订阅整库；任何状态写入（搜索一个字、选中一张、一个 toast）都会让 **N 张卡片重新求值 body** | `LibraryStore.swift:9-28`、`PinCard.swift:7` |
| B | **派生数据在 body 里现算** | `filteredPins` 是纯计算属性，一次 body 里被读 **5 次**（侧栏操作条/detail 另算）；每次 O(N log N) + 每 pin 拼 7 个字符串 | `LibraryStore.swift:89-138`；`LibraryView.swift:44,55,170,199,200` |
| C | **网格完全非懒加载** | `ScrollView { VStack { MasonryLayout { ForEach } } }`：N 张卡全部实例化，测量 **2 次**（`sizeThatFits` 与 `placeSubviews` 各测一遍），每张卡起一个图片任务 | `MasonryLayout.swift:25-57`、`LibraryView.swift:49-59` |
| D | **主线程同步写盘 + 全尺寸解码** | 详情标题/备注**每敲一个字符**全量编码 JSON + 原子写盘；详情加载**原图**，而 `NSImage` 是懒解码——真正的 60–70 ms 解码落在绘制时的主线程 | `PinDetailView.swift:781-797`、`LibraryStore.swift:406-413,851-860`、`Components.swift:297-314` |

**症状 → 主因映射**

| 你感受到的 | 主因 | 本方案条目 |
|---|---|---|
| 点击详情要等一下 | N 张卡 body 重算 + 全窗口动画 + 原图在绘制时解码 | 2.1 / 2.7 / 2.4 |
| ←/→ 切换图片卡顿 | 每次切换都重新解码整张原图 + 一次按键触发 5–8 次 `filteredPins` | 2.4 / 2.2 |
| 切换画板卡顿 | 5 次 `filteredPins` + 整网格两遍布局 + 全网格动画 | 2.2 / 2.3 / 2.7 |
| 卡片一多整体变卡 | 非懒加载（N 个视图 + N 个解码任务）+ 无字节上限的图片缓存（内存压力） | 2.3 / 2.6 / 2.1 |
| 搜索/改标题时掉帧 | 每键重算 `filteredPins` + 每键全量写盘 + 全网格动画 | 2.2 / 2.5 / 2.7 |

**实测代价（M1 Max，`-O`，合成 1k 图库）**

- 一次 `LibraryView` body 的**数据层**：**10.5 ms**；3k 时 **29.4 ms**；5k 时 **50.0 ms**——还没算一张卡片的渲染。
- 一次按键：`filteredPins`（搜索态）**15.5 ms** + `persist()` **15.3 ms** = **30.8 ms 主线程**，再加 N 卡重渲染。
- 详情换图：原图首次绘制 **68 ms** + 41 MB 位图；而卡片只需要 **0.65 MB** 的 476 px 位图。
- 加载/Agent 写回：**75 ms @1k / 219 ms @3k** 主线程解码，其中 **80% 是 `ISO8601DateFormatter`**（33 µs/日期）。

**建议**

| 阶段 | 内容 | 工作量 | 预期 |
|---|---|---|---|
| **P0** | 快照/投影 + 卡片值化 `Equatable` + 懒列网格 + 图片分档/后台解码 + 持久化 debounce/后台写 + 快速日期解析 + 埋点 | **约 10 个工作日**（纯 Swift，不改格式/API） | 1k 卡片 p95 交互 **150–300 ms（估算）→ <50 ms**；内存 <400 MB |
| **P1** | 搜索倒排 + 缩略图回填 + 详情独立窗口 + API 快照缓存；必要时 `NSCollectionView` 复用渲染 | 2–3 周 | 1 万卡片可用；API 单请求 <2 ms |
| **P2** | SQLite WAL、Rust 内核 | 按需 | 见第 5 节，设置明确准入条件 |

**关于 Rust：不建议重写。** Rust 不能渲染 SwiftUI/AppKit，无法改善 A/B/C/D 中的任何一项；重写 UI 是 6–12 人月且会失去现有 macOS 集成与 154 项 API 冒烟测试。Rust 真正值得的落点只有「**离线批量媒体 worker**」「**十万级索引服务**」「**跨平台内核**」，而且要等 P0/P1 用数据证明瓶颈还在别处。详见第 5 节。

---

## 1. 测量方法与基线

### 1.1 环境与方法

- 机器：Apple M1 Max / 64 GB / macOS 26.6.2；Swift 6.3.3；`swiftc -O`。
- **可复现**：`./scripts/perf-bench/run.sh`（本次新增）。它把 `LibraryStore.filteredPins`、`boardSummaries`、`persist()`、`CantaJSON`、`thumbnailURL` 的原样逻辑，编译进**真实的 `Pin` 模型**（`Sources/Canta/Store/Models.swift` + `Localization.swift`）后测量。
- 合成图库字段长度贴近真实数据（标题 20–40 字符、备注 ~150 字符、5 个标签、5 个画板）。
- **能测的**：数据层、JSON、文件系统、ImageIO 解码/内存——本文所有毫秒数均为直接测量。
- **不能测的**：SwiftUI body 求值与布局。这些数字在文中标注「估算」，并给出确认方法（第 6 节埋点）。所有 UI 级结论都可用「组件实测 × 结构推断」复核。

### 1.2 基线：`filteredPins` 与一次 body pass

| N | `filteredPins`（全部/按时间） | 按画板过滤 | 搜索（3 个词） | **模拟 LibraryView body 数据层** | 换画板数据层 | ←/→ 换图数据层 |
|---:|---:|---:|---:|---:|---:|---:|
| 200 | 0.52 ms | 0.13 ms | 3.09 ms | 1.72 ms | 0.20 ms | 0.53 ms |
| 1 000 | **3.17 ms** | 0.76 ms | **15.45 ms** | **10.51 ms** | 0.94 ms | 3.20 ms |
| 3 000 | 8.90 ms | 1.89 ms | 46.84 ms | 29.44 ms | 2.78 ms | 9.03 ms |
| 5 000 | 14.32 ms | 4.37 ms | 78.95 ms | 50.02 ms | 5.30 ms | 14.77 ms |

> 「模拟 body」= 3 次 `filteredPins` + `favoriteCount` + `screenshotCount` + `boardSummaries` + 每个画板找代表。**真实视图读 5 次** `filteredPins`（`LibraryView.swift:44,55,170,199,200`），选择模式下 `BatchActionBar` 还会通过 `allVisibleSelected` / `selectedPinsAreFavorites` 再触发 2–3 次；详情浮层自己再读 2–3 次。

关键结论：**N=1000 时，单次 body 的数据层就已经吃掉 10 ms 以上**，而这只发生在一次「敲键/点卡/换画板」的开始；随后还有 N 张卡片的 body 与两遍布局。

### 1.3 基线：持久化

| 操作 | N=1 000 | N=3 000 |
|---|---:|---:|
| `JSONEncoder`（`.prettyPrinted + .sortedKeys`） | 13.7–14.1 ms | 43.1 ms |
| `Data.write(.atomic)` | 0.7 ms | 1.3 ms |
| **`persist()` 合计（主线程）** | **15.3 ms** | **44.8 ms** |
| 产物大小 | 928 KB | 2.8 MB |

`PinDetailView` 的 `titleBinding` / `noteBinding`（`:781-797`）每个字符都调用 `updatePin` → `persist()`。**在 3k 图库里打字，每敲一个字阻塞主线程约 45 ms**，同时全库 `@Published` 触发 N 张卡片重渲染。

### 1.4 基线：加载 / Agent 写回

| 操作 | N=1 000 | N=3 000 |
|---|---:|---:|
| 当前解码（`ISO8601DateFormatter` 策略） | **72–75 ms** | **219–223 ms** |
| 其中日期解析（2 个日期/pin） | 58–60 ms | 180–181 ms |
| 手写 ISO-8601 解析后的解码 | **8.6 ms** | ~26 ms（按同比例） |

- `ISO8601DateFormatter.date(from:)`：**33 µs/次**；手写 20 字节定点解析：**0.07 µs/次**（约 450×）。
- 磁盘上的格式完全不变（仍是 `2026-11-13T09:12:00Z`），只是换解析器，**API 契约零变化**。
- 启动时 `SeedLoader.installIfNeeded`（`SeedLoader.swift:45-48`）先解码一次判断是否需要播种，`LibraryStore.init`（`LibraryStore.swift:61-62`）再解码一次——**冷启动解码两次，且都在主线程**。

### 1.5 基线：图片

| 操作 | 实测 | 说明 |
|---|---:|---|
| `NSImage(contentsOfFile:)` 3200×2400 PNG | **1.7 ms** | 只读头，**懒解码** |
| 首次绘制到 476×357（新 NSImage） | **68.4 ms** | 解码发生在**调用绘制的一方**——App 里就是主线程 |
| 同一 NSImage 第二次绘制 | 0.09 ms | 已缓存，所以「第一次卡，之后顺」 |
| `CGImageSource` 全解码 3200×2400 | 59–61 ms | |
| `CGImageSource` 取 476 px 缩略图（从 3200 原图） | **70.1 ms** | PNG 没有 DCT 缩放路径，**不比全解码快** |
| 全解码已存的 1200×900 JPEG（卡片当前路径） | 3.2–3.4 ms | 1200 px 对 238–300 pt 卡位是 4–6× 过大 |
| 从 1200 px JPEG 取 476 px（理想路径） | 3.8–3.9 ms | 仍不如直接预生成 640 px |
| 解码位图大小：3200×2400 / 1200×900 / 476×357 | 29 MB / 4.1 MB / **0.65 MB** | `w × h × 4` |
| 实测驻留：6 张原图尺寸 / 200 张 476 px / 200 张 240 px | +245 MB / +134 MB / +20 MB | 即 41 MB、0.67 MB、0.10 MB/张（略高于理论值，含 CGContext 对齐/开销） |

`ImageCache`（`Components.swift:249-264`）`countLimit = 220`、**没有字节上限**：最坏 220 × 4.1 MB ≈ 900 MB 的解码位图；超过 220 张后开始抖动，往回滚动会重新解码。

### 1.6 基线：每卡文件系统与候选优化

| 操作 | 实测 |
|---|---:|
| `fileExists` × 1 000（热） | 2.6 ms |
| `thumbnailURL(path)+fileExists` × 1 000 卡 | **4.2 ms** | 
| 快照投影构建（仅搜索键）@1k / 3k / 5k | 6.7 / 21.1 / 34.4 ms（一次性，可后台） |
| 快照投影构建（+ 单词倒排）@1k / 3k / 5k | 26.8 / 80.8 / 133.3 ms（一次性，可后台） |
| 冷搜索查询（无倒排）@1k / 3k / 5k | 5.6 / 16.4 / 26.9 ms |
| 冷搜索查询（单词倒排）@1k / 3k / 5k | **1.8 / 4.9 / 7.8 ms** |
| 同一查询 memo 命中 | **0.0001 ms** |

---

## 2. 根因拆解

### 2.1 [P0] 观察粒度反了：17 个 `@Published` × 每张卡订阅整库

**证据**

- `LibraryStore.swift:9-28`：`pins`、`section`、`selectedBoard`、`searchText`、`filter`、`sort`、`selectedPinID`、`isSelectingPins`、`selectedPinIDs`、`capturePresented`、`isImporting`、`toast`、`startupError`、`agentStatus`、`agentPort`、`agentAPIEnabled`、`defaultBoard`——**17 个独立状态共用一个 `objectWillChange`**。
- `PinCard.swift:7`：`@EnvironmentObject private var store: LibraryStore`，并在 `:17,29,47,50,59,66,69,74` 读取 store。
- `RootView.swift:35-39`：详情浮层是叠在网格之上的 overlay，网格**始终在树里**。

**机制**

`@EnvironmentObject` 的契约是「订阅该对象的 `objectWillChange`」。任一 `@Published` setter 都会通知所有订阅者。于是：

- 在搜索框敲一个字 → 全部 N 张卡片 body 重新求值；
- 点开一张卡（`selectedPinID`）→ 全部 N 张卡片重新求值；
- 勾选一张卡（`selectedPinIDs`）→ 全部 N 张重新求值 + 全网格动画；
- 弹一个 toast、Agent 状态变化、端口变化 → 同样全部重算。

`PinCard` 需要的其实只有「这个 pin 的值 + 我是否被选中 + 是否选择模式」。它却订阅了整个库。

**N 缩放**：每次状态写入 = **N × 单卡 body 成本**。外部审计用 TextKit 做的代理测量约为 **0.1 ms/卡/次文本测量**（数量级参考，须用 Instruments 确认）；1 000 张卡就是 100 ms 级，加上下面的布局两遍测量。

**修法（P0）**

1. 叶子**只拿值 + 动作**，不拿 store：

```swift
struct PinCard: View, Equatable {
    let model: PinCardModel        // 值类型：id/title/board/boardColor/pixelLabel/aspectRatio/thumbPath/isFavorite
    let isSelected: Bool
    let isSelecting: Bool
    let actions: CardActions       // 闭包，不可变，不触发观察

    static func == (l: Self, r: Self) -> Bool {
        l.model == r.model && l.isSelected == r.isSelected && l.isSelecting == r.isSelecting
    }
}
// 调用处：PinCard(...).equatable()
```

2. `store` 迁移到 `@Observable`（macOS 14 可用），把「快照 / 查询 / UI 状态」拆成三个对象（见 3.1），让视图只追踪自己真正读到的属性。
3. 动作通过 `EnvironmentKey` 注入一个**永不发布**的 `CantaActions` 结构（open/toggle/select），避免闭包破坏 `Equatable`。

**验收**：Instruments 里「点一次卡」的 `View Body` 次数从 ≈N 降到 **个位数 + 可见卡数**。

### 2.2 [P0] 派生数据在 body 里现算，且被反复读

**证据**

- `LibraryStore.swift:89-138`：`filteredPins` 每次访问都复制数组、过滤、按 7 个字段拼搜索串并 `lowercased`、排序。
- 读取点：`LibraryView.swift:44`（空态）、`:55`（ForEach）、`:170`（计数）、`:199-200`（Select 按钮的 disabled/opacity）——**5 次**；`BatchActionBar.swift:15-19,29-30`；`PinDetailView.swift:41,146-147`；`LibraryStore.swift:262`（换图）、`:78,82`（批量派生）。
- `boardSummaries`（`:140-149`）在 `SidebarView.swift:39,45,48` 被读 **3 次**。
- `selectedPin`（`:72-75`）是线性扫描，`RootView` 每次 body 都会调用。

**N 缩放**：`body 次数 × O(N log N)`。1k 时一次 body 10–17 ms；5k 时 50–80 ms。**换画板/换图/搜索都会触发多次 body**。

**修法（P0）**

- 引入不可变 `LibrarySnapshot`：`pins`、`indexByID: [UUID: Int]`、预计算 `searchKey` / `boardKey` / `createdAt`、`favoriteIndices`、`screenshotIndices`。
- `GalleryProjection.visibleIDs(for: QueryKey)` 带 memo：**一次交互只算一次**，body 里读到的是数组（O(1)）。
- `selectedPin` → `snapshot.pin(id:)`（字典查找）；`boardSummaries` / `allTags` / `allBoardNames` 按 `snapshot.revision` 缓存。
- 搜索键在**加载时后台**构建（6.7 ms/1k，34 ms/5k），或首搜时惰性构建。

**实测收益**：memo 命中 **0.0001 ms**（vs 3.2–14.3 ms）；冷查询加倒排后 1k/3k/5k 为 **1.8/4.9/7.8 ms**。

### 2.3 [P0] 网格完全非懒加载，且 Layout 把每张卡测两遍

**证据**

- `LibraryView.swift:49-59`：`MasonryLayout { ForEach(store.filteredPins) { PinCard } }` 放在 `ScrollView { VStack }` 里。
- 全仓库没有 `LazyVStack` / `LazyVGrid` / `List`（可自行 `grep` 复核）。
- `MasonryLayout.swift:31-35`（`sizeThatFits` 遍历全部 subview 测尺寸）与 `:47-48`（`placeSubviews` 再测一遍）——**每张卡两次测量**；`cache: inout ()` 意味着没有任何缓存。
- 每张卡内嵌 `LibraryImage`（`PinCard.swift:38`），其 `.task`（`Components.swift:297`）在出现时立即启动**无并发上限**的解码任务；卡片是全部实例化的，所以**一次首帧会同时启动 N 个解码**。

**机制**：`ScrollView + VStack + ForEach` 本身就会实例化全部子视图；再套一个自定义 `Layout`，又会保证「先测一遍、摆放时再测一遍」，且没有缓存。卡片高度本可由 `aspectRatio` 解析计算，却被交给文本测量并重复两遍。首帧、换画板、列表变化都 O(N)。

**修法（P0，1–3 天）**

1. 标题改为 `.lineLimit(2, reservesSpace: true)`，让题注高度**固定**；卡片高度 = `列宽 / aspectRatio + 固定题注高度` —— 可**纯算术**预计算。
2. 按「最短列优先」O(N) 分配 K 列；每列一个 `LazyVStack`（`HStack(alignment: .top)` 包裹）。这样只有可见卡被实例化/测量。
3. 网格不再使用 `MasonryLayout`（`FlowLayout` 保留给标签）。

```swift
struct MasonryColumns: View {
    let columns: [[PinCardModel]]      // 由 Projection 按宽度 + 高度预分列
    let spacing: CGFloat
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { i in
                LazyVStack(spacing: rowSpacing) {
                    ForEach(columns[i]) { model in
                        PinCard(model: model, ...).equatable()
                    }
                }
            }
        }
    }
}
```

4. 若 1 万级仍抖动，进入 P1：`NSCollectionView` + 自定义 `NSCollectionViewLayout`（真正的复用、`prepareForReuse`、visible-rect 预取、图像直接挂 `CALayer`），SwiftUI 只保留 chrome。

**验收**：1000 张库首帧实例化卡片数 ≈ 可见卡（30–60）；滚动丢帧 <3%。

### 2.4 [P0] 详情加载原图，且「后台解码」实际没把解码挪走

**证据**

- `PinDetailView.swift:125`、`:243`：`LibraryImage(path: store.originalURL(for: pin).path)`——**跳过已有缩略图，直接读原图**。
- `Components.swift:304-306`：`Task.detached { NSImage(contentsOfFile: path) }`。
- `ImageCache`（`:249-264`）按路径缓存 `NSImage`，`countLimit = 220`，无字节上限。

**机制**

`NSImage(contentsOfFile:)` 只解析头部就返回（实测 **1.7 ms**），真正的解码发生在 **`Image(nsImage:)` 绘制时**——在 App 里就是主线程（实测 **68 ms**，3200×2400）。所以 `Task.detached` 只挪走了 1.7 ms，把 68 ms 留在了最关键的第一次绘制上；并且每次 ←/→ 换图都重来一次。顺带上传 29–41 MB 的纹理。

**修法（P0，2 天）**

1. **资产分档**（不破坏现有 API 对 `Thumbnails/` 的语义）：
   - `Cards/` **640 px**（新增，网格专用；2× 最大列宽）；
   - `Thumbnails/` **1200 px**（保持不变；详情首帧 + Agent API 的 `thumbnailURL`）；
   - `Images/` 原图（仅大图模式/放大时渐进加载）；
   - 可选 `Previews/` 1600 px（若要 2× 全屏更锐，再补一档）；
   - 可选 `Icons/` 64 px（侧栏画板缩略图）。
   理由：实测 1200 px 解码 3.2 ms、4.1 MB，详情一次只看一张，完全够用；网格才需要 640 px（0.65–1.2 MB）。少生成一档就少一份迁移成本与磁盘占用。
2. **真正的后台解码**：在 detach 的任务里用 ImageIO 直接得到**目标像素**的 `CGImage`：

```swift
CGImageSourceCreateThumbnailAtIndex(source, 0, [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceThumbnailMaxPixelSize: targetPixels,
    kCGImageSourceShouldCacheImmediately: true,     // 关键：在本线程完成解码
    kCGImageSourceCreateThumbnailWithTransform: true
] as CFDictionary)
```

   注意：**不要**在绘制路径上对原图临时取缩略图——实测从 3200 px PNG 取 476 px 要 **70 ms**，比全解码还慢（PNG 没有 DCT 缩放路径）。正确做法是**导入时就生成小图**（见 3.3）。
3. 视图用 `Image(decorative: cgImage, scale: 2)`，缓存 `CGImage` 并带 `cost = w*h*4`。
4. 详情：先出 1200 缩略图（后台解码，3.2 ms/4.1 MB），大图模式或停留 >300 ms 再渐进替换原图；打开时预取 ±1 张缩略图。
5. 背景遮罩从 `.ultraThinMaterial` 换成实色（材质会对**正在动画的整张网格**做逐帧采样，`PinDetailView.swift:22-24`）。

**验收**：详情打开可见 ≤100 ms（热缓存 ≤1 帧）；←/→ ≤1 帧（预取命中）。

### 2.5 [P0] 每个按键全量持久化，且在主线程

**证据**：`PinDetailView.swift:781-797`（title/note 的 Binding setter）→ `LibraryStore.swift:406-413`（`updatePin`，`:412` 调 `persist()`）→ `:851-860`（全量编码 + 原子写）。

**实测**：N=1000 **15.3 ms/按键**，N=3000 **44.8 ms/按键**；文件 928 KB / 2.8 MB。`.prettyPrinted` 只占约 2 ms —— **问题在频率和线程，不在格式标志**。

**修法（P0，1 天）**

- 编辑先落 `@State` 草稿，**300–600 ms debounce** 后写；失焦 / 切换 pin / 关闭详情 / 退出应用时 **flush**。
- 单写者 actor（或串行队列）在后台编码并 `.atomic` 写；用递增 generation 丢弃过期写；同一时刻最多一个 in-flight 写。
- `CantaJSON.encoder/iso8601` 这类静态实例**不要跨线程共用**（`JSONEncoder` 非线程安全），写线程内自建实例。
- 可选 P2：SQLite（系统 `import SQLite3`，无第三方依赖）作为真源，`library.json` 仅作导出；或 append-only journal + 周期压缩。**这属于存储架构升级，不属于本次止血**。

### 2.6 [P1] 缩略图过大 + 缓存按数量而非字节

**证据**：`ImageProcessor.swift:92` `maxPixel: 1200`；`Components.swift:254` `countLimit = 220`。

**机制**：卡宽 238–300 pt，@2x 只需 476–600 px；1200 px 是 4–6× 像素量（4.1 MB vs 0.65 MB 位图）。缓存按张数而非字节，最坏 ~900 MB；除了解码慢，还会在低内存机器上触发大量内存压缩/交换——**这正是「卡片一多整台机器都卡」的另一半原因**。

**修法（P0/P1）**：卡片档 640 px + 图标档 64 px；`NSCache.totalCostLimit = 128 MB`，`setObject(..., cost: bytes)`；删除 pin 时移除缓存；监听 `NSApplication.didResignActive`/内存压力清空。

### 2.7 [P1] 动画作用域过大

**证据**：`LibraryStore.swift` 中 13 处 `withAnimation`（`:230,241,250,256,267,299,308,315,325,331,627,837,845`）；`RootView.swift:78-79` 对 `selectedPinID` 做**全窗口** spring 动画；`LibraryView.swift:62` 的 `.animation(value: store.currentListIdentity)`（identity 含 `searchText`，`:210-212`）、`:63`、`:57` 的每卡 transition、`:24`。

**机制**：`withAnimation` 给「这次状态变化导致的所有重渲染」套上动画交易。于是搜一个字 → 0.32 s 全网格动画 + 每卡 insert/remove transition；开详情 → 侧栏、网格、材质背景一起动；加一张卡 → 所有卡片位移动画。

**修法（P0，0.5 天）**：store 层**不做**动画；只在呈现边缘（overlay、批量条、标题数字）用 `.animation(value:)`；删掉每卡 transition；`currentListIdentity` 只驱动数据重算与 `scrollTo`，不驱动动画。

### 2.8 [P1] 详情浮层让背后整张网格保持活着

**证据**：`RootView.swift:35-39`（overlay 覆盖在 `SidebarView + LibraryView` 上）；`PinDetailView.swift:22-24`（全屏 `.ultraThinMaterial`）；`:96-118`（48 px 阴影 + `compositingGroup`）。

**修法**：详情改为独立 `NSWindow`/sheet，或至少冻结背景（`.disabled(true)` + 缓存快照）；去掉 `compositingGroup` 与大半径阴影，遮罩用纯色。P1 再做窗口化。

### 2.9 [P2] 启动重复解码；ISO-8601 解析占解码 80%

**证据**：`SeedLoader.swift:45-48` 解码一次，`LibraryStore.swift:61-62` 再解码一次；`CantaPaths.swift:56-66` 的 `.custom` 日期策略。

**实测**：75 ms @1k、219 ms @3k 主线程解码；其中 60/180 ms 是 `ISO8601DateFormatter`（33 µs/次）。换成手写定点解析 → **8.6 ms @1k**（8×），磁盘格式不变。

**修法（P0，0.5 天）**：`installIfNeeded` 返回已解码结果或 `Data`，只解码一次；解码移到后台，先渲染窗口再填充；手写 ISO-8601 解析器（附录 B）。

> 同一问题也在 Agent API：`CantaAgentKit/Library.swift:389-402` **每个请求**都重新读 + 解码 `library.json`。修成「内存快照 + FSEvents 失效」后，`GET /api/v1/pins` 可从 ~60 ms 降到 <2 ms。这不在本次 UI 卡顿主路径，但 Agent 频繁读取时会抢 IO/CPU。

### 2.10 [P2] 其他值得顺手处理的点

| 点 | 位置 | 处理 |
|---|---|---|
| 侧栏 3 次 `boardSummaries` | `SidebarView.swift:39,45,48` | body 顶部算一次 `let`，或投影缓存 |
| 每卡 `fileExists` | `LibraryStore.swift:218-224` + `PinCard.swift:38` | 快照里预计算缩略图路径；导入时已保证存在，失败再回退 |
| 侧栏每行 O(N) 找代表 | `SidebarView.swift:119` | 快照维护 `board -> representativeID` 字典 |
| 常驻 `repeatForever` 动画 | `TopBarView.swift:114-118` | 仅在 API running 时启动，停止时取消 |
| `DateFormatter` 每次新建 | `Theme.swift:86-92` | 详情里仅 0.04 ms，属打磨；`agentSnippet` 每 pin 一次，批量复制时改用 `Date.FormatStyle` |

---

## 3. 目标架构

### 3.1 三层数据流

```
            导入 / Agent 写回 / 编辑
                      │
        ┌─────────────▼──────────────┐
        │  LibrarySnapshot（值类型）  │  pins + indexByID + searchKey/boardKey
        │  不可变 · 后台构建          │  favorite/screenshot 索引 · revision
        └─────────────┬──────────────┘
                      │
        ┌─────────────▼──────────────┐
        │ GalleryProjection          │  visibleIDs(for: QueryKey) 带 memo
        │ 查询参数 → 排好序的 ids     │  boardSummaries / allTags 按 revision 缓存
        └─────────────┬──────────────┘
                      │  只读值
        ┌─────────────▼──────────────┐
        │ AppState（@Observable）    │  searchText / selectedPinID / selectedPinIDs
        │ 极小的 UI 状态             │  isSelectingPins / toast / agentStatus
        └─────────────┬──────────────┘
                      │
   RootView → LibraryView（懒列） → PinCard(model:isSelected:isSelecting:).equatable()
                      └→ DetailOverlay（独立小状态）
```

**规则**

1. 视图只读自己需要的属性；`@Observable` 按属性追踪，改 toast 不会让卡片重算。
2. 叶子视图**只接收值**，不接收 store；动作通过不发布变更的 `CantaActions`（`EnvironmentKey`）注入。
3. 所有派生数据都在投影里算一次并缓存；body 里不做 O(N) 工作。
4. 数据层抽成 **`CantaCore` library target**（不依赖 SwiftUI）：可单测、可基准、可被未来的 Rust 实现替换——这是语言重构的唯一切入点（第 5 节）。

### 3.2 渲染层

- **阶段 A（P0）**：按列 `LazyVStack` + 高度算术预计算 + `reservesSpace` + `Equatable` 卡片。改动集中在 `LibraryView.swift` / `PinCard.swift` / 新增 `MasonryColumns.swift`。
- **阶段 B（P1，条件触发）**：`NSCollectionView` + 自定义布局。收益：真正的视图复用、visible-rect 预取、图像直接挂 layer、无 SwiftUI 布局开销。代价：1–2 周、键盘/无障碍需补齐。触发条件：5k+ 卡片滚动 p95 帧时间 >20 ms，或需要每屏 >200 卡。

### 3.3 图片管线

```
导入 ──> Images/原图（不变）
      ├─> Cards/640px       (网格；新增)
      ├─> Thumbnails/1200px (详情首帧 + Agent API；现状)
      ├─> Previews/1600px   (可选：2× 全屏)
      └─> 调色板（44px 采样，现状即可）

渲染 ──> ImageLoader(actor)
          · 有界并发 4–6，按路径去重，可取消
          · ImageIO 直接解到目标像素 + shouldCacheImmediately
          · NSCache<NSString, CGImageBox>，cost = 字节，上限 128 MB
          · 卡片 .utility；详情 .userInitiated；±1 预取
```

- **迁移**：旧库没有 `Cards/`。启动后后台任务（串行、节流、可续、仅空闲时跑）从现有 1200 px 缩略图生成 640 px（约 1–2 ms/张；1 万张 ≈ 20–40 s），失败则回退到 `Thumbnails/`。`Previews/` 是按需增强，不做强制回填。
- **不要**在主线程或绘制路径上临时缩放大图（实测从 3200 px 取 476 px 要 70 ms/张）。
- 详情渐进：`Thumbnails/1200` 立即显示 →（进入大图模式或停留 >300 ms）→ 后台载入原图并交叉淡入。

### 3.4 持久化

```swift
@MainActor final class LibraryWriter {
    private let queue = DispatchQueue(label: "canta.library-writer", qos: .utility)
    private var pending: DispatchWorkItem?
    private var generation = 0

    func schedule(_ snapshot: [Pin], debounce: TimeInterval = 0.45) {
        pending?.cancel()
        generation += 1
        let gen = generation
        let snapshot = snapshot
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen else { return }
            let encoder = Self.makeEncoder()      // 不跨线程共享
            guard let data = try? encoder.encode(CantaLibrary(version: 1, pins: snapshot)) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    func flush() { /* 同步等待最后一次写完成，退出/失焦时调用 */ }
}
```

- `library.json` **格式不变**，API 兼容；`.prettyPrinted` 可保留（约 2 ms），也可只在 Debug 开启。
- 真正的存储升级（SQLite WAL）放到 P2：它是「写放大/多进程一致性」的解，不是本次卡顿的解。

### 3.5 搜索

- 加载时预计算小写、NFC 归一的 `searchKey`（标题/备注/画板/本地化画板/来源/标签/类型）。
- 查询 memo：`QueryKey(section, board, filter, sort, needle, language, revision)`。
- 过滤用 **UTF-8 字节扫描**（预计算 `searchKeyBytes` + `memmem`）：合法 UTF-8 上的字节子串匹配等价于字符子串匹配，且比 `String.contains` 快一个数量级。实测冷查询 1k/5k/10k = **0.28 / 1.88 / 4.79 ms**。
- 输入 debounce：>4000 张时 40 ms，其余即时；5k 以下每个按键的总数据层成本 <3 ms。
- **升级阈值**：>50k 或需要排序/模糊/多语言分词 → SQLite FTS5（系统自带）或 trigram/倒排。实测 5k 线性字节扫描已远低于 16 ms 目标，倒排在这里是过度设计。

### 3.6 动效原则

- 动画只写在**要动的那个视图**上，不写在 store 或根视图；
- 列表增删不做全量位移动画（卡片进出用 ≤120 ms 的 opacity）；
- 详情开合用 opacity + 轻微 scale，时长 200–240 ms；
- 逐帧材质（`.ultraThinMaterial`）不与动画叠加。

---

## 4. 路线图与验收

### 4.0 如果只有 2–3 天：最小止血包

按「改动小、风险低、用户立刻能感觉到」排序，全部不碰数据格式：

| # | 改动 | 大致位置 | 立刻收益 |
|---|---|---|---|
| Q1 | 普通详情的图改用 `store.thumbnailURL(for:)`（1200 px）而不是 `originalURL`；大图模式（`:125`）仍保留原图 | `PinDetailView.swift:243` | 详情/换图从 **68 ms 解码**降到 **3.2 ms**（一行改动） |
| Q2 | `persist()` 加 400 ms debounce + 后台串行写 | `LibraryStore.swift:406-413,851-860` | 打字不再每字阻塞 **15–45 ms** |
| Q3 | 去掉 `currentListIdentity` 驱动的全网格动画与每卡 transition | `LibraryView.swift:57,62` | 搜索/换画板不再整屏动画 |
| Q4 | `ImageCache` 改为 `totalCostLimit`（~128 MB）并按字节计费 | `Components.swift:249-264` | 卡片多时不再堆积近 GB 解码位图 |
| Q5 | `thumbnailURL` 去掉每卡 `fileExists`（失败再回退） | `LibraryStore.swift:218-224` | 每次 body 省 2.6–4.2 ms/1000 卡 |

> 这 5 项预计 2–3 天、约 300 行以内的改动，且都能独立回滚；它们不替代 P0，但能把「明显卡」变成「偶尔卡」，为后续重构争取时间。

### 4.1 P0 —— 止血（约 10 个工作日）

| # | 改动 | 主要文件 | 预期收益 | 验收 |
|---|---|---|---|---|
| 0 | **埋点**：`OSSignposter` + 帧间隔 HUD + 合成图库生成器 | 新增 `Performance.swift` | 让后面每一项都可量化 | 每次交互可导出：body 次数、查询/写盘/解码耗时、掉帧 |
| 1 | **快照 + 投影**：`LibrarySnapshot`、`QueryKey` memo、索引 | 新增 `CantaCore/Snapshot.swift` 等 | body 数据层 10–50 ms → **<0.6 ms** | 1k 卡 body 数据层 <1 ms |
| 2 | **卡片值化**：`PinCardModel` + `Equatable` + actions 注入 + `@Observable` | `PinCard.swift`、`LibraryView.swift`、`LibraryStore.swift` | 每次写入的 body 数 N → 个位数 | 点卡/选择时 Instruments body 次数 ≤ 可见卡 |
| 3 | **懒列网格**：列分配 + `LazyVStack` + `reservesSpace` | `LibraryView.swift`、新增 `MasonryColumns.swift` | 首帧实例化 N → ~40 | 1k/5k 首帧 <100 ms |
| 4 | **持久化**：草稿 + debounce + 后台单写者 | `PinDetailView.swift`、新 `LibraryWriter` | 每按键 15–45 ms → **0 ms 主线程** | `fs_usage` 无逐键写；标题输入帧率平稳 |
| 5 | **图片分档 + Loader**：Cards/640、详情用现有 1200、后台解码、字节上限缓存、预取 | `ImageProcessor.swift`、`Components.swift`、新 `ImageLoader.swift` | 卡片解码 3.2 ms→<0.6 ms；详情 68 ms→<5 ms（1200 档） | 详情打开 ≤100 ms；←/→ ≤1 帧 |
| 6 | **启动**：单次解码 + 快速 ISO-8601 | `SeedLoader.swift`、`LibraryStore.swift`、`CantaPaths.swift` | 启动解码 75 ms→9 ms @1k | 冷启动到可交互 ≤800 ms @5k |
| 7 | **动效收口** | `LibraryStore.swift`、`RootView.swift`、`LibraryView.swift` | 去掉全网格动画 | 搜字/换画板无整屏动画 |
| 8 | **回归** | — | — | 见 4.4 |

**M1 里程碑门槛（1k 卡片，M1 Max 基准，Intel/Air 允许 2×）**

- 点详情：p95 **≤50 ms**，无 >100 ms 主线程阻塞；
- ←/→：预取命中时 **≤16.7 ms**；
- 换画板：**≤40 ms**；
- 搜索每个字符：**≤8 ms**（数据层 <1 ms + 视图 diff）；
- 常驻内存 **≤400 MB**；图片缓存 ≤128 MB；
- 滚动：平均 ≥55 fps，丢帧 <5%。

### 4.2 P1 —— 规模（2–3 周）

1. **已完成**：搜索改为 UTF-8 字节扫描 + 40 ms 防抖（5k 1.9 ms）；
2. **已完成**：API 文件版本缓存 + 响应 LRU（GET `/pins` 1.2 ms、`/library` 1.4 ms）；
3. **已完成**：`@Observable` 迁移 + `DetailLayer/CaptureLayer/ToastLayer` 隔离（打开详情不再重算网格）；
4. **已完成**：`scripts/perf-guard.sh` 自动性能门禁；
5. **未触发**：`NSCollectionView` 渲染层（需要真实 10k 库的滚动 p95 证据；当前 10k 冷启动 0.82 s、数据层均达标）；
6. **不做**：详情独立窗口（隔离后网格已不重算，overlay 只做合成）；回填进度与 HUD 记录为可选打磨。

**M2 门槛**：1 万卡片下点详情 ≤80 ms、换画板 ≤120 ms、滚动 ≥50 fps、内存 ≤800 MB、冷启动 ≤1.2 s。

### 4.3 P2 —— 可选（按需）

- SQLite WAL 真源 + 导出 `library.json`；
- Rust 内核（第 5 节）；
- 跨平台。

### 4.4 验证方法（每个 PR 都要能跑）

1. **数据层**：`./scripts/perf-bench/run.sh`（本次已入库），对比改动前后。
2. **UI 层**：Instruments 模板（SwiftUI View Body / Animation Hitches / Hangs / Time Profiler），固定动作序列：打开详情 → ← ×10 → 标题输入 6 字 → 换画板 → 搜索 8 字。
3. **合成图库**：`CANTA_HOME=/tmp/canta-bench-5k ./dist/Canta.app/Contents/MacOS/Canta`，用脚本生成 1k/5k/10k 三档。
4. **文件写入**：`fs_usage -w -f filesys Canta`，确认按键不再逐键写。
5. **回归清单**：详情 ←/→ 首尾边界、搜索清空、选择模式、拖拽导入、Agent 写回后 UI 刷新、语言切换。

---

## 5. Rust 重构评估

### 5.1 为什么 UI 层不能（也不该）用 Rust

- Canta 的 UI 是 SwiftUI + AppKit（材质、`NSWindow`、跟踪光标、输入法、无障碍、`SettingsLink`）。Rust 没有可用的 macOS 原生 UI 栈；重写意味着重新实现整个交互层，**6–12 人月**（估算）起，且会失去现有 **154 项** API 冒烟测试与签名打包链路。
- 更关键：本次四个症状的主线程预算是「view body 求值 + 布局 + 状态无效化」。这些**只发生在 SwiftUI 内部**，Rust 代码再快也进不了这条路径。
- 本机**没有安装 `rustc`/`cargo`**（已确认），本次未做任何 Rust 基准；下文的 Rust 数字全部标注为**估算**。

### 5.2 候选子系统矩阵

| 子系统 | 在交互热路径？ | 值得换语言？ | 判定 | 说明 |
|---|---|---|---|---|
| 图片解码/缩放/编码 | 是（详情/滚动） | 否 | **保留 Swift + ImageIO** | ImageIO 有硬件路径与 HEIC/RAW；Rust `image` 不解 HEIC；公开基准里 `zune-jpeg` 约 10 ms/图，未见优于 ImageIO 的证据（估算，未在本机验证） |
| 缩略图批量生成 | 否（导入/回填） | 现在不值得 | **保留**；可选离线 worker | 同一条 ImageIO 调用，换语言无收益 |
| 调色板提取 | 否（导入） | 不值得 | **保留** | 1.2 ms/张（44 px 采样），1 万张后台约 12 s，已成非问题 |
| EXIF/元数据 | 否 | 否 | **保留** | ImageIO properties 已够 |
| JSON 编解码/持久化 | **是**（每次按键） | 否（换机制） | **换机制，不换语言** | 手写日期解析 8×；debounce + 后台写；P2 可 SQLite。serde 不会比 `JSONDecoder` 快 20× 到值得引入 FFI |
| 搜索/过滤/排序/索引 | 是（每次按键） | 1 万以内不值得 | **Swift 倒排**；>50k 再评估 | 实测倒排冷查询 1.8–7.8 ms；memo 命中 0.0001 ms |
| HTTP API 服务 | 否（但会抢 IO） | 否 | **保留 Network.framework** | 瓶颈是每请求重读+解码，改成快照即可 |
| 跨平台内核（未来） | — | 可能 | **观察** | 若将来要 Windows/Linux，Rust core + 平台壳才是合理形态 |

### 5.3 如果要做 Rust：三种集成方式

| 方式 | 打包/签名 | 边界成本 | 适用 |
|---|---|---|---|
| **staticlib + C 头 + modulemap** | 链接进同一 Mach-O，一次签名/公证 | ~2–10 ns/调用（估算） | **单 .app 首选** |
| `cdylib` | 需放进 `Contents/Frameworks` 单独签名，`--deep` 不可靠 | +dyld 加载 1–3 ms | 不推荐 |
| **sidecar 进程（pipe/XPC）** | `Contents/Helpers` 独立签名/公证，崩溃隔离 | 100 µs–1 ms/往返 | **批处理首选**，绝不用于 UI |

工程细节（若批准）：

- 通用二进制：`cargo build --target {aarch64,x86_64}-apple-darwin` + `lipo -create`；`MACOSX_DEPLOYMENT_TARGET=14.0`。当前 `dist/Canta.app` 是 **arm64-only、ad-hoc 签名**（已核实），`scripts/build-app.sh` 里 `ARCH_DIR` 也写死了 arm64，需要先决定是否做通用包。
- Swift 6 并发：`Package.swift` 目前是 `swiftLanguageModes: [.v5]`。跨边界指针不得逃逸 `withUnsafeBytes`；句柄用 `actor` 包裹；Rust 回调必须 `@Sendable` 并显式跳 `@MainActor`。
- 错误与 panic：`panic = "abort"` + 边界 `catch_unwind`；错误用 `(Int32, *const c_char)` 或 JSON envelope，**不要在 ABI 传 Swift `String`**。
- **绝不在 SwiftUI body 里跨 FFI**。1 万卡 × 60 Hz × 1 µs = 600 ms/s；批处理（每 64 张一次调用）或异步投递。

### 5.4 唯一建议的 Rust 落点（如果一定要做）

**`canta-media`：离线批量媒体 worker（sidecar CLI）**

- 职责：为存量图库生成 `Cards/` 640 px（可选 `Previews/` 1600 px）、调色板重算、PNG/JPEG 优化；
- 收益面：批处理吞吐（可用满多核），以及未来跨平台复用；
- 不碰：UI、实时渲染、每帧/每次交互路径；
- 门禁：在 1 万张真实图库上，**比优化后的 Swift+ImageIO 批处理快 ≥1.5×**，且输出字节一致；否则放弃；
- 打包：`Contents/Helpers/canta-media`，独立签名/公证；宿主可缺省运行；
- 回滚：删除 helper，Swift 批处理路径保留。

**不建议**的落点：JSON/持久化（换 SQLite 更划算）、搜索（1 万以内 Swift 足够）、HTTP（重实现 154 项检查）、任何 UI。

### 5.5 什么时候重新评估 Rust

满足任意两条再立项：

1. 产品明确要求 **Windows/Linux**；
2. 单库 **>5 万张**，且搜索/索引成为可感知瓶颈（届时 tantivy/fst 有真实优势）；
3. 出现**服务端/无头**形态（团队共享图库、CI 里的设计上下文服务）；
4. 批处理媒体成为核心功能（批量重压、格式转换、视觉相似度），且 Swift 实现被实测证明不够快。

**决策记录**：本轮结论是「**先修 Swift 架构，语言问题后置**」。如果 P0 完成后仍有一项交互 p95 >100 ms，再带着新的 Instruments 证据讨论，而不是现在就重写。

---

## 6. 性能预算、埋点与回归

### 6.1 SLO（1k / 5k 卡片，M1 Max 基准，Intel/Air ×2）

| 指标 | 1k | 5k | 采集方式 |
|---|---|---|---|
| 点详情 p95 | ≤50 ms | ≤80 ms | signpost + 帧间隔 |
| ←/→ 换图（预取命中） p95 | ≤16.7 ms | ≤33 ms | 同上 |
| 换画板 p95 | ≤40 ms | ≤80 ms | 同上 |
| 搜索每字符 p95 | ≤8 ms | ≤16 ms | 数据层 + body |
| 主线程单次阻塞 p99 | ≤50 ms | ≤100 ms | Hangs/Animation Hitches |
| 滚动平均帧率 | ≥58 fps | ≥55 fps | 掉帧 <3% |
| 常驻内存 | ≤400 MB | ≤800 MB | `task_vm_info` |
| 图片缓存 | ≤128 MB | ≤128 MB | 自定义统计 |
| 冷启动可交互 | ≤800 ms | ≤1.2 s | signpost |
| 磁盘写 | 空闲时 ≤1 次/400 ms，且从不在主线程 | 同左 | `fs_usage` |

### 6.2 埋点设计

```swift
import os
enum Perf {
    static let sp = OSSignposter(subsystem: "studio.canta.library", category: "interaction")
    // 统一字段：N（库大小）、visible（可见卡）、tier（cards/thumb1200/original）、ms
}

// 关键区间
// canta.query.recompute      LibrarySnapshot/Projection
// canta.persist.encode/write
// canta.image.decode.{cards|thumb1200|original}
// canta.detail.open
// canta.card.body            （sample 1/64 卡，避免自身开销）
// canta.grid.layout
```

HUD（`⌥⌘P`，仅 Debug）：`N / 可见卡 / 最近一秒 body 次数 / 帧间隔 p95 / 图片缓存 MB / 上次写盘 ms`。

### 6.3 门禁

- `scripts/perf-bench/run.sh`：数据层回归（本次已入库）；P0 落地时把基线固化为 `docs/perf-baseline.json`，回归劣化 >20% 失败；
- `CantaCoreTests`：`XCTClockMetric` + `XCTMemoryMetric`（1k/5k 两档）；
- 发布前：Instruments 固定动作序列，导出 trace 存档；
- 代码评审红线：
  * body / `body` 调用的方法里不得有 O(N) 遍历、文件 IO、JSON、解码；
  * 叶子视图不得 `@EnvironmentObject` 整库；
  * 不得在 store 里 `withAnimation`；
  * 不得在主线程 `Data(contentsOf:)` / `encode` / `write`。

---

## 7. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| `reservesSpace` 让标题固定两行 | 视觉变化（卡片变高、单行标题留白） | 与设计确认；或按字符数估算行数（误差 ±1 行） |
| 懒列网格的列平衡与插入顺序 | 与旧布局不完全一致 | 用精确高度算术（不是估算），仅视觉近似；截图回归 |
| `@Observable` 迁移面较大 | 编译错误、少见的刷新遗漏 | 分 PR：先拆状态对象 → 再逐视图迁移；保留 `ObservableObject` 兼容期 |
| 缩略图格式迁移 | 磁盘占用 + 后台 IO | 后台节流、可续、只在空闲时做；旧文件保留直到新文件成功 |
| 图片缓存字节上限 | 快速滚动时重复解码 | 128 MB + 预取窗口；监控 hit rate，必要时调大 |
| 详情改独立窗口 | 键盘/焦点/关闭行为变化 | 先冻结背景，窗口化作为 P1 可回滚项 |
| 数据格式 | 任何改动都影响 API | **P0/P1 不改格式**；SQLite 迁移放 P2 且保留导出 |

**回滚策略**：每项独立 PR + 可开关（`UserDefaults` 调试开关或编译 flag）；P0 不改变磁盘与 API，回滚只需 revert 代码。

---

## 8. 实施记录（P0 落地）

> 2026-11-14 在真实代码上落地。构建：`./scripts/build-app.sh release`；API 回归：`./scripts/agent-smoke-test.sh`（154 项通过）。

### 8.1 已完成

| 方案条目 | 实现 | 关键文件 |
|---|---|---|
| P0-0 观测 | `OSSignposter`（query / models / write / image decode）；`--bench` 数据层基准 | `Performance/Perf.swift`、`Performance/DataLayerBench.swift` |
| P0-1 快照/投影 | `LibrarySnapshot`（`indexByID`、计数、画板/标签聚合、懒加载搜索键）+ `GalleryProjection`（查询 memo、卡片模型 memo） | `Store/LibrarySnapshot.swift` |
| P0-2 卡片值化 | `PinCardModel` + `PinCardActions`；`PinCard: Equatable`，不再持有 store | `Views/PinCard.swift` |
| P0-3 懒列网格 | `MasonryColumns`（每列一个 `LazyVStack`）+ 高度算术分配；删除 `MasonryLayout` | `Views/LibraryView.swift` |
| P0-4 持久化 | `LibraryWriter`：debounce + 单写者 + 后台编码 + generation 丢弃过期写；退出/失焦/关详情 flush | `Store/LibraryWriter.swift` |
| P0-5 图片管线 | `ImageLoader` actor（有界并发、128 MB 字节上限、目标像素解码）；`Cards/` 640 px 生成 + 后台回填；详情 1200 px、原图仅大图模式；±1 预取 | `Store/ImageLoader.swift`、`Store/CardThumbnailBackfill.swift`、`Design/Components.swift` |
| P0-6 启动 | `SeedLoader.loadOrInstall` 单次解码；手写 ISO-8601 解析 | `Store/SeedLoader.swift`、`Store/CantaPaths.swift` |
| P0-7 动效 | 移除网格容器动画与每卡 transition；详情遮罩去材质 | `Views/LibraryView.swift`、`Views/PinDetailView.swift` |

转入 P1 / 未做：`@Observable` 迁移（卡片已不订阅整库，剩余收益变小）、搜索倒排（5k 冷查询仍有 36 ms）、`NSCollectionView`、API 快照、详情独立窗口、HUD。

### 8.2 实测（同机同库）

1000–1001 pins 合成库：

| 指标 | 优化前 | 优化后 | 备注 |
|---|---:|---:|---|
| 冷启动到窗口出现（1 000 pins） | **6.3–6.5 s** | **0.68–0.87 s**（有 `Cards/`，三次）/ **1.28–1.32 s**（无 `Cards/` 首次） | 同机同库 |
| 冷启动到窗口出现（5 000 pins） | **43.3 s** | **0.90 s** | 无 `Cards/` 首次 |
| 一次 body 数据层 | 10.4 ms | **0.0001 ms**（memo 命中） | 3 次读取 + 统计 |
| 冷搜索查询 | 15.45 ms | **7.08 ms** | 1k |
| 冷换画板查询（数据层） | 0.94 ms | **0.62 ms** | 完整交互还含布局 |
| 卡片模型重建 / 分列 | 无此结构 | **0**（memo）/ **0.09 ms** | — |
| `library.json` 解码 | 74.9 ms × 2 次 | **10.1 ms × 1 次** | 启动 |
| `library.json` 编码 | 主线程 13.7 ms/次 | **后台 13.6 ms，debounce 0.4 s** | 不阻塞输入 |
| 卡片图解码 | 3.2 ms/张（1200 px） | **<0.6 ms/张**（640 px，估算） | 旧库回退 3.9 ms |
| 详情首图 | 原图 68 ms（主线程绘制时） | **~3 ms**（1200 px 后台解码） | 大图模式仍用原图 |

5000 pins：memo **0.0001 ms**、冷搜索 **36.4 ms**、换画板 **2.7 ms**、分列 **0.43 ms**、解码 **49.3 ms**、编码 **66.7 ms**（后台）。

功能验证：

- 50 次快速编辑 + `flushAndWait` → 最终快照胜出（独立 writer harness，PASS）；
- 详情改标题/加标签/移动画板/收藏 → 落盘校验通过（临时 mutation smoke，已移除）；
- Agent API 写入 → UI 计数从 1000 变 1001、磁盘一致；
- `./scripts/agent-smoke-test.sh` → **154/154 PASS**；
- 截图：gallery / detail / batch / large，中英语言切换均正常；
- 最终 `--bench`（1001 pins）：memo 0.0001 ms、冷搜索 7.10 ms、换画板 0.67 ms、分列 0.09 ms、解码 10.0 ms；
- 旧库首次启动后台生成 `Cards/`：1001 张约 20 s，可中断续跑。

### 8.3 已知限制

1. **滚动 p95 尚未自动化**：`NSCollectionView` 迁移的触发条件需要 Instruments 在真实 10k 库上测量；当前 10k 冷启动 0.82 s、搜索 4.8 ms、分列 0.8 ms，没有证据表明需要重写渲染层。
2. **Agent 外部写 vs 本地 debounce 写**：仍是 last-writer-wins（原有行为）。窗口很小（仅当外部写入与本地待写重叠），后续可用文件版本号/合并解决。
3. **旧库回填**：首次启动在后台生成 `Cards/`，期间网格回退到 1200 px 缩略图。
4. **标题固定两行**：`.lineLimit(2, reservesSpace: true)` 带来的视觉变化（卡片题注高度一致）。
5. **详情仍是 overlay**：没有独立窗口，但 `@Observable` + 呈现层隔离后，打开/切换详情不会重新求值网格（详见 8.4）。

### 8.4 P1 实施记录（2026-11-14）

| 项 | 实现 | 实测 |
|---|---|---|
| 搜索 | `searchKeyBytes` + `memmem` 字节扫描；>4000 张 40 ms 防抖 | 1k **0.28 ms** / 5k **1.88 ms** / 10k **4.79 ms**（P0 前 15.45 / 78.9 / 估算约 150 ms） |
| API | `LibraryFileStamp` 解码缓存 + `AgentResponseCache`（16 MB / 64 条 LRU，按 size+mtime(ns)+inode 失效） | `GET /pins` **76 → 1.2 ms**；`/library` **30 → 1.4 ms**；POST 后立即失效 |
| 观察粒度 | `LibraryStore` 迁移 `@Observable`；派生属性补数据依赖；`RootView` 拆出 `DetailLayer/CaptureLayer/ToastLayer` | 启动 3 s 后打开详情，`LibraryView.body` 在 openDetail 之后 **0 次**重算 |
| 性能门禁 | `scripts/perf-guard.sh [--pins N]`，解析 `--bench` 的 JSON 输出 | 1k、5k 均 PASS |
| 10k 规模 | 合成 10k 图库 | 冷启动 **0.82 s**、搜索 4.79 ms、换画板 1.31 ms、分列 0.82 ms、解码 101.7 ms |

**取舍记录**：先尝试了 trigram 倒排（构建 26 ms/5k、内存数 MB），但字节扫描已把 5k 冷查询降到 1.9 ms，倒排只再省约 1 ms，属于过度设计，最终移除以保持代码简单。倒排/FTS 留到 >50k 或出现真实瓶颈时再评估。

**未做**：`NSCollectionView`（缺少滚动 p95 证据）、详情独立窗口（隔离后无需）、回填进度提示与 HUD（可选打磨）。

---

## 附录 A：实测数据全表

> 机器：M1 Max / 64 GB / macOS 26.6.2；Swift 6.3.3 `-O`；合成图库；best-of-11；16.7 ms = 60 Hz 一帧。同机重复运行波动约 ±10%。
> 复现：`./scripts/perf-bench/run.sh`。

### A.1 查询与派生（当前实现）

| N | `filteredPins` | 按画板 | 搜索 3 词 | 模拟 body 数据层 | 换画板 | ←/→ |
|---:|---:|---:|---:|---:|---:|---:|
| 200 | 0.520 | 0.133 | 3.089 | 1.721 | 0.195 | 0.529 |
| 1 000 | 3.169 | 0.755 | 15.454 | 10.510 | 0.940 | 3.201 |
| 3 000 | 8.897 | 1.890 | 46.835 | 29.445 | 2.779 | 9.026 |
| 5 000 | 14.321 | 4.372 | 78.947 | 50.021 | 5.295 | 14.772 |

### A.2 投影与搜索

| N | 构建（仅搜索键） | 构建（+倒排） | 冷查询（无倒排） | 冷查询（倒排） | memo 命中 |
|---:|---:|---:|---:|---:|---:|
| 1 000 | 6.7 | 26.8 | 5.62 | **1.81** | 0.0001 |
| 3 000 | 21.1 | 80.8 | 16.40 | **4.92** | 0.0001 |
| 5 000 | 34.4 | 133.3 | 26.95 | **7.75** | 0.0001 |

### A.3 持久化与解码

| 操作 | N=1 000 | N=3 000 |
|---|---:|---:|
| 编码 `.prettyPrinted + .sortedKeys` | 13.7–14.1 | 43.1 |
| 原子写 | 0.7 | 1.3 |
| **`persist()`** | **15.3** | **44.8** |
| 解码（当前 ISO8601 策略） | **72–75** | **219–223** |
| 其中日期解析 | 58–60 | 180–181 |
| 解码（手写解析） | **8.6** | ~26 |
| `ISO8601DateFormatter` / 手写 | 33 µs / 0.07 µs | — |

### A.4 文件系统

| 操作 | 实测 |
|---|---:|
| `fileExists` × 1 000 | 2.6 ms |
| `fileExists` × 5 000 | 5.3 ms |
| `thumbnailURL`（URL 拼接 + stat）× 1 000 卡 | 4.2 ms |

### A.5 图片

| 操作 | 实测 |
|---|---:|
| `NSImage(contentsOfFile:)` 3200×2400 | 1.7 ms（懒） |
| 首次绘制到 476×357 | 68.4 ms（主线程） |
| 二次绘制 | 0.09 ms |
| ImageIO 全解码 3200×2400 | 59–61 ms |
| ImageIO 取 476 px（从 3200 原图） | 70.1 ms |
| ImageIO 全解码 1200×900 JPEG | 3.2–3.4 ms |
| ImageIO 取 476 px（从 1200 JPEG） | 3.8–3.9 ms |
| 位图：3200×2400 / 1200×900 / 476×357 | 29 MB / 4.1 MB / 0.65 MB |
| 驻留实测：原图尺寸 ×6 / 476 px ×200 / 240 px ×200 | +245 MB / +134 MB / +20 MB |

---

## 附录 B：P0 关键代码草图

### B.1 快照与投影

```swift
struct LibrarySnapshot {                 // 值类型，构建一次
    let revision: UInt64
    let pins: [Pin]
    let indexByID: [UUID: Int]
    let searchKeys: [String]             // 小写 haystack
    let boardKeys: [String]              // 小写画板
    let favoriteIndices: [Int]
    let screenshotIndices: [Int]
}

struct QueryKey: Hashable {
    var section: LibrarySection
    var board: String?
    var filter: GalleryFilter
    var sort: PinSort
    var needle: String
}

final class GalleryProjection {
    private let snapshot: LibrarySnapshot
    private var memo: [QueryKey: [Int]] = [:]
    private var statsMemo: (revision: UInt64, boards: [BoardSummary], tags: [(String, Int)])?

    func visibleIDs(_ key: QueryKey) -> [Int] {
        if let hit = memo[key] { return hit }
        // 候选集来自索引 → 过滤 → 按预计算 createdAt 排序
        // needle 非空时先用倒排（前缀）收窄，再子串后过滤，保证与现有 .contains 语义一致
        let ids = compute(key)
        memo[key] = ids
        return ids
    }
}
```

### B.2 懒列网格

```swift
struct MasonryColumns: View {
    let columns: [[PinCardModel]]
    let selectedIDs: Set<UUID>        // 父视图传入的值快照，不订阅 store
    let isSelecting: Bool
    let spacing: CGFloat
    let rowSpacing: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: rowSpacing) {
                    ForEach(columns[index]) { model in
                        PinCard(model: model,
                                isSelected: selectedIDs.contains(model.id),
                                isSelecting: isSelecting)   // actions 由 Environment 注入
                            .equatable()
                    }
                }
            }
        }
    }
}

func split(_ models: [PinCardModel], into count: Int, width: CGFloat, gap: CGFloat) -> [[PinCardModel]] {
    let columnWidth = (width - gap * CGFloat(count - 1)) / CGFloat(count)
    var heights = Array(repeating: CGFloat.zero, count: count)
    var columns = Array(repeating: [PinCardModel](), count: count)
    for model in models {
        let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
        let height = columnWidth / max(model.aspectRatio, 0.2) + model.captionHeight
        columns[target].append(model)
        heights[target] += height + gap
    }
    return columns
}
```

### B.3 快速 ISO-8601（与现有磁盘格式完全兼容）

```swift
@inline(__always)
private func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
    var y = y
    if m <= 2 { y -= 1 }
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (m + 9) % 12
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/// "2026-11-13T09:12:00Z" → Date，约 0.07 µs（对比 ISO8601DateFormatter 33 µs）
func parseCantaDate(_ s: String) -> Date? {
    let b = Array(s.utf8)
    guard b.count == 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58, b[19] == 90 else { return nil }
    let y = Int(b[0] - 48) * 1000 + Int(b[1] - 48) * 100 + Int(b[2] - 48) * 10 + Int(b[3] - 48)
    let mo = Int(b[5] - 48) * 10 + Int(b[6] - 48)
    let d = Int(b[8] - 48) * 10 + Int(b[9] - 48)
    let h = Int(b[11] - 48) * 10 + Int(b[12] - 48)
    let mi = Int(b[14] - 48) * 10 + Int(b[15] - 48)
    let sec = Int(b[17] - 48) * 10 + Int(b[18] - 48)
    return Date(timeIntervalSince1970: Double(daysFromCivil(y, mo, d) * 86_400 + h * 3_600 + mi * 60 + sec))
}
```

> 注意：现有 `CantaJSON.decoder` 同时接受带小数秒的旧数据（`iso8601Fractional`），保留该回退分支即可。

### B.4 图片解码 actor（骨架）

```swift
actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, CGImageBox>()
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    private let gate = AsyncSemaphore(limit: 6)   // 自实现或 Actor 计数

    init() { cache.totalCostLimit = 128 << 20 }

    func image(path: String, maxPixel: Int, priority: TaskPriority) async -> CGImage? {
        let key = "\(path)#\(maxPixel)"
        if let hit = cache.object(forKey: key as NSString) { return hit.image }
        if let running = inflight[key] { return await running.value }
        let task = Task.detached(priority: priority) { [cache] () -> CGImage? in
            await gate.acquire()
            defer { gate.release() }
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
            cache.setObject(CGImageBox(image), forKey: key as NSString,
                            cost: image.height * image.bytesPerRow)   // CGImageBox: @unchecked Sendable
            return image
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        return await task.value
    }
}
```

---

## 附录 C：复现与验证

```bash
# 数据层基准（本次入库，约 1–2 分钟）
./scripts/perf-bench/run.sh

# 构建并运行应用（release）
./scripts/build-app.sh release
open dist/Canta.app

# 用合成图库存跑（避免污染真实图库）
CANTA_HOME=/tmp/canta-5k ./dist/Canta.app/Contents/MacOS/Canta

# 观察写盘频率：在详情里改标题时应看到「一次写/约 0.5 s」，而不是每个字符一次
fs_usage -w -f filesys Canta

# 记录 Instruments 轨迹（固定动作序列）
#   Xcode → Instruments → SwiftUI + Animation Hitches + Time Profiler
```

**代码审阅红线**（建议写入 CONTRIBUTING）

1. `body` 及其调用的属性不得包含 O(N) 遍历、文件 IO、JSON、图片解码；
2. 叶子视图不得 `@EnvironmentObject` 整个 store；
3. store 层不得调用 `withAnimation`；
4. 不得在主线程 `Data(contentsOf:)`、`encode`、`write`；
5. 每次 `@Published` 写入都要能回答「谁会因此重渲染，代价是多少」。

---

## 附录 D：本次交付物与约束

| 产物 | 说明 |
|---|---|
| `docs/PERFORMANCE_PLAN.md` | 本方案：诊断、目标架构、分期路线、Rust 评估、SLO 与回归方式 |
| `docs/PERF_IMPROVEMENT_REPORT.md` | 本次优化报告（适合直接粘贴/导入飞书） |
| `docs/Canta-交互性能优化报告.docx` | 同上的 Word 版，可在飞书知识库「导入」为文档 |
| `docs/DETAIL_OPEN_LATENCY.md` | 详情打开延迟专项：分阶段探针、根因、P0–P2 实现与最终实测 |
| `docs/AGENT_PAGE_LATENCY.md` | Agent 访问页切换专项：分段测量、分阶段渲染与最终实测 |
| `scripts/perf-bench/run.sh` + `scripts/perf-bench/main.swift` | 可复现的 P0 前数据层基准（对照用） |
| `scripts/perf-guard.sh` | P1 性能门禁：合成图库 + `--bench` JSON + 预算断言，1k/5k 均通过 |
| 应用源码（P0 实施） | 数据层、卡片、网格、图片管线、持久化、启动、动效均已落地；新增 `Store/LibrarySnapshot.swift`、`Store/ImageLoader.swift`、`Store/LibraryWriter.swift`、`Store/CardThumbnailBackfill.swift`、`Performance/` |

约束（已遵守）：

- 不引入第三方依赖；
- 不改 `library.json` 的字段与日期格式（新增的 `Cards/` 目录由 id 推导，不进入 JSON）；
- 不改 Agent API 的路径与响应结构（154 项冒烟测试通过）；
- 每个 P0 子项可独立回滚。
