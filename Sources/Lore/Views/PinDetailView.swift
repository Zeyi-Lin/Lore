import SwiftUI
import AppKit
import LoreAgentKit

struct PinDetailOverlay: View {
    let pin: Pin

    @Environment(LibraryStore.self) private var store
    @State private var showDeleteAlert = false
    @State private var tagEntry = ""
    @State private var showNewBoardField = false
    @State private var newBoardName = ""
    @State private var showBoardMenu = false
    @State private var isImageMode = UserDefaults.standard.bool(forKey: "lore.debugLargeImage")
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var scrollNavigator = ScrollNavigationAccumulator()
    @State private var detailStage = 0
    @State private var isEditingTitle = false
    @State private var isEditingNote = false
    @State private var boardMenuHovering = false
    @State private var moreMenuHovering = false
    @State private var noteHovering = false
    @State private var tagHovering = false
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var noteFieldFocused: Bool
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let metrics = DetailCardMetrics(available: geo.size, aspectRatio: pin.aspectRatio)

            ZStack {
                Color.black.opacity(isImageMode ? 0.86 : 0.46)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if isImageMode {
                            exitImageMode()
                        } else {
                            store.dismissDetail()
                        }
                    }

                if isImageMode {
                    LargeImageViewer(pin: pin, onExit: exitImageMode)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    regularCard(metrics: metrics)
                        .transition(.opacity)

                    if store.filteredPins.count > 1 {
                        HStack {
                            navButton(icon: "chevron.left", offset: -1)
                                .padding(.leading, 22)
                            Spacer()
                            navButton(icon: "chevron.right", offset: 1)
                                .padding(.trailing, 22)
                        }
                        .frame(width: geo.size.width)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            installKeyMonitor()
            installScrollMonitor()
            store.prefetchNeighbors(around: pin)
            if detailStage == 0 {
                // Let the lightweight shell commit its first frame before the
                // metadata editor and the heavier sections are built.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    detailStage = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        detailStage = 2
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .loreResignTextFocus)) { _ in
            titleFieldFocused = false
            noteFieldFocused = false
            tagFieldFocused = false
            isEditingTitle = false
            isEditingNote = false
        }
        .onChange(of: pin.id) { _, _ in
            titleFieldFocused = false
            noteFieldFocused = false
            tagFieldFocused = false
            isEditingTitle = false
            isEditingNote = false
            tagEntry = ""
            noteHovering = false
            tagHovering = false
            boardMenuHovering = false
            scrollNavigator.reset()
            store.prefetchNeighbors(around: pin)
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            }
        }
        .onExitCommand {
            if isEditingTitle {
                isEditingTitle = false
                return
            }
            if isEditingNote {
                isEditingNote = false
                return
            }
            if isImageMode {
                exitImageMode()
            } else {
                store.dismissDetail()
            }
        }
        .alert(T("Delete this pin?"), isPresented: $showDeleteAlert) {
            Button(T("Delete"), role: .destructive) { store.deletePin(pin) }
            Button(T("Cancel"), role: .cancel) { }
        } message: {
            Text(T("The original image and its metadata will be removed from Lore."))
        }
    }

    private func regularCard(metrics: DetailCardMetrics) -> some View {
        HStack(spacing: 0) {
            imagePane(metrics: metrics)
                .frame(width: metrics.imageWidth)
            metaPane(metrics: metrics)
                .frame(width: metrics.metaWidth)
        }
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 30, x: 0, y: 18)
        .overlay(alignment: .topTrailing) {
            Button {
                store.dismissDetail()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 35, height: 35)
                    .background(Circle().fill(Theme.paper))
                    .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .offset(x: 13, y: -13)
            .help(T("Close"))
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous))
    }

    private func exitImageMode() {
        withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            if event.keyCode == 53 {
                if isEditingTitle {
                    titleFieldFocused = false
                    isEditingTitle = false
                    return nil
                }
                if isEditingNote {
                    noteFieldFocused = false
                    isEditingNote = false
                    return nil
                }
                if tagFieldFocused {
                    tagFieldFocused = false
                    return nil
                }
            }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            switch event.keyCode {
            case 123:
                guard store.filteredPins.count > 1 else { return event }
                store.showAdjacentPin(offset: -1)
                return nil
            case 124:
                guard store.filteredPins.count > 1 else { return event }
                store.showAdjacentPin(offset: 1)
                return nil
            case 53:
                if isImageMode {
                    exitImageMode()
                } else {
                    store.dismissDetail()
                }
                return nil
            default:
                return event
            }
        }
    }

    /// Wheel/trackpad scrolling steps through the gallery while the detail is
    /// open. Image mode keeps the wheel for zoom, and a focused text editor
    /// keeps it for its own scrolling.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard !isImageMode else { return event }
            guard let mainWindow = NSApp.mainWindow, event.window === mainWindow else { return event }
            if let responder = event.window?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            // A trackpad flick keeps emitting momentum after the fingers lift;
            // swallow it so one flick moves exactly one pin.
            if !event.momentumPhase.isEmpty { return nil }
            if event.phase == .began || event.phase == .ended || event.phase == .cancelled {
                scrollNavigator.reset()
            }
            guard store.filteredPins.count > 1 else { return event }
            guard let offset = scrollNavigator.step(
                deltaY: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas
            ) else { return nil }
            store.showAdjacentPin(offset: offset)
            return nil
        }
    }

    // MARK: - Image side

    private func imagePane(metrics: DetailCardMetrics) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xEFEAE2), Color(hex: 0xE7E1D7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.5), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 430
            )

            detailImage(metrics: metrics)
                .padding(metrics.imagePadding)

            VStack {
                HStack {
                    detailChip(icon: pin.mediaIcon, text: pin.mediaLabel)
                    Spacer()
                    detailChip(icon: "rectangle.dashed", text: pin.pixelLabel)
                }
                Spacer()
                HStack {
                    Button {
                        store.openOriginal(pin)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text(T("Open original"))
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(Theme.paper.opacity(0.88)))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    Spacer()
                    Text(TF("%ld-color palette", pin.colors.count))
                        .font(Theme.mono(9, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .padding(18)
        }
        .clipped()
    }

    /// The hero image. It is itself the affordance for the image-only view, so
    /// a single click expands it; the adaptive mat around it stays inert.
    private func detailImage(metrics: DetailCardMetrics) -> some View {
        Color.clear
            .aspectRatio(max(pin.aspectRatio, 0.05), contentMode: .fit)
            .overlay {
                if pin.isGIF {
                    ZStack {
                        LibraryImage(
                            paths: store.cardImageCandidates(for: pin),
                            maxPixel: 640,
                            contentMode: .fill
                        )
                        AnimatedGIFView(paths: store.largeImageCandidates(for: pin))
                            .allowsHitTesting(false)
                    }
                } else {
                    LibraryImage(
                        paths: store.detailImageCandidates(for: pin),
                        maxPixel: ImageLoader.detailMaxPixel,
                        placeholderPaths: store.cardImageCandidates(for: pin),
                        placeholderMaxPixel: 640,
                        contentMode: .fill
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: metrics.imageCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.imageCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: metrics.imageCornerRadius, style: .continuous))
            .onTapGesture { enterImageMode() }
            .help(T("Click to open large image"))
            .pointerCursor()
    }

    private func enterImageMode() {
        withAnimation(.snappy(duration: 0.28)) { isImageMode = true }
    }

    private func detailChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Theme.mono(9.5, weight: .medium))
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Theme.paper.opacity(0.85)))
        .overlay(Capsule().strokeBorder(Theme.hairline.opacity(0.75), lineWidth: 1))
    }

    // MARK: - Metadata side

    private func metaPane(metrics: DetailCardMetrics) -> some View {
        VStack(spacing: 0) {
            Group {
                if detailStage >= 1 {
                    actionRow
                } else {
                    HStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.parchment)
                            .frame(width: 92, height: 24)
                        Spacer()
                        Circle().fill(Theme.parchment).frame(width: 30, height: 30)
                        Circle().fill(Theme.parchment).frame(width: 30, height: 30)
                        Circle().fill(Theme.parchment).frame(width: 30, height: 30)
                    }
                    .frame(height: 35)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.metaPadding)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Hairline()

            ScrollView(showsIndicators: false) {
                metaSections(metrics: metrics)
            }

            // Keep the destructive/secondary actions anchored to the card's
            // bottom edge: on tall displays the metadata column is shorter
            // than the card, and a scrolling footer would leave it floating
            // mid-pane.
            if detailStage >= 2 {
                Hairline()
                footerActions
                    .padding(.horizontal, metrics.metaPadding)
                    .padding(.vertical, 15)
            }
        }
        .background(Theme.paper)
    }

    @ViewBuilder
    private func metaSections(metrics: DetailCardMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            titleSection

            if detailStage >= 1 {
                noteSection
                tagsSection
            } else {
                detailSkeleton(rows: 4)
            }

            if detailStage >= 2 {
                paletteSection
                agentSection
                metadataSection
            } else {
                detailSkeleton(rows: 8)
            }
        }
        .padding(.horizontal, metrics.metaPadding)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    /// Cheap placeholder for the deferred metadata sections, so the first
    /// frame does not lay out the full editor.
    private func detailSkeleton(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.parchment.opacity(row.isMultiple(of: 3) ? 0.9 : 0.55))
                    .frame(width: row.isMultiple(of: 3) ? 140 : 230, height: 10)
            }
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            boardMenu

            Spacer()

            CircleActionButton(icon: "arrow.up.left.and.arrow.down.right", label: T("Large image"), size: 35) {
                enterImageMode()
            }
            .help(T("Large image"))

            CircleActionButton(icon: pin.isFavorite ? "heart.fill" : "heart", size: 35) {
                store.toggleFavorite(pin)
            }
            .help(pin.isFavorite ? "Remove from favorites" : "Add to favorites")

            CircleActionButton(icon: "doc.on.doc", size: 35) {
                store.copyAgentSnippet(for: pin)
            }
            .help(T("Copy agent snippet"))

            moreMenu
        }
    }

    private var boardMenu: some View {
        Button {
            showBoardMenu.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.boardColor(pin.board))
                    .frame(width: 6, height: 6)
                Text(localizedBoard(pin.board))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(Capsule().fill(boardMenuHovering ? Theme.parchmentDeep : Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .onHover { boardMenuHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: boardMenuHovering)
        .popover(isPresented: $showBoardMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.allBoardNames, id: \.self) { board in
                    Button {
                        store.movePin(pin.id, toBoard: board)
                        showBoardMenu = false
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.boardColor(board))
                                .frame(width: 6, height: 6)
                            Text(localizedBoard(board))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if board.caseInsensitiveCompare(pin.board) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.red)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .menuRowHover(isSelected: board.caseInsensitiveCompare(pin.board) == .orderedSame)
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                }
                Divider()
                Button {
                    showNewBoardField = true
                    showBoardMenu = false
                } label: {
                    Label(T("New board…"), systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .menuRowHover()
                }
                .buttonStyle(PointerPlainButtonStyle())
            }
            .padding(6)
            .frame(width: 210)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(T("Copy image")) { store.copyImage(pin) }
            Button(T("Copy pin JSON")) { store.copyPinJSON(pin) }
            Button(T("Copy image URL")) {
                store.copyText(store.apiImageURL(for: pin), message: T("Image URL copied"), icon: "link")
            }
            Divider()
            Button(T("Open original")) { store.openOriginal(pin) }
            if pin.sourceURL != nil {
                Button(T("Open source page")) { store.openSource(pin) }
            }
            Button(T("Reveal in Finder")) { store.revealPin(pin) }
            Divider()
            Button(T("Delete pin"), role: .destructive) { showDeleteAlert = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 35, height: 35)
                .background(Circle().fill(moreMenuHovering ? Theme.parchmentDeep : Theme.paper))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .pointerCursor()
        .onHover { moreMenuHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: moreMenuHovering)
        .help(T("More actions"))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingTitle {
                TextField(T("Untitled pin"), text: titleBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...3)
                    .focused($titleFieldFocused)
                    .onAppear {
                        DispatchQueue.main.async { titleFieldFocused = true }
                    }
                    .onSubmit {
                        titleFieldFocused = false
                        isEditingTitle = false
                    }
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { isEditingTitle = false }
                    }
            } else {
                Text(pin.title.isEmpty ? T("Untitled pin") : pin.title)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.9)
                    .foregroundStyle(pin.title.isEmpty ? Theme.inkTertiary : Theme.ink)
                    .lineLimit(1...3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditingTitle = true }
                    .help(T("Click to edit"))
            }

            HStack(spacing: 7) {
                if let sourceLabel = localizedSourceLabel(pin.sourceLabel) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                    if let sourceURL = pin.sourceURL, let url = URL(string: sourceURL) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text(sourceLabel).underline()
                        }
                        .buttonStyle(PointerPlainButtonStyle())
                    } else {
                        Text(sourceLabel)
                    }
                    Text("·")
                }
                Text(TF("Captured %@", pin.createdAt.loreShort))
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)

            if showNewBoardField {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField(T("New board name"), text: $newBoardName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 10)
                            .frame(height: 29)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.parchment))
                            .help(T("Use “/” to nest boards, e.g. Linear/Settings"))
                        Button(T("Move")) {
                            let name = newBoardName.trimmed
                            guard !name.isEmpty else { return }
                            store.movePin(pin.id, toBoard: name)
                            newBoardName = ""
                            showNewBoardField = false
                        }
                        .buttonStyle(PointerPlainButtonStyle())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                        Button {
                            showNewBoardField = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .buttonStyle(PointerPlainButtonStyle())
                    }
                    Text(T("Use “/” to nest boards, e.g. Linear/Settings"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.leading, 2)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(
                text: T("Design note"),
                trailing: isEditingNote
                    ? "\(noteBinding.wrappedValue.count)"
                    : (noteHovering ? T("Edit") : nil)
            )

            Group {
                if isEditingNote {
                    TextField(T("What makes this worth copying? Layout, type, color…"), text: noteBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($noteFieldFocused)
                        .onAppear {
                            DispatchQueue.main.async { noteFieldFocused = true }
                        }
                        .onSubmit {
                            noteFieldFocused = false
                            isEditingNote = false
                        }
                        .onChange(of: noteFieldFocused) { _, focused in
                            if !focused { isEditingNote = false }
                        }
                } else {
                    Text(pin.note.isEmpty
                         ? T("What makes this worth copying? Layout, type, color…")
                         : pin.note)
                        .foregroundStyle(pin.note.isEmpty ? Theme.inkTertiary : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditingNote = true }
                        .help(T("Click to edit"))
                        .pointerCursor()
                }
            }
            .font(.system(size: 12))
            .lineSpacing(3)
            .lineLimit(2...8)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEditingNote || noteHovering ? Theme.paper : Theme.parchment)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isEditingNote
                            ? Theme.ink.opacity(0.24)
                            : (noteHovering ? Theme.ink.opacity(0.14) : Theme.hairline.opacity(0.8)),
                        lineWidth: isEditingNote ? 1.4 : 1
                    )
            )
            .shadow(
                color: .black.opacity(noteHovering && !isEditingNote ? 0.05 : 0),
                radius: 8,
                y: 3
            )
            .onHover { inside in
                guard noteHovering != inside else { return }
                withAnimation(.easeOut(duration: 0.16)) { noteHovering = inside }
            }
            .animation(.easeOut(duration: 0.16), value: isEditingNote)

            if isEditingNote {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9, weight: .semibold))
                    Text(T("Auto-saved · Esc to finish"))
                        .font(.system(size: 9.5, weight: .medium))
                    Spacer()
                    Button {
                        noteFieldFocused = false
                        isEditingNote = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(T("Done"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.ink))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                    .help(T("Finish editing"))
                }
                .foregroundStyle(Theme.inkTertiary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isEditingNote)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: T("Tags"), trailing: "\(pin.tags.count)")

            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(pin.tags, id: \.self) { tag in
                    TagChip(tag: tag, onRemove: {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.removeTag(tag, from: pin.id)
                        }
                    })
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                }

                tagEntryField
            }
            .animation(.snappy(duration: 0.22), value: pin.tags)

            if tagFieldFocused, !tagSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("Suggested tags"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(Theme.inkTertiary)

                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(tagSuggestions, id: \.self) { suggestion in
                            TagSuggestionChip(tag: suggestion) {
                                addTag(suggestion)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: tagFieldFocused)
    }

    private var tagEntryField: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .scaleEffect(tagFieldFocused ? 1.18 : 1)
                .foregroundStyle(tagFieldFocused ? Theme.inkSecondary : Theme.inkTertiary)

            TextField(T("Add tag"), text: $tagEntry)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 68)
                .focused($tagFieldFocused)
                .onSubmit { commitTagEntry() }

            if !tagEntry.isEmpty {
                Text("↵")
                    .font(Theme.mono(8.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(
            Capsule().fill(
                tagFieldFocused
                    ? Theme.parchmentDeep
                    : (tagHovering ? Theme.parchmentDeep.opacity(0.55) : Theme.paper)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                tagFieldFocused ? Theme.ink.opacity(0.28) : Theme.hairline,
                style: StrokeStyle(
                    lineWidth: tagFieldFocused ? 1.2 : 1,
                    dash: tagFieldFocused ? [] : [3, 3]
                )
            )
        )
        .contentShape(Capsule())
        .onHover { tagHovering = $0 }
        .onTapGesture { tagFieldFocused = true }
        .shadow(color: .black.opacity(tagFieldFocused ? 0.04 : 0), radius: 5, y: 1)
        .animation(.easeOut(duration: 0.14), value: tagFieldFocused)
        .animation(.easeOut(duration: 0.14), value: tagHovering)
        .help(T("Press ↵ to add"))
    }

    private var tagSuggestions: [String] {
        let query = tagEntry.trimmed.lowercased()
        let existing = Set(pin.tags.map { $0.lowercased() })
        return store.allTags
            .map { $0.name }
            .filter { !existing.contains($0.lowercased()) }
            .filter { query.isEmpty || $0.lowercased().contains(query) }
            .prefix(6)
            .map { $0 }
    }

    private func commitTagEntry() {
        let parts = tagEntry.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
        guard !parts.isEmpty else { return }
        withAnimation(.snappy(duration: 0.2)) {
            for part in parts {
                store.addTag(String(part), to: pin.id)
            }
        }
        tagEntry = ""
        tagFieldFocused = true
    }

    private func addTag(_ tag: String) {
        withAnimation(.snappy(duration: 0.2)) {
            store.addTag(tag, to: pin.id)
        }
        tagEntry = ""
        tagFieldFocused = true
    }

    private var paletteSection: some View {
        let profile = pin.colorProfile
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionLabel(text: T("Palette"))
                HStack(spacing: 3) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 7.5, weight: .semibold))
                    Text(T("Auto-detected"))
                        .font(.system(size: 8.5, weight: .medium))
                }
                .foregroundStyle(Theme.inkTertiary)
                .help(T("Detected from the image's OKLCH hue, chroma, and lightness."))
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(profile.families, id: \.self) { family in
                    colorFamilyPill(family, isPrimary: family == profile.family)
                }
                if profile.isMulticolor {
                    colorFamilyPill(.multicolor, isPrimary: false)
                }
                Button {
                    store.applyColorFilter(tone: profile.tone)
                    store.dismissDetail()
                } label: {
                    Text(profile.tone.localizedTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(Capsule().fill(Theme.parchment))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PointerPlainButtonStyle())
                .help(T("Show pins with this tone"))
            }

            HStack(spacing: 8) {
                ForEach(Array(pin.colors.prefix(5).enumerated()), id: \.offset) { _, hex in
                    Button {
                        store.copyText(hex, message: TF("%@ copied", hex), icon: "paintpalette")
                    } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(hexString: hex) ?? Theme.parchmentDeep)
                                .frame(height: 27)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            Text(hex.uppercased())
                                .font(Theme.mono(7.8, weight: .medium))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                    .help(TF("Copy %@", hex))
                }
            }
        }
    }

    private func colorFamilyPill(_ family: LoreColorFamily, isPrimary: Bool) -> some View {
        Button {
            store.applyColorFilter(family: family)
            store.dismissDetail()
        } label: {
            HStack(spacing: 5) {
                ColorFamilySwatch(family: family, size: 8)
                Text(family.localizedTitle)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(isPrimary ? Color.white : Theme.inkSecondary)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(Capsule().fill(isPrimary ? Theme.ink : Theme.parchment))
            .overlay(
                Capsule().strokeBorder(isPrimary ? Color.clear : Theme.hairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .help(T("Show pins in this color family"))
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Theme.redWash)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.red)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(T("Agent-ready"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(T("Metadata + image stream, one fetch away."))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkTertiary)
                }
                Spacer()
            }

            Button {
                store.copyText(store.apiImageURL(for: pin), message: T("Image URL copied"), icon: "link")
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                    Text(store.apiImageURL(for: pin))
                        .font(Theme.mono(9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 10)
                .frame(height: 31)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.paper))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PointerPlainButtonStyle())

            HStack(spacing: 7) {
                SmallPillButton(title: T("Copy snippet"), icon: "doc.on.doc") {
                    store.copyAgentSnippet(for: pin)
                }
                SmallPillButton(title: T("Copy JSON"), icon: "curlybraces") {
                    store.copyPinJSON(pin)
                }
                SmallPillButton(title: T("Copy image"), icon: "photo.on.rectangle") {
                    store.copyImage(pin)
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.parchment)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: T("Details"))
            HStack(alignment: .top, spacing: 0) {
                detailStat(label: T("PIXELS"), value: pin.pixelLabel)
                detailDivider
                detailStat(label: T("FILE"), value: pin.byteLabel)
                detailDivider
                detailStat(label: T("FORMAT"), value: (pin.image as NSString).pathExtension.uppercased())
                detailDivider
                detailStat(label: T("CAPTURED"), value: pin.createdAt.loreShort)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
            )
        }
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.inkTertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 8)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
            Button {
                store.openOriginal(pin)
            } label: {
                Label(T("Open original"), systemImage: "arrow.up.right.square")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(PointerPlainButtonStyle())

            Button {
                store.revealPin(pin)
            } label: {
                Label(T("Reveal"), systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(PointerPlainButtonStyle())

            Spacer()

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(T("Delete"), systemImage: "trash")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.red)
            }
            .buttonStyle(PointerPlainButtonStyle())
        }
        .padding(.top, 2)
    }

    private func navButton(icon: String, offset: Int) -> some View {
        Button {
            store.showAdjacentPin(offset: offset)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.34)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.selectedPin?.title ?? pin.title },
            set: { value in
                store.updatePin(id: pin.id) { $0.title = value }
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { store.selectedPin?.note ?? pin.note },
            set: { value in
                store.updatePin(id: pin.id) { $0.note = value }
            }
        )
    }
}

/// Responsive geometry for the inspiration card. The card used to be clamped
/// to a 1140 × 790 window, which read as a small fixed sheet on a 5K display.
/// It now follows the window (88% of its height, up to 1000 pt) and then sizes
/// its width from the image: the picture keeps roughly the same share of its
/// pane as before, the metadata column stays at a comfortable reading width,
/// and landscape pins claim the extra width that portrait pins do not need.
private struct DetailCardMetrics {
    static let minCardWidth: CGFloat = 800
    static let maxCardWidth: CGFloat = 1880
    static let minCardHeight: CGFloat = 540
    static let maxCardHeight: CGFloat = 1000
    static let widthFraction: CGFloat = 0.86
    static let heightFraction: CGFloat = 0.88
    static let minMetaWidth: CGFloat = 392
    static let maxMetaWidth: CGFloat = 560
    /// The hero image occupies about this share of the image pane. Keeping it
    /// constant preserves the original card's visual balance at every size.
    static let imageShare: CGFloat = 0.52

    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let metaWidth: CGFloat

    init(available: CGSize, aspectRatio: CGFloat) {
        let availableWidth = max(available.width, 1)
        let availableHeight = max(available.height, 1)
        let height = min(
            max(availableHeight * Self.heightFraction, Self.minCardHeight),
            Self.maxCardHeight
        )
        let maxWidth = min(
            max(availableWidth * Self.widthFraction, Self.minCardWidth),
            Self.maxCardWidth
        )
        let imagePadding = Self.imagePadding(for: height)
        let imageWidth = max((height - imagePadding * 2) * max(aspectRatio, 0.05), 1)
        let estimatedMeta = min(
            max(maxWidth * 0.425, Self.minMetaWidth),
            Self.maxMetaWidth
        )
        let idealWidth = estimatedMeta + imageWidth / Self.imageShare

        cardHeight = height
        cardWidth = min(max(idealWidth, Self.minCardWidth), maxWidth)
        metaWidth = min(
            max(cardWidth * 0.425, Self.minMetaWidth),
            Self.maxMetaWidth
        )
    }

    var imageWidth: CGFloat { max(cardWidth - metaWidth, 1) }

    /// Breathing room inside the image pane, tied to the card height so the
    /// mat does not look pinched once the card grows.
    var imagePadding: CGFloat { Self.imagePadding(for: cardHeight) }

    private static func imagePadding(for height: CGFloat) -> CGFloat {
        min(max(height * 0.034, 24), 36)
    }

    var imageCornerRadius: CGFloat { min(max(cardHeight * 0.0165, 12), 18) }

    var metaPadding: CGFloat { min(max(cardWidth * 0.022, 24), 40) }

    var sectionSpacing: CGFloat { min(max(cardHeight * 0.026, 18), 26) }
}

struct SmallPillButton: View {
    var title: String
    var icon: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(hovering ? Theme.parchmentDeep : Theme.paper))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .onHover { hovering = $0 }
    }
}
/// One-tap reuse of a tag already present elsewhere in the library. Kept
/// separate from `TagChip` so it can show the add affordance and hover state.
private struct TagSuggestionChip: View {
    let tag: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 7.5, weight: .bold))
                Text("#\(tag)")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(hovering ? Theme.parchmentDeep : Theme.paper))
            .overlay(Capsule().strokeBorder(hovering ? Theme.ink.opacity(0.14) : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(TF("Add #%@", tag))
    }
}
