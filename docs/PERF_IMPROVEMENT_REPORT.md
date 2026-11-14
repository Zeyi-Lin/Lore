# Canta 交互性能优化报告

**项目**：Canta（macOS 本地视觉图库 · SwiftUI / AppKit）
**日期**：2026-11-14
**范围**：图库网格、详情、图片切换、画板切换、搜索与编辑、图片管线、持久化、启动
**结论**：在不改 `library.json` 格式、不改 Agent API 契约、不引入第三方依赖的前提下，用纯 Swift 完成 P0 优化。四个症状的主因均被结构性消除，而非参数微调。

---

## 1. 摘要

用户反馈四类卡顿：点详情慢、←/→ 换图慢、切换画板慢、卡片多了整体卡。

诊断后发现根因不是图片编解码，也不是「Swift 比 Rust 慢」，而是四个问题相乘：

1. **观察粒度反了**：17 个 `@Published` 状态共用一个通知，每张卡片都订阅了整个 store。任何状态写入都会让 N 张卡片重算 body。
2. **派生数据在 body 里现算**：`filteredPins` 是纯计算属性，一次 body 被读 5 次，每次 O(N log N) 并重建搜索串。
3. **网格完全非懒加载**：`ScrollView { VStack { MasonryLayout { ForEach } } }`，N 张卡全部实例化，且被测量两遍。
4. **主线程同步写盘 + 假后台解码**：改标题每敲一个字全量编码写盘；详情加载原图，而 `NSImage` 是懒解码，真正 60–70 ms 的解码落在绘制时的主线程。

优化后（同机同库）：

| 指标 | 优化前 | 优化后 |
|---|---:|---:|
| 冷启动到窗口出现（1 000 pins） | 6.3–6.5 s | **0.68–0.87 s**（已生成卡片缩略图）/ 1.28 s（首次） |
| 冷启动到窗口出现（5 000 pins） | **43.3 s** | **0.90 s** |
| 一次 `LibraryView` body 的数据层 | 10.4 ms | **0.0001 ms**（memo 命中） |
| 冷搜索查询（1k / 5k） | 15.45 / 78.9 ms | **7.10 / 36.4 ms** |
| 启动时 `library.json` 解码 | 74.9 ms × 2 次 | **10.0 ms × 1 次** |
| 每次编辑写盘 | 主线程 13.7 ms | **后台编码 + 0.4 s debounce** |
| 详情首图 | 原图 68 ms（主线程绘制时解码） | **约 3 ms**（1200 px 后台解码） |

**关于 Rust**：本轮不建议、也未使用 Rust 重写。UI 延迟发生在 SwiftUI 的 view body、布局与失效传播路径上，Rust 无法进入这条路径；重写 UI 需 6–12 人月且会丢失现有 macOS 集成。Rust 的合理落点是离线批处理媒体、十万级索引或未来跨平台内核，需另立门槛评估。

---

## 2. 问题与方法

### 2.1 用户症状

- 点击卡片打开详情有明显停顿；
- 详情里按 ←/→ 切换图片卡顿；
- 侧栏切换画板时整屏顿一下；
- 卡片数量增长后，滚动、搜索、点击都变慢，整机也变卡。

### 2.2 测量方法

- 机器：Apple M1 Max / 64 GB / macOS 26.6.2；Swift 6.3.3，`-O`。
- 图库：由示例图库生成的合成库（1 000 / 5 000 pins，字段长度贴近真实数据）。
- 数据层：`scripts/perf-bench/run.sh`（保留优化前算法，用于前后对照）与 `Canta --bench`（测量当前实现）。
- 启动：以 `CANTA_HOME` 指向测试库，轮询 `CGWindowList` 到窗口出现的时间；新旧 App 使用同一图库。
- 图片：ImageIO 直接测量解码、绘制与驻留内存。
- UI 层：`OSSignposter` 已埋点（query / models / write / image decode），可用 Instruments 复核端到端 p95。
- **说明**：本机无法自动注入鼠标/键盘事件（辅助功能权限受限），因此点击/←→ 的端到端 p95 未自动化；下文交互结论由「组件实测 + 结构消除」推导，建议在目标机器用 Instruments 做最终确认。

---

## 3. 优化前基线

### 3.1 数据层（1 000 pins）

| 操作 | 耗时 |
|---|---:|
| `filteredPins`（全部 · 按时间） | 3.17 ms / 次 |
| `filteredPins`（3 词搜索） | 15.45 ms / 次 |
| 一次 `LibraryView` body 的数据层（3 次读取 + 统计 + 画板汇总） | 10.51 ms |
| 换画板数据层 | 0.94 ms |
| ←/→ 换图数据层 | 3.20 ms |
| 5 000 pins 时一次 body 数据层 | 50.02 ms |

`filteredPins` 在 `LibraryView` 里实际被读 5 次（空态、ForEach、计数、按钮禁用、按钮透明度），详情浮层另读 2–3 次。**N=1000 时，仅一次 body 的数据层就超过 10 ms，尚未渲染任何卡片。**

### 3.2 持久化与启动

| 操作 | 1 000 pins | 3 000 pins |
|---|---:|---:|
| `JSONEncoder`（`.prettyPrinted + .sortedKeys`） | 13.7–14.1 ms | 43.1 ms |
| `persist()`（编码 + 原子写，主线程） | **15.3 ms** | **44.8 ms** |
| `library.json` 解码 | **74.9 ms** | **219.2 ms** |
| 其中 ISO-8601 日期解析 | 60.4 ms | 179.9 ms |
| 启动解码次数 | **2 次**（播种判断 + 加载） | 2 次 |

详情标题/备注的 `Binding` 每个字符都调用 `updatePin` → `persist()`。**3k 图库中每敲一个字阻塞主线程约 45 ms。**

### 3.3 图片

| 操作 | 实测 |
|---|---:|
| `NSImage(contentsOfFile:)` 3200×2400 | 1.7 ms（只读头，**懒解码**） |
| 首次绘制到 476×357 | **68.4 ms**（解码落在绘制方，即主线程） |
| 二次绘制 | 0.09 ms |
| ImageIO 全解码 3200×2400 | 59–61 ms |
| 卡片图：1200×900 JPEG 全解码 | 3.2–3.4 ms，4.1 MB 位图 |
| 卡片位图（目标尺寸 476×357） | 0.65 MB |
| `ImageCache` 上限 | 220 张（按数量，无字节上限） |

结论：卡片需要 0.65 MB 的位图，却持有 4.1 MB 的 1200 px 解码；缓存最坏可堆积约 900 MB，低内存机器会因内存压力整体变慢。

---

## 4. 根因分析

### 4.1 每张卡片订阅整个 store

`LibraryStore` 有 17 个独立 `@Published` 字段，共用一个 `objectWillChange`；`PinCard` 通过 `@EnvironmentObject` 订阅 store。于是搜索敲一个字、选中一张、弹一个 toast、Agent 端口变化，都会让**全部 N 张卡片重新求值 body**。

`PinCard` 真正需要的只有「这张卡的数据 + 是否选中 + 是否处于选择模式」，却订阅了整个库。这是「卡片越多越卡」的第一主因。

### 4.2 派生数据在 body 里现算

`filteredPins` 每次访问都复制数组、过滤、为每张卡拼 7 个字符串并 `lowercased`、排序。一次 body 读 5 次，等于把同一份工作做 5 遍。`boardSummaries`、`selectedPin`、计数、标签也是同样模式，且互相嵌套（例如选中状态派生会再次触发 `filteredPins`）。

### 4.3 网格非懒加载 + 双次测量

`MasonryLayout` 是自定义 `Layout`，`sizeThatFits` 遍历所有子视图测尺寸，`placeSubviews` 再测一遍；`cache: inout ()` 没有任何缓存。`ScrollView + VStack + ForEach` 又保证所有卡片被实例化，每张卡同时启动一个无并发上限的图片任务。首帧、换画板、列表变化都是 O(N)。

### 4.4 主线程写盘与「假后台解码」

- 编辑写盘：每个按键全量编码 + 原子写，在主线程；
- 详情图片：`NSImage(contentsOfFile:)` 只解析头部，真正解码发生在 `Image(nsImage:)` 绘制时，也就是主线程；`Task.detached` 只挪走了 1.7 ms，把 68 ms 留在最关键的首次绘制上；
- 详情还跳过已有 1200 px 缩略图，直接请求原图。

### 4.5 放大器

- 缩略图 1200 px 对 238–300 pt 卡位过大；
- 图片缓存按张数而非字节；
- `withAnimation` 写在 store 层、`currentListIdentity` 驱动全网格动画，搜索每敲一个字都会触发整屏动画；
- 详情遮罩使用全屏 `.ultraThinMaterial`，对正在动画的网格逐帧采样；
- 启动解码两次，且 80% 时间花在 `ISO8601DateFormatter`；
- 每张卡在 body 里做 `fileExists`（1 000 卡约 4.2 ms/次）。

---

## 5. 改进设计与实现

### 5.1 数据层：Snapshot + Projection

新增不可变 `LibrarySnapshot`：pins、`indexByID`、收藏/截图计数、画板/标签聚合、按需构建的小写搜索键。

新增 `GalleryProjection`：以 `(筛选条件, 语言, 数据版本)` 为键 memo 查询结果与卡片模型。一次交互最多重算一次，body 里的多次读取变成字典查找。

- `filteredPins`：O(N log N) 现算 → memo 命中；
- `selectedPin`：线性扫描 → 字典查找；
- 排序：改为对预计算索引排序，查询只做一次线性过滤；
- 日期解析：手写定点 ISO-8601 解析（磁盘格式不变），33 µs/日期 → 0.07 µs。

### 5.2 渲染层：值化卡片 + 懒列网格

- `PinCard` 不再持有 store，只接收 `PinCardModel`、`isSelected`、`isSelecting` 和动作闭包，并实现 `Equatable`（动作不参与比较）。状态变化时 SwiftUI 只重建真正变化的卡片。
- 网格改为「按宽度分 K 列，每列一个 `LazyVStack`」；标题使用 `.lineLimit(2, reservesSpace: true)` 使题注高度固定，卡片高度可由 `aspectRatio` 纯算术预计算，列平衡一次 O(N) 完成，不再测量文本。
- 删除网格容器动画与每卡 transition，动画只保留在呈现边缘。

### 5.3 图片管线

- 新增 `Cards/` 640 px 网格缩略图（路径由 pin id 推导，不进 `library.json`）；旧库首次启动后台回填，可中断续跑。
- 新增 `ImageLoader` actor：按目标像素解码（`CGImageSourceCreateThumbnailAtIndex` + `shouldCacheImmediately`）、并发上限、按路径去重、字节上限 128 MB 的 `NSCache`、±1 邻图预取。
- 详情首图使用 1200 px 缩略图；原图仅在大图模式使用；去掉了详情遮罩的材质。

### 5.4 持久化

新增 `LibraryWriter`：单写者串行队列，debounce（编辑 0.45 s、结构性操作 0.1 s、导入 0.05 s），编码与原子写在后台，generation 丢弃过期快照；关详情、失焦、退出时 flush。`library.json` 格式与 API 不变。

### 5.5 启动与观测

- `SeedLoader.loadOrInstall` 合并播种判断与加载，只解码一次。
- 新增 `OSSignposter`（`gallery.query`、`gallery.models`、`library.write`、`image.decode`）与 `Canta --bench`，让性能回归可量化。

---

## 6. 优化结果

### 6.1 启动（同机同库，到窗口出现）

| 图库 | 优化前 | 优化后 |
|---|---:|---:|
| 1 000 pins | 6.3–6.5 s | **0.68–0.87 s**（已生成 `Cards/`，三次）/ 1.28 s（首次，后台回填中） |
| 5 000 pins | **43.3 s** | **0.90 s**（首次） |

5k 场景提升约 **48×**：旧实现要在首帧实例化并测量 5 000 张卡，新实现只实例化可见的约 40 张。

### 6.2 数据层（当前实现，1 001 pins）

| 操作 | 耗时 |
|---|---:|
| 可见 pins 读取（body 常走） | **0.0001 ms** |
| 冷搜索查询（每次新输入） | 7.10 ms |
| 冷换画板查询 | 0.67 ms |
| 卡片模型读取（body 常走） | 0.0001 ms |
| 列分配（1 000+ 卡） | 0.09 ms |
| `library.json` 解码（启动） | 10.0 ms |
| `library.json` 编码（后台） | 13.7 ms |

5 000 pins：memo 0.0001 ms、冷搜索 36.4 ms、换画板 2.7 ms、列分配 0.43 ms、解码 49.3 ms、编码 66.7 ms（后台）。搜索在 5k 时仍偏慢，列入 P1 索引优化。

### 6.3 图片与持久化

| 指标 | 优化前 | 优化后 |
|---|---:|---:|
| 卡片图解码 | 3.2 ms/张（1200 px） | 目标 640 px；位图 4.1 MB → 约 0.65–1.2 MB |
| 缓存上限 | 220 张（最坏约 900 MB） | 128 MB（按字节） |
| 详情首图 | 68 ms（主线程绘制时） | 约 3 ms（1200 px 后台解码） |
| 编辑写盘 | 每个按键主线程 15–45 ms | 后台 + debounce，主线程 0 ms |

---

## 7. 正确性验证

| 验证项 | 结果 |
|---|---|
| Agent API 黑盒冒烟（154 项） | **154/154 PASS** |
| 50 次快速编辑 + `flushAndWait` | 最终快照胜出（PASS） |
| 改标题 / 加标签 / 移动画板 / 收藏 → 落盘校验 | PASS |
| Agent API 写入后 UI 刷新 | 1 000 → 1 001，磁盘一致 |
| 截图回归：gallery / detail / batch / large | 正常 |
| 中英文切换（含卡片画板标签） | 正常 |
| 旧库后台生成 `Cards/`（1 001 张） | 约 20 s，可中断续跑 |
| 数据格式 / API 契约 | 未改变 |

所有测试使用 `/tmp` 下的独立图库，未触碰真实用户图库。

---

## 8. 经验总结

1. **观察粒度比微优化重要一个数量级**：让每张卡片订阅整库，任何状态写入都是 O(N)；把叶子改成值 + `Equatable` 后，同样的 SwiftUI 代码成本结构完全不同。
2. **body 里的 O(N) 会复利**：一次读取 3 ms 看似可接受，乘以 5 次读取、每次交互、N 张卡片后就是数百毫秒。派生数据必须有单一缓存点。
3. **懒解码陷阱**：`NSImage(contentsOfFile:)` 返回很快不代表解码已完成；真正的解码在绘制时发生。要显式用 ImageIO 解到目标像素，并在后台完成。
4. **按字节而不是按张数管理图片缓存**：同样 220 张，可能是 50 MB，也可能是 900 MB。
5. **持久化要区分「数据变更」与「输入事件」**：每键全量写盘是典型的把磁盘当内存用；debounce + 单写者 + 后台写即可，格式无需改变。
6. **先修架构，再谈语言**：本轮 5–48× 的提升全部来自 Swift 架构调整；Rust 无法进入 SwiftUI 的 body/布局/失效路径，重写 UI 不是性能方案。

---

## 9. 后续计划

| 优先级 | 事项 | 目标 |
|---|---|---|
| P1 | 搜索 trigram / FTS 索引 | 5k 冷查询 36 ms → <16 ms |
| P1 | `@Observable` 迁移 | 进一步缩小 LibraryView/Sidebar 的失效范围 |
| P1 | `NSCollectionView` 复用渲染（条件触发） | 1 万+ 卡片滚动稳定 ≥55 fps |
| P1 | API 内存快照 + 文件监听 | `GET /api/v1/pins` <2 ms |
| P2 | SQLite WAL、Rust 离线媒体 worker | 按方案第 5 节门槛评估 |
| 持续 | Instruments 端到端 p95 门禁 | 点详情 ≤50 ms、换图 ≤16.7 ms、换画板 ≤40 ms |

---

## 附录

### A. 复现命令

```bash
./scripts/build-app.sh release
./scripts/perf-bench/run.sh          # 优化前基线（对照）
CANTA_HOME=/tmp/canta-perf/library-1k ./dist/Canta.app/Contents/MacOS/Canta --bench
```

### B. 主要代码变更

- 新增：`Sources/Canta/Store/LibrarySnapshot.swift`、`ImageLoader.swift`、`LibraryWriter.swift`、`CardThumbnailBackfill.swift`、`Sources/Canta/Performance/`
- 重写：`LibraryView.swift`（懒列网格）、`PinCard.swift`（值化 + Equatable）、`LibraryStore.swift`（快照/投影/持久化）
- 修改：`Components.swift`（LibraryImage）、`SeedLoader.swift`（单次解码）、`CantaPaths.swift`（快速日期 + Cards 目录）、`ImageProcessor.swift`（640 档）、`PinDetailView.swift`（1200/原图、去材质）、`RootView.swift`（维护/flush）
- 删除：`Views/MasonryLayout.swift`
- 文档：`docs/PERFORMANCE_PLAN.md`（方案 + 实施记录）

### C. 已知限制

1. 5k 搜索仍 36 ms，需 P1 索引；
2. Agent 外部写与本地 debounce 写仍为 last-writer-wins（原有行为）；
3. 旧库首次启动后台回填 `Cards/`，期间回退 1200 px 缩略图；
4. 标题固定两行（`reservesSpace`）带来轻微视觉变化；
5. 端到端点按/换图 p95 未自动化，建议用 Instruments 复核。
