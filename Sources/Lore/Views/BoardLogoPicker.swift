import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Board logo picker. A board's logo defaults to its first pin; here the user
/// can keep that default, pick any inspiration instead, or upload an image.
/// Everything applies immediately — there is no draft state to lose — so the
/// picker just closes when the user is done.
struct BoardLogoPicker: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var importing = false
    /// Local ⌘V monitor; text fields (the search box) keep the standard paste.
    @State private var pasteMonitor: Any?
    @State private var hoveredPinID: UUID?
    @FocusState private var searchFocused: Bool

    private var board: String? { store.boardLogoEditor }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.34)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                if let board {
                    panel(for: board)
                        .frame(width: min(640, geo.size.width - 96))
                        .frame(maxHeight: min(730, geo.size.height - 96))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.975)))
        .onAppear { installPasteMonitor() }
        .onDisappear { removePasteMonitor() }
    }

    // MARK: - Panel

    private func panel(for board: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: board)

            currentLogoCard(for: board)
                .padding(.top, 18)

            Divider()
                .overlay(Theme.hairline)
                .padding(.vertical, 16)

            inspirationHeader

            inspirationGrid(for: board)
                .padding(.top, 11)
        }
        .padding(24)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 48, y: 22)
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private func header(for board: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(T("Board logo"))
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.9)
                .foregroundStyle(Theme.ink)

            Text(TF("Pick an inspiration for “%@”, or upload or paste your own image. By default a board uses its first image.", localizedBoard(board)))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 34)
    }

    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 29, height: 29)
                .background(Circle().fill(Theme.parchment))
        }
        .buttonStyle(PressableStyle())
        .padding(16)
        .help(T("Close"))
    }

    // MARK: - Current logo

    private func currentLogoCard(for board: String) -> some View {
        let display = store.boardLogoDisplay(for: board)
        let custom = store.hasCustomBoardLogo(board)
        let pinTitle = display?.pinID.flatMap { store.pin(id: $0)?.title }

        return HStack(spacing: 15) {
            BoardLogoBadge(
                display: display,
                accent: Theme.boardColor(BoardPath.segments(board).first ?? board),
                size: 66,
                cornerRadius: 18,
                placeholderIcon: "photo.badge.plus"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceTitle(display: display, custom: custom, pinTitle: pinTitle))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)

                Text(custom
                     ? T("This logo appears in the sidebar and above the board.")
                     : T("The first image in this board is used automatically."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 6) {
                    compactButton(title: T("Paste"), icon: "doc.on.clipboard") {
                        pasteFromClipboard(for: board)
                    }
                    .help(T("Paste from clipboard (⌘V)"))
                    .disabled(importing)

                    compactButton(
                        title: importing ? T("Importing…") : T("Upload image…"),
                        icon: importing ? "hourglass" : "square.and.arrow.up",
                        filled: true
                    ) {
                        guard !importing else { return }
                        chooseUpload(for: board)
                    }
                    .disabled(importing)
                }

                if custom {
                    compactButton(title: T("Use first image"), icon: "arrow.uturn.backward") {
                        store.resetBoardLogo(for: board)
                    }
                    .disabled(importing)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.parchment.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func sourceTitle(display: BoardLogoDisplay?, custom: Bool, pinTitle: String?) -> String {
        if !custom {
            return display == nil
                ? T("No image yet")
                : T("Default · first image in this board")
        }
        if let pinTitle, !pinTitle.isEmpty {
            return TF("Inspiration · “%@”", pinTitle)
        }
        return T("Custom image")
    }

    // MARK: - Inspiration picker

    private var inspirationHeader: some View {
        HStack(spacing: 10) {
            Text(T("Choose from your inspirations"))
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.inkTertiary)
                .textCase(.uppercase)

            Spacer(minLength: 8)

            searchField
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            TextField(T("Search inspirations"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.parchment))
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(searchFocused ? Theme.paper : Theme.parchment)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Theme.ink.opacity(0.24) : Theme.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.14), value: searchFocused)
    }

    /// Fixed cell count so the panel can size itself to its content instead of
    /// leaving a tall empty scroll area under two rows. Wider windows keep the
    /// same 8-column rhythm; the panel itself is capped at 640 pt.
    private let logoGridColumnCount = 8

    private func inspirationGrid(for board: String) -> some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = needle.isEmpty
            ? store.pins
            : store.pins.filter { pinMatches($0, needle: needle) }
        let boardMatches = matches.filter { pin in
            BoardPath.key(pin.board) == BoardPath.key(board)
        }
        let otherMatches = matches.filter { pin in
            BoardPath.key(pin.board) != BoardPath.key(board)
        }

        return Group {
            if store.pins.isEmpty {
                emptyMessage(T("Add an inspiration first — the picker shows images from your library."))
            } else if matches.isEmpty {
                emptyMessage(T("No inspirations match this search."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if !boardMatches.isEmpty {
                            section(
                                title: TF("In this board · %ld", boardMatches.count),
                                pins: boardMatches,
                                currentPinID: store.boardLogoDisplay(for: board)?.pinID,
                                board: board
                            )
                        }
                        if !otherMatches.isEmpty {
                            section(
                                title: sectionTitle(for: otherMatches, searching: !needle.isEmpty),
                                pins: otherMatches,
                                currentPinID: store.boardLogoDisplay(for: board)?.pinID,
                                board: board
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(height: gridContentHeight(boardMatches.count, otherMatches.count))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Height of the pin grid for the rows it actually shows, capped so a large
    /// library scrolls instead of pushing the panel off screen.
    private func gridContentHeight(_ firstCount: Int, _ secondCount: Int) -> CGFloat {
        var height: CGFloat = 0
        for (index, count) in [firstCount, secondCount].enumerated() where count > 0 {
            if index > 0, height > 0 { height += 14 }
            let rows = max(1, Int(ceil(Double(count) / Double(logoGridColumnCount))))
            height += 20 + CGFloat(rows) * 62 + CGFloat(max(rows - 1, 0)) * 8
        }
        return min(300, max(96, height + 4))
    }

    private func sectionTitle(for pins: [Pin], searching: Bool) -> String {
        if searching { return TF("%ld results", pins.count) }
        return TF("All inspirations · %ld", pins.count)
    }

    private func section(title: String, pins: [Pin], currentPinID: UUID?, board: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(62), spacing: 8),
                    count: logoGridColumnCount
                ),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(pins) { pin in
                    pinCell(pin, isCurrent: currentPinID == pin.id, board: board)
                }
            }
        }
    }

    private func pinCell(_ pin: Pin, isCurrent: Bool, board: String) -> some View {
        Button {
            store.setBoardLogo(pinID: pin.id, for: board)
        } label: {
            LibraryImage(
                paths: store.cardImageCandidates(for: pin),
                maxPixel: 160,
                contentMode: .fill,
                placeholderIcon: "photo"
            )
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isCurrent ? Theme.red : (hoveredPinID == pin.id ? Theme.ink.opacity(0.2) : Theme.cardBorder),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.red))
                        .padding(4)
                }
            }
            .scaleEffect(hoveredPinID == pin.id ? 1.035 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: hoveredPinID)
        }
        .buttonStyle(PointerPlainButtonStyle())
        .onHover { hovering in
            hoveredPinID = hovering ? pin.id : (hoveredPinID == pin.id ? nil : hoveredPinID)
        }
        .help(pin.title)
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Footer bits

    private func compactButton(
        title: String,
        icon: String,
        filled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.white : Theme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? Theme.ink : Theme.paper)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(filled ? Color.clear : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .opacity(importing && filled ? 0.6 : 1)
    }

    // MARK: - Actions

    private func chooseUpload(for board: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = T("Choose an image to use as the board logo")
        panel.prompt = T("Use as logo")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importing = true
        Task { @MainActor in
            _ = await store.importBoardLogo(from: url, for: board)
            importing = false
        }
    }

    private func pasteFromClipboard(for board: String) {
        guard !importing else { return }
        importing = true
        Task { @MainActor in
            _ = await store.importBoardLogoFromClipboard(for: board)
            importing = false
        }
    }

    // MARK: - Keyboard paste

    /// ⌘V imports a clipboard image into the logo slot, matching the app's
    /// paste-anywhere habit. It is deliberately suppressed while a text field
    /// has focus so the search box still pastes text, and while a modal panel
    /// (the upload browser) is open.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Clipboard.isPasteShortcut(event),
                  !Clipboard.isTextInputFocused(),
                  NSApp.modalWindow == nil,
                  event.window === NSApp.mainWindow,
                  Clipboard.containsImage(),
                  let board = MainActor.assumeIsolated({ store.boardLogoEditor }),
                  !MainActor.assumeIsolated({ importing }) else { return event }
            Task { @MainActor in
                importing = true
                _ = await store.importBoardLogoFromClipboard(for: board)
                importing = false
            }
            return nil
        }
    }

    private func removePasteMonitor() {
        guard let pasteMonitor else { return }
        self.pasteMonitor = nil
        // Removing a monitor from inside its own callback is fragile; let the
        // current event finish first.
        DispatchQueue.main.async {
            NSEvent.removeMonitor(pasteMonitor)
        }
    }

    private func pinMatches(_ pin: Pin, needle: String) -> Bool {
        let haystack = [
            pin.title,
            pin.board,
            localizedBoard(pin.board),
            pin.note,
            pin.tags.joined(separator: " ")
        ].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(needle)
    }

    private func close() {
        store.boardLogoEditor = nil
    }
}
