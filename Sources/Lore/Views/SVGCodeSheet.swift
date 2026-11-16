import SwiftUI
import AppKit
import LoreAgentKit

/// "Paste SVG code" surface: a monospaced editor, a live vector preview and the
/// same title/board fields the capture sheet uses. The code is normalised and
/// stored as the pin's original, so the Agent API can hand the real vector to a
/// coding agent later.
struct SVGCodeSheet: View {
    @Environment(LibraryStore.self) private var store
    @State private var code = ""
    @State private var title = ""
    @State private var board = "Unsorted"
    @State private var preview: NSImage?
    @State private var intrinsicSize: CGSize?
    @State private var invalid = false
    @State private var isAdding = false
    @State private var boardMenuHovering = false
    @State private var previewTask: Task<Void, Never>?
    @FocusState private var codeFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.36)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                VStack(alignment: .leading, spacing: 0) {
                    header
                    HStack(alignment: .top, spacing: 14) {
                        editorPane
                        previewPane
                    }
                    .padding(.top, 20)
                    titleField
                        .padding(.top, 14)
                    Divider()
                        .overlay(Theme.hairline)
                        .padding(.top, 20)
                    footer
                        .padding(.top, 16)
                }
                .padding(26)
                .frame(width: min(780, geo.size.width - 80))
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 50, y: 22)
                .overlay(alignment: .topTrailing) {
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 29, height: 29)
                            .background(Circle().fill(Theme.parchment))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(16)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.975)))
        .onAppear {
            board = store.selectedBoard ?? store.defaultBoard
            if code.isEmpty, let clipboard = Clipboard.svgCode() {
                code = clipboard
            }
            evaluate(code)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { codeFocused = true }
        }
        .onDisappear { previewTask?.cancel() }
        .onChange(of: code) { _, newValue in
            schedulePreview(for: newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(Theme.red).frame(width: 5, height: 5)
                Text(T("PASTE VECTOR"))
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(Theme.inkTertiary)
            }

            Text(T("Add SVG code."))
                .font(.system(size: 26, weight: .bold))
                .tracking(-1)
                .foregroundStyle(Theme.ink)

            Text(T("Paste the markup of a logo, icon or illustration. Lore stores the vector itself and renders it at any size."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 30)
    }

    // MARK: - Editor

    private var editorPane: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.parchment.opacity(0.55))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)

            if code.isEmpty {
                Text(T("Paste <svg> markup here…"))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkTertiary.opacity(0.85))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $code)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .focused($codeFocused)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    // MARK: - Preview

    private var previewPane: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))

                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(18)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: invalid ? "exclamationmark.triangle" : "square.on.circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(invalid ? Theme.red : Theme.inkTertiary)
                        Text(invalid ? T("That isn't a valid SVG document.") : T("Live preview"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(invalid ? Theme.red : Theme.inkTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .frame(height: 300)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(invalid ? Theme.red.opacity(0.4) : Theme.hairline, lineWidth: 1)
            )

            HStack(spacing: 5) {
                Image(systemName: PinKind.svg.icon)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(sizeLabel)
                    .font(Theme.mono(9.5, weight: .medium))
            }
            .foregroundStyle(Theme.inkTertiary)
        }
        .frame(width: 232)
    }

    private var sizeLabel: String {
        guard let intrinsicSize else {
            return code.isEmpty ? T("No markup yet") : T("Waiting for markup")
        }
        return "\(Int(intrinsicSize.width.rounded())) × \(Int(intrinsicSize.height.rounded())) · SVG"
    }

    // MARK: - Title

    private var titleField: some View {
        TextField(T("Title (optional)"), text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Text(T("ADD TO"))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkTertiary)
                Menu {
                    ForEach(store.allBoardNames, id: \.self) { name in
                        Button {
                            board = name
                        } label: {
                            if board == name {
                                Label(localizedBoard(name), systemImage: "checkmark")
                            } else {
                                Label(localizedBoard(name), systemImage: "circle.fill")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.boardColor(board)).frame(width: 6, height: 6)
                        Text(localizedBoard(board))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .background(Capsule().fill(boardMenuHovering ? Theme.parchmentDeep : Theme.parchment))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .onHover { boardMenuHovering = $0 }
                .animation(.easeOut(duration: 0.14), value: boardMenuHovering)
                .focusable(false)
                .fixedSize()
                .pointerCursor()
            }

            Spacer(minLength: 0)

            LoreButton(title: T("Cancel"), variant: .ghost) { close() }

            LoreButton(
                title: isAdding ? T("Adding…") : T("Pin SVG"),
                icon: "pin.fill",
                variant: .primary,
                shortcut: "⌘↩"
            ) {
                submit()
            }
            .disabled(!canPin)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - State

    private var canPin: Bool {
        !isAdding && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !invalid && preview != nil
    }

    private func schedulePreview(for text: String) {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            evaluate(text)
        }
    }

    private func evaluate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = nil
            intrinsicSize = nil
            invalid = false
            return
        }
        guard let markup = SVGRasterizer.normalizedMarkup(trimmed),
              let data = markup.data(using: .utf8),
              let size = SVGRasterizer.intrinsicSize(data: data),
              let image = NSImage(data: data) else {
            preview = nil
            intrinsicSize = nil
            invalid = true
            return
        }
        preview = image
        intrinsicSize = size
        invalid = false
    }

    private func submit() {
        guard canPin else { return }
        let markup = code
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetBoard = board
        isAdding = true
        Task { @MainActor in
            let added = await store.addSVGCode(
                markup,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                sourceLabel: "SVG code",
                board: targetBoard
            )
            isAdding = false
            if added { close() }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            store.svgPastePresented = false
        }
    }
}
