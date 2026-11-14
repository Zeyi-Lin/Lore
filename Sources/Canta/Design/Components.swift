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
            window.isMovableByWindowBackground = true
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

struct CantaMark: View {
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

enum CantaButtonVariant {
    case primary
    case secondary
    case ghost
    case dark
}

struct CantaButton: View {
    var title: String
    var icon: String?
    var variant: CantaButtonVariant = .primary
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
                        .font(Theme.mono(10.5, weight: .medium))
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
    var contentMode: ContentMode = .fill
    var placeholderIcon: String = "photo"

    @State private var image: CGImage?
    @State private var failed = false

    private var loadKey: String { "\(maxPixel)|" + paths.joined(separator: "|") }

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.parchmentDeep)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: contentMode)
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
            image = nil
            failed = false
            let loaded = await ImageLoader.shared.image(paths: paths, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
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
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Theme.ink.opacity(0.055)))
                }
                .buttonStyle(PointerPlainButtonStyle())
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
        panel.title = T("Add references to Canta")
        panel.prompt = T("Pin")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP, .bmp]
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
    static let cantaFocusSearch = Notification.Name("canta.focusSearch")
}