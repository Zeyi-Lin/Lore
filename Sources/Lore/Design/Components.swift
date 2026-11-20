import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Window chrome

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // The window only moves from the explicit grips (see WindowGrip):
            // background dragging made every empty spot of the gallery a handle.
            window.isMovableByWindowBackground = false
            window.isMovable = false
            window.backgroundColor = NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            window.minSize = NSSize(width: 1080, height: 700)
            for delay in [0.35, 1.2, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(nil)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Brand mark

struct LoreMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(Theme.red)

            RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .frame(width: size * 0.42, height: size * 0.54)
                .rotationEffect(.degrees(-14))
                .offset(x: -size * 0.075, y: size * 0.015)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .fill(Color.white)
                    .frame(width: size * 0.42, height: size * 0.54)
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(Theme.red)
                    .offset(y: -size * 0.015)
            }
            .rotationEffect(.degrees(9))
            .offset(x: size * 0.075, y: -size * 0.005)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons

enum LoreButtonVariant {
    case primary
    case secondary
    case ghost
    case dark
}

struct LoreButton: View {
    var title: String
    var icon: String?
    var variant: LoreButtonVariant = .primary
    var shortcut: String?
    var fullWidth: Bool = false
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        // SF Mono does not advance ⌘/⇧ correctly at this
                        // size (they overlap); the default face keeps the
                        // keycap glyphs legible.
                        .font(.system(size: 10.5, weight: .medium))
                        .opacity(0.58)
                        .padding(.leading, 2)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 42)
            .padding(.horizontal, fullWidth ? 18 : 18)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    private var foreground: Color {
        switch variant {
        case .primary, .dark: return .white
        case .secondary, .ghost: return Theme.ink
        }
    }

    private var background: Color {
        switch variant {
        case .primary:
            return hovering ? Theme.redDeep : Theme.red
        case .dark:
            return hovering ? Color(hex: 0x2B2622) : Theme.ink
        case .secondary:
            return hovering ? Theme.parchment : Theme.paper
        case .ghost:
            return hovering ? Color.black.opacity(0.055) : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary, .ghost, .dark: return .clear
        case .secondary: return Theme.hairline
        }
    }
}

struct CircleActionButton: View {
    var icon: String
    var label: String?
    var emphasized: Bool = false
    var filled: Bool = false
    var size: CGFloat = 38
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                if let label {
                    Text(label).font(.system(size: 12.5, weight: .semibold))
                }
            }
            .foregroundStyle(filled ? Color.white : (emphasized ? Theme.red : Theme.ink))
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, label == nil ? 0 : 13)
            .background(
                Capsule().fill(
                    filled ? Theme.red : (hovering ? Theme.parchmentDeep : Theme.paper)
                )
            )
            .overlay(Capsule().strokeBorder(filled ? .clear : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    var title: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(Theme.mono(10.5, weight: .medium))
                        .opacity(isSelected ? 0.65 : 0.48)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Theme.inkSecondary)
            .frame(height: 32)
            .padding(.horizontal, 13)
            .background(
                Capsule().fill(isSelected ? Theme.ink : (hovering ? Theme.parchmentDeep : Theme.parchment))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Menu row hover

/// Hover + selected surface for rows inside custom popover menus. Native
/// `Menu`s get this for free; the app's own board/sort/filter popovers need it
/// explicitly so every menu responds to the pointer.
private struct MenuRowHoverModifier: ViewModifier {
    var isSelected: Bool
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isSelected ? Theme.parchmentDeep : Color.clear)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(hovering
                              ? (isSelected ? Color.black.opacity(0.035) : Theme.parchmentDeep.opacity(0.55))
                              : Color.clear)
                }
            }
            .onHover { inside in
                guard hovering != inside else { return }
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            }
    }
}

extension View {
    /// Apply after `contentShape` so the whole menu row is the hover target.
    func menuRowHover(isSelected: Bool = false, cornerRadius: CGFloat = 7) -> some View {
        modifier(MenuRowHoverModifier(isSelected: isSelected, cornerRadius: cornerRadius))
    }
}

// MARK: - Section label

struct SectionLabel: View {
    var text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.35)
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
    }
}

// MARK: - Image loading

/// Draws a decoded image from `ImageLoader`. Decoding happens off the main
/// actor at the target pixel size; a missing first candidate (the 640 px
/// `Cards/` derivative) falls through to the stored thumbnail/original.
struct LibraryImage: View {
    var paths: [String]
    var maxPixel: Int = 640
    /// Low-resolution image shown immediately while the target decodes.
    var placeholderPaths: [String] = []
    var placeholderMaxPixel: Int = 640
    var contentMode: ContentMode = .fill
    var placeholderIcon: String = "photo"
    /// Mat behind a fitted image. Cards keep the warm parchment; a board logo
    /// asks for paper so an uploaded transparent logo sits on white.
    var background: Color = Theme.parchmentDeep

    @State private var image: CGImage?
    @State private var placeholderImage: CGImage?
    @State private var failed = false
    @State private var loadedKey: String = ""
    @State private var placeholderKey: String = ""

    init(
        paths: [String],
        maxPixel: Int = 640,
        placeholderPaths: [String] = [],
        placeholderMaxPixel: Int = 640,
        contentMode: ContentMode = .fill,
        placeholderIcon: String = "photo",
        background: Color = Theme.parchmentDeep
    ) {
        self.paths = paths
        self.maxPixel = maxPixel
        self.placeholderPaths = placeholderPaths
        self.placeholderMaxPixel = placeholderMaxPixel
        self.contentMode = contentMode
        self.placeholderIcon = placeholderIcon
        self.background = background

        let key = "\(maxPixel)|" + paths.joined(separator: "|")
        let cached = ImageLoader.shared.cachedImage(paths: paths, maxPixel: maxPixel)
        let cachedLow = placeholderPaths.isEmpty
            ? nil
            : ImageLoader.shared.cachedImage(paths: placeholderPaths, maxPixel: placeholderMaxPixel)
        _image = State(initialValue: cached)
        _placeholderImage = State(initialValue: cachedLow)
        _loadedKey = State(initialValue: cached == nil ? "" : key)
        _placeholderKey = State(initialValue: cachedLow == nil ? "" : key)
    }

    private var loadKey: String { "\(maxPixel)|" + paths.joined(separator: "|") }

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            if let image, loadedKey == loadKey {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
            } else if let placeholderImage, placeholderKey == loadKey {
                Image(decorative: placeholderImage, scale: 2)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 22, weight: .light))
                    Text(T("Image unavailable"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.inkTertiary)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.inkTertiary.opacity(0.5))
            }
        }
        .task(id: loadKey) {
            if loadKey == loadedKey, image != nil { return }
            failed = false

            if let cached = ImageLoader.shared.cachedImage(paths: paths, maxPixel: maxPixel) {
                image = cached
                loadedKey = loadKey
                return
            }

            image = nil
            if placeholderPaths.isEmpty {
                placeholderImage = nil
            } else if let cachedLow = ImageLoader.shared.cachedImage(
                paths: placeholderPaths, maxPixel: placeholderMaxPixel
            ) {
                placeholderImage = cachedLow
            } else {
                placeholderImage = nil
                let low = await ImageLoader.shared.image(paths: placeholderPaths, maxPixel: placeholderMaxPixel)
                guard !Task.isCancelled else { return }
                placeholderImage = low
            }

            let loaded = await ImageLoader.shared.image(paths: paths, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
                loadedKey = loadKey
            } else {
                failed = true
            }
        }
        // A decoded image settles into the card instead of snapping over the
        // placeholder. Cached images are installed synchronously in `init`, so
        // this only animates the first decode of a given card.
        .animation(.easeOut(duration: 0.18), value: loadedKey)
    }
}

// MARK: - Board logo

/// Square badge used for a board's logo in the sidebar, the board header and
/// the logo picker. A pin thumbnail fills the square (it is a reference image);
/// an uploaded logo is fitted with a small inset and a hairline edge, because
/// wordmarks should not be cropped and often have transparency.
struct BoardLogoBadge: View {
    var display: BoardLogoDisplay?
    var accent: Color
    var size: CGFloat = 22
    var cornerRadius: CGFloat = 6
    var placeholderIcon: String = "photo"

    /// A chosen inspiration is still a full-bleed reference image; only an
    /// uploaded logo is fitted, because a wordmark should not be cropped.
    private var fitsImage: Bool {
        display?.isCustom == true && display?.pinID == nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fitsImage ? Theme.paper : accent.opacity(0.14))

            if let display, !display.paths.isEmpty {
                LibraryImage(
                    paths: display.paths,
                    maxPixel: Int(size * 3),
                    contentMode: fitsImage ? .fit : .fill,
                    placeholderIcon: placeholderIcon,
                    background: fitsImage ? Theme.paper : Theme.parchmentDeep
                )
                .padding(fitsImage ? max(1, size * 0.10) : 0)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundStyle(accent.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    fitsImage ? Theme.hairline : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Toast

struct ToastView: View {
    var toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 23, height: 23)
                .background(Circle().fill(Theme.red))
            Text(toast.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.ink.opacity(0.96))
                .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
        )
    }
}

// MARK: - Flow layout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct TagChip: View {
    var tag: String
    var removable: Bool = true
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    @State private var hovering = false
    @State private var removeHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text("#\(tag)")
                .font(.system(size: 11.5, weight: .medium))
            if removable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(removeHovering ? Theme.red : Theme.inkTertiary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(removeHovering ? Theme.redWash : Theme.ink.opacity(0.055)))
                }
                .buttonStyle(PointerPlainButtonStyle())
                .onHover { removeHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: removeHovering)
                .help(T("Remove tag"))
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.leading, 10)
        .padding(.trailing, removable ? 6 : 10)
        .frame(height: 27)
        .background(Capsule().fill(hovering ? Theme.parchmentDeep : Theme.parchment))
        .overlay(Capsule().strokeBorder(Theme.hairline.opacity(0.8), lineWidth: 1))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { onTap?() }
        .pointerCursor()
    }
}

// MARK: - Drop support

@MainActor
enum DropReceiver {
    @discardableResult
    static func handle(info: DropInfo, store: LibraryStore, board: String? = nil) -> Bool {
        handle(providers: info.itemProviders(for: [UTType.fileURL, UTType.image]), store: store, board: board)
    }

    @discardableResult
    static func handle(providers: [NSItemProvider], store: LibraryStore, board: String? = nil) -> Bool {
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var fileURLs: [URL] = []
        var imageDatas: [Data] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        lock.lock()
                        fileURLs.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            } else if let imageType = provider.registeredTypeIdentifiers.first(where: { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                    if let data {
                        lock.lock()
                        imageDatas.append(data)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                if !fileURLs.isEmpty {
                    await store.addFiles(fileURLs, sourceLabel: "Drag & drop", board: board)
                }
                for data in imageDatas {
                    await store.addImageData(data, preferredExtension: nil, sourceLabel: "Drag & drop", board: board)
                }
            }
        }
        return true
    }
}

// MARK: - AppKit import panel

@MainActor
enum ImportPanel {
    static func present(store: LibraryStore, board: String? = nil) {
        let panel = NSOpenPanel()
        panel.title = T("Add references to Lore")
        panel.prompt = T("Pin")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP, .bmp, .svg]
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                await store.addFiles(urls, sourceLabel: "Imported", board: board)
            }
        }
    }
}

// MARK: - Focus search notification

extension Notification.Name {
    static let loreFocusSearch = Notification.Name("lore.focusSearch")
    /// Posted when a mouse click lands outside the focused text control. Views
    /// holding a `@FocusState` mirror it so their focus styling clears even
    /// when AppKit resigns the field editor directly.
    static let loreResignTextFocus = Notification.Name("lore.resignTextFocus")
}

// MARK: - Click outside text fields

/// Watches mouse-downs for the host window. A click outside the focused text
/// control resigns the field editor and posts `loreResignTextFocus`, so note,
/// tag, title, and search editors all blur exactly once.
private enum TextFocusDismissal {
    static func resignIfClickOutside(_ event: NSEvent) {
        guard let window = event.window, let responder = window.firstResponder else { return }

        let controlFrame: NSRect
        if let textView = responder as? NSTextView {
            // The field editor covers the editable text; use the enclosing text
            // field when possible so the control's padding still counts as
            // inside.
            if let field = textView.superview as? NSTextField {
                controlFrame = field.convert(field.bounds, to: nil)
            } else {
                controlFrame = textView.convert(textView.bounds, to: nil)
            }
        } else if let textField = responder as? NSTextField {
            controlFrame = textField.convert(textField.bounds, to: nil)
        } else {
            return
        }

        guard !controlFrame.contains(event.locationInWindow) else { return }
        window.makeFirstResponder(nil)
        NotificationCenter.default.post(name: .loreResignTextFocus, object: nil)
    }
}

private struct TextFocusDismissalModifier: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                    TextFocusDismissal.resignIfClickOutside(event)
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }
}

extension View {
    func dismissTextFocusOnClickOutside() -> some View {
        modifier(TextFocusDismissalModifier())
    }
}