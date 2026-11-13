import Foundation
import SwiftUI

// MARK: - Language preference

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return T("System")
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum ResolvedLanguage: String {
    case chinese = "zh"
    case english = "en"

    var locale: Locale {
        switch self {
        case .chinese: return Locale(identifier: "zh_CN")
        case .english: return Locale(identifier: "en_US")
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var selection: AppLanguage
    @Published private(set) var resolved: ResolvedLanguage

    private static let selectionKey = "canta.language"
    private static let debugKey = "canta.debugLanguage"

    private init() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.selectionKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.selection = saved
        if let forced = defaults.string(forKey: Self.debugKey).flatMap(ResolvedLanguage.init(rawValue:)) {
            self.resolved = forced
        } else if saved == .system {
            self.resolved = Self.systemLanguage
        } else {
            self.resolved = saved == .chinese ? .chinese : .english
        }
    }

    static var systemLanguage: ResolvedLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? .chinese : .english
    }

    var locale: Locale { resolved.locale }

    func select(_ language: AppLanguage) {
        selection = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.selectionKey)
        if let forced = UserDefaults.standard.string(forKey: Self.debugKey).flatMap(ResolvedLanguage.init(rawValue:)) {
            resolved = forced
        } else {
            resolved = language == .system ? Self.systemLanguage : (language == .chinese ? .chinese : .english)
        }
    }

    func string(_ key: String) -> String {
        resolved == .chinese ? (Self.zh[key] ?? key) : key
    }

    // English strings are the keys. Chinese lives here so the app needs no
    // bundle lookup and switching language is immediate at runtime.
    private static let zh: [String: String] = [
        // App / navigation
        "Capture": "收录",
        "All pins": "全部灵感",
        "Favorites": "收藏",
        "Recent": "最近",
        "Agent access": "Agent 访问",
        "All Pins": "全部灵感",
        "Agent Access": "Agent 访问",
        "Boards": "画板",
        "Boards appear here as you pin.": "收录内容后，画板会显示在这里。",
        "VISUAL LIBRARY": "视觉图库",
        "Local library": "本地图库",
        "Local only": "仅本地",
        "%ld pins · private": "%ld 个灵感 · 仅本地",
        "Settings": "设置",
        "Keep Canta quiet, local, and ready for your agent.": "让 Canta 保持安静、本地，随时为你的 Agent 服务。",
        "Agent API": "Agent API",
        "Metadata and image streams for your coding agent.": "为编程 Agent 提供元数据与图片流。",
        "Agent API live": "Agent API 已启动",
        "API live": "API 已启动",
        "API stopped": "API 已停止",
        "API off": "API 未开启",
        "API starting…": "API 启动中…",
        "API unavailable": "API 不可用",
        "Starting": "启动中",
        "Offline": "离线",
        "Open Agent access": "打开 Agent 访问",
        "Capture a new pin": "收录一个新灵感",
        "Copy filtered pins as agent context": "将筛选结果复制为 Agent 上下文",
        "Settings…": "设置…",

        // Search / library
        "Search pins, tags, boards…": "搜索灵感、标签或画板…",
        "Search Pins": "搜索灵感",
        "YOUR VISUAL LIBRARY": "你的视觉图库",
        "SAVED FOR LATER": "留待以后",
        "RECENTLY PINNED": "最近收录",
        "SEARCHING YOUR LIBRARY": "正在搜索图库",
        "BOARD · %@": "画板 · %@",
        "SEARCH": "搜索",
        "A quiet visual library for humans and their agents.": "属于人类与 Agent 的安静视觉图库。",
        "All": "全部",
        "Screenshots": "截图",
        "shown": "已显示",
        "%ld shown": "已显示 %ld 个",
        "Clear board filter": "清除画板筛选",
        "Recently added": "最近添加",
        "Oldest first": "最早添加",
        "A–Z": "名称 A–Z",
        "Sort": "排序",
        "Clear search & filters": "清除搜索与筛选",
        "No pins match": "没有匹配的灵感",
        "Your library is waiting": "你的图库正在等待",
        "Try a different phrase, or loosen the filters.\nBoards and tags are searchable too.": "换个关键词，或放宽筛选条件。\n画板和标签也可以搜索。",
        "Pin the interfaces that make you stop scrolling.\nEvery capture keeps its pixels, palette, and context — ready for your agent.": "把那些让你停下来多看一眼的界面收进来。\n每张截图都保留像素、色板与上下文，随时喂给 Agent。",
        "Capture screenshot": "截取屏幕",
        "Import images": "导入图片",
        "or press ⇧⌘V to pin the clipboard": "或按 ⇧⌘V 收录剪贴板",
        "⇧⌘2 for a screen capture": "⇧⌘2 截取屏幕",
        "agent ready": "Agent 就绪",
        "A quiet dashboard": "安静的仪表盘",
        "AGENT ACCESS": "AGENT 访问",
        "AGENT API": "AGENT API",
        "Command copied": "命令已复制",
        "Prompt copied": "提示词已复制",
        "Copy": "复制",
        "Images are stored on this Mac and never uploaded.": "图片仅保存在这台 Mac 上，不会上传。",
        "Add references to Canta": "为 Canta 添加参考",
        "Pin": "收录",
        "llms.txt": "llms.txt",
        "%ld pins · a small, searchable visual memory for building interfaces": "%ld 个灵感 · 一个小而可检索的视觉记忆，帮你构建界面",
        "%ld pins curated in this board": "%ld 个灵感 · 精心收藏于此画板",
        "%ld hand-picked references": "%ld 个精选参考",
        "%ld pins added in the last 30 days": "最近 30 天新增 %ld 个灵感",
        "Give your coding agent eyes for good design": "让你的编程 Agent 看见好设计",
        "Sort by": "排序方式",
        "Filters": "筛选",

        // Pin card
        "Save": "收藏",
        "Saved": "已收藏",
        "Save to favorites": "加入收藏",
        "Remove from favorites": "取消收藏",
        "Open pin": "打开灵感",
        "Add to favorites": "加入收藏",
        "Copy agent snippet": "复制 Agent 片段",
        "Copy image": "复制图片",
        "Move to board": "移动到画板",
        "Open original": "打开原图",
        "Reveal in Finder": "在 Finder 中显示",
        "Open source page": "打开来源页面",
        "Copy image URL": "复制图片链接",
        "Delete pin": "删除灵感",
        "More actions": "更多操作",
        "Image unavailable": "图片不可用",

        // Pin detail
        "Close": "关闭",
        "Screenshot": "截图",
        "Image": "图片",
        "%ld-color palette": "%ld 色调色板",
        "New board…": "新建画板…",
        "Copy pin JSON": "复制灵感 JSON",
        "Image URL copied": "图片链接已复制",
        "Delete this pin?": "删除这个灵感？",
        "Delete": "删除",
        "Cancel": "取消",
        "The original image and its metadata will be removed from Canta.": "原图及其元数据将从 Canta 中移除。",
        "Untitled pin": "未命名灵感",
        "Captured %@": "收录于 %@",
        "New board name": "新画板名称",
        "Move": "移动",
        "Design note": "设计笔记",
        "What makes this worth copying? Layout, type, color…": "它为什么值得参考？布局、字体、色彩…",
        "Tags": "标签",
        "tag": "标签",
        "%@ copied": "%@ 已复制",
        "Copy %@": "复制 %@",
        "Agent-ready": "Agent 就绪",
        "Metadata + image stream, one fetch away.": "元数据与图片流，一次请求即可获取。",
        "Copy snippet": "复制片段",
        "Copy JSON": "复制 JSON",
        "Details": "详情",
        "PIXELS": "像素",
        "FILE": "文件",
        "FORMAT": "格式",
        "CAPTURED": "收录时间",
        "Reveal": "显示",
        "Canta Seed": "Canta 预设",
        "Recent captures": "最近收录",
        "%ld pin": "%ld 个灵感",
        "%ld pins": "%ld 个灵感",
        "Palette": "色板",

        // Capture sheet
        "QUICK CAPTURE": "快速收录",
        "Pin something worth referencing.": "收录值得参考的设计。",
        "Screenshots in, structure out. Canta reads pixels, palette, and dimensions for you.": "截图进来，结构化信息自动生成。Canta 会为你读取像素、色板与尺寸。",
        "Drop screenshots here": "拖入截图",
        "Release to pin": "松开即可收录",
        "or paste with ⇧⌘V · PNG, JPEG, HEIC, TIFF": "或按 ⇧⌘V 粘贴 · 支持 PNG、JPEG、HEIC、TIFF",
        "Take screenshot": "截取屏幕",
        "Choose images": "选择图片",
        "Paste": "粘贴",
        "ADD TO": "添加到",
        "Unsorted": "未分类",

        // Import / store
        "Imported": "导入",
        "Clipboard": "剪贴板",
        "Screen capture": "屏幕截图",
        "Drag & drop": "拖放",
        "Screenshot · %@": "截图 · %@",
        "Pasted screenshot · %@": "粘贴截图 · %@",
        "Screen capture · %@": "屏幕截图 · %@",
        "Untitled capture": "未命名截图",
        "Still importing": "仍在导入",
        "Canta is still importing": "Canta 仍在导入",
        "Couldn't add that image": "无法添加这张图片",
        "Couldn't save the library": "无法保存图库",
        "Couldn't load that image": "无法读取这张图片",
        "Image copied": "图片已复制",
        "Pin JSON copied": "灵感 JSON 已复制",
        "Agent snippet copied": "Agent 片段已复制",
        "Agent context copied": "Agent 上下文已复制",
        "Copied": "已复制",
        "No image on the clipboard": "剪贴板中没有图片",
        "Pin deleted": "灵感已删除",
        "Saved to favorites": "已加入收藏",
        "Removed from favorites": "已取消收藏",
        "%ld pin added to %@": "%ld 个灵感已添加到 %@",
        "%ld pins added to %@": "%ld 个灵感已添加到 %@",
        "%@ added · %@": "已添加 %@ · %@",
        "Screenshot added to %@": "截图已添加到 %@",
        "Screenshot added": "截图已添加",
        "Untitled": "未命名",
        "%@ isn't a readable image.": "%@ 不是可读取的图片。",
        "%@ uses an unsupported image format.": "%@ 使用了不支持的图片格式。",
        "Couldn't store the image: %@": "无法保存图片：%@",
        "Clipboard image": "剪贴板图片",
        "No pins yet.": "还没有灵感。",
        "No pins in this library.": "图库中还没有灵感。",

        // App menus
        "Library": "图库",
        "New Pin": "新建灵感",
        "Import Images…": "导入图片…",
        "Paste Image": "粘贴图片",
        "Capture Screenshot": "截取屏幕",
        "Copy Agent Context": "复制 Agent 上下文",
        "Open Data Folder": "打开数据文件夹",
        "Canta Agent API Documentation": "Canta Agent API 文档",
        "Canta Agent API Documentation…": "Canta Agent API 文档…",

        // Agent access page
        "Give your agent eyes.": "让 Agent 看见好设计。",
        "Every pin is a queryable JSON record with a direct image stream, served on loopback.": "每个灵感都是一条可查询的 JSON 记录，并附带直连图片流，仅在本地回环地址提供。",
        "LOCALHOST · READ ONLY": "本地 · 只读",
        "Your library, readable\nby your coding agent.": "你的图库，\n可被编程 Agent 读取。",
        "Point Claude Code, Codex, or Cursor at the docs endpoint.\nIt gets structured metadata and exact image URLs — no exports, no screenshots of screenshots.": "把 Claude Code、Codex 或 Cursor 指向文档端点。\n它能获得结构化元数据与准确的图片链接——无需导出，也无需二次截图。",
        "Open API docs": "打开 API 文档",
        "Copy endpoint": "复制端点",
        "QUICKSTART": "快速开始",
        "Fetch the whole design context in one request.": "一次请求获取完整设计上下文。",
        "Copy command": "复制命令",
        "Open context": "打开上下文",
        "AGENT PROMPT": "Agent 提示词",
        "Paste this into your coding agent to establish the reference loop.": "粘贴给你的编程 Agent，建立参考闭环。",
        "Copy prompt": "复制提示词",
        "Open llms.txt": "打开 llms.txt",
        "API SURFACE": "API 接口",
        "Everything in one payload": "一次获取全部内容",
        "Filter by q, tag, board, favorite": "按 q、标签、画板、收藏筛选",
        "A single enriched pin": "单个增强灵感",
        "Original or thumbnail stream": "原图或缩略图流",
        "Markdown design context": "Markdown 设计上下文",
        "Human + agent documentation": "面向人与 Agent 的文档",
        "THE SERVER": "服务状态",
        "PORT": "端口",
        "Apply": "应用",
        "Restart": "重启",
        "Data folder": "数据文件夹",
        "Bound to loopback only. Images and metadata never leave this Mac.": "仅绑定本机回环地址。图片与元数据不会离开这台 Mac。",
        "Port must be 1024–65535": "端口必须为 1024–65535",
        "Agent API restarted on :%ld": "Agent API 已在 :%ld 重启",
        "Endpoint copied": "端点已复制",
        "Open docs": "打开文档",
        "Serves the library on 127.0.0.1 only. Read-only, no authentication required for local agents.": "仅在 127.0.0.1 提供图库。只读，本地 Agent 无需鉴权。",
        "Local design references for your agent.": "供 Agent 使用的本地设计参考。",
        "Read-only": "只读",
        "Design context": "设计上下文",

        // Settings
        "CAPTURE": "收录",
        "Default board": "默认画板",
        "New pins land here unless you pick another board.": "除非另选画板，新灵感默认放在这里。",
        "Library location": "图库位置",
        "ABOUT": "关于",
        "Canta 1.0": "Canta 1.0",
        "Made for macOS": "为 macOS 打造",
        "LANGUAGE": "语言",
        "App language": "应用语言",
        "Follows your macOS language unless changed.": "默认跟随 macOS 系统语言，也可手动切换。",
        "System": "跟随系统",
        "Web dashboards": "网页仪表盘",
        "Mobile flows": "移动端流程",
        "Landing pages": "落地页",
        "Editorial": "编辑排版",

        // Drop overlay
        "Drop to pin": "松手即可收录",
        "Screenshots, images, or a pile of references": "截图、图片，或一堆参考素材",
        "Screenshot permission": "截图权限",
        "Screen Recording permission may be required.": "可能需要屏幕录制权限。",

        // Root / misc
        "Canta couldn't read your library. New pins will start a fresh one. (%@)": "Canta 无法读取你的图库，新收录的内容会重新开始。 (%@)",
        "Error": "错误",
        "Done": "完成",
        "image": "图片",
        "screenshots": "截图"
    ]
}

func T(_ key: String) -> String {
    LanguageManager.shared.string(key)
}

func TF(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: LanguageManager.shared.string(format), locale: LanguageManager.shared.locale, arguments: arguments)
}

func localizedSourceLabel(_ source: String?) -> String? {
    guard let source, !source.isEmpty else { return nil }
    switch source {
    case "Canta Seed": return T("Canta Seed")
    case "Imported": return T("Imported")
    case "Clipboard": return T("Clipboard")
    case "Screen capture": return T("Screen capture")
    case "Drag & drop": return T("Drag & drop")
    default: return source
    }
}

func localizedBoard(_ board: String) -> String {
    switch board.lowercased() {
    case "web dashboards": return T("Web dashboards")
    case "mobile flows": return T("Mobile flows")
    case "landing pages": return T("Landing pages")
    case "editorial": return T("Editorial")
    case "unsorted": return T("Unsorted")
    default: return board
    }
}

// Board-name keys used by localizedBoard
extension LanguageManager {
    static let boardTranslations: [String: String] = [:]
}