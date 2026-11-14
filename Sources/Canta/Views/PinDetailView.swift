import SwiftUI
import AppKit

struct PinDetailOverlay: View {
    let pin: Pin

    @EnvironmentObject private var store: LibraryStore
    @State private var showDeleteAlert = false
    @State private var tagEntry = ""
    @State private var showNewBoardField = false
    @State private var newBoardName = ""
    @State private var showBoardMenu = false
    @State private var isImageMode = UserDefaults.standard.bool(forKey: "canta.debugLargeImage")
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            let width = min(max(geo.size.width - 150, 800), 1140)
            let height = min(max(geo.size.height - 92, 540), 790)

            ZStack {
                Color.black.opacity(isImageMode ? 0.86 : 0.42)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if isImageMode {
                            withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
                        } else {
                            store.dismissDetail()
                        }
                    }

                if isImageMode {
                    imageOnlyLayer
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    regularCard(width: width, height: height)
                        .transition(.opacity)
                }

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

                if isImageMode {
                    imageModeChrome
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.975)))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .onExitCommand {
            if isImageMode {
                withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
            } else {
                store.dismissDetail()
            }
        }
        .alert(T("Delete this pin?"), isPresented: $showDeleteAlert) {
            Button(T("Delete"), role: .destructive) { store.deletePin(pin) }
            Button(T("Cancel"), role: .cancel) { }
        } message: {
            Text(T("The original image and its metadata will be removed from Canta."))
        }
    }

    private func regularCard(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            imagePane
                .frame(width: width * 0.575)
            metaPane
                .frame(width: width * 0.425)
        }
        .frame(width: width, height: height)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 48, x: 0, y: 26)
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
        .compositingGroup()
        .contentShape(RoundedRectangle(cornerRadius: Theme.modalRadius, style: .continuous))
    }

    private var imageOnlyLayer: some View {
        GeometryReader { proxy in
            let fitted = fittedImageSize(in: CGSize(width: proxy.size.width - 130, height: proxy.size.height - 130))
            LibraryImage(path: store.originalURL(for: pin).path, contentMode: .fit)
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 50, x: 0, y: 22)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .onTapGesture(count: 2) {
                    withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
                }
        }
        .ignoresSafeArea()
    }

    private var imageModeChrome: some View {
        ZStack {
            VStack {
                HStack {
                    if let index = store.filteredPins.firstIndex(where: { $0.id == pin.id }) {
                        Text("\(index + 1) / \(store.filteredPins.count)")
                            .font(Theme.mono(10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Capsule().fill(Color.black.opacity(0.32)))
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        overlayCircleButton(icon: "arrow.down.right.and.arrow.up.left", help: T("Exit large image")) {
                            withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
                        }
                        overlayCircleButton(icon: "xmark", help: T("Close")) {
                            store.dismissDetail()
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 40)

                Spacer()

                Text(T("Use ← → to browse"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .padding(.horizontal, 11)
                    .frame(height: 25)
                    .background(Capsule().fill(Color.black.opacity(0.28)))
                    .padding(.bottom, 28)
            }
        }
    }

    private func overlayCircleButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.38)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
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
                    withAnimation(.snappy(duration: 0.24)) { isImageMode = false }
                } else {
                    store.dismissDetail()
                }
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - Image side

    private var imagePane: some View {
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

            GeometryReader { proxy in
                let fitted = fittedImageSize(in: CGSize(width: proxy.size.width - 54, height: proxy.size.height - 54))
                LibraryImage(path: store.originalURL(for: pin).path, contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 12)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy(duration: 0.28)) { isImageMode = true }
                    }
            }
            .padding(27)

            VStack {
                HStack {
                    detailChip(icon: pin.kind.icon, text: pin.kind.label)
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

    private func fittedImageSize(in available: CGSize) -> CGSize {
        guard available.width > 1, available.height > 1 else { return available }
        let ratio = max(pin.aspectRatio, 0.3)
        var width = available.width
        var height = width / ratio
        if height > available.height {
            height = available.height
            width = height * ratio
        }
        return CGSize(width: width, height: height)
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

    private var metaPane: some View {
        VStack(spacing: 0) {
            actionRow
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Hairline()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 21) {
                    titleSection
                    noteSection
                    tagsSection
                    paletteSection
                    agentSection
                    metadataSection
                    footerActions
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 26)
            }
        }
        .background(Theme.paper)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            boardMenu

            Spacer()

            CircleActionButton(icon: "arrow.up.left.and.arrow.down.right", label: T("Large image"), size: 35) {
                withAnimation(.snappy(duration: 0.28)) { isImageMode = true }
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
            .background(Capsule().fill(Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
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
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(board.caseInsensitiveCompare(pin.board) == .orderedSame ? Theme.parchment : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
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
                }
                .buttonStyle(.plain)
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
                .background(Circle().fill(Theme.paper))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help(T("More actions"))
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(T("Untitled pin"), text: titleBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.9)
                .foregroundStyle(Theme.ink)
                .lineLimit(1...3)

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
                        .buttonStyle(.plain)
                    } else {
                        Text(sourceLabel)
                    }
                    Text("·")
                }
                Text(TF("Captured %@", pin.createdAt.cantaShort))
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)

            if showNewBoardField {
                HStack(spacing: 6) {
                    TextField(T("New board name"), text: $newBoardName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 10)
                        .frame(height: 29)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.parchment))
                    Button(T("Move")) {
                        let name = newBoardName.trimmed
                        guard !name.isEmpty else { return }
                        store.movePin(pin.id, toBoard: name)
                        newBoardName = ""
                        showNewBoardField = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    Button {
                        showNewBoardField = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: T("Design note"))
            TextField(T("What makes this worth copying? Layout, type, color…"), text: noteBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(3)
                .lineLimit(2...6)
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.parchment)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline.opacity(0.8), lineWidth: 1)
                )
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: T("Tags"), trailing: "\(pin.tags.count)")
            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(pin.tags, id: \.self) { tag in
                    TagChip(tag: tag, onRemove: {
                        store.removeTag(tag, from: pin.id)
                    })
                }
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.inkTertiary)
                    TextField(T("tag"), text: $tagEntry)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 55)
                        .onSubmit {
                            store.addTag(tagEntry, to: pin.id)
                            tagEntry = ""
                        }
                }
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(Capsule().fill(Theme.paper))
                .overlay(Capsule().strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: T("Palette"))
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
                    .buttonStyle(.plain)
                    .help(TF("Copy %@", hex))
                }
            }
        }
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
            .buttonStyle(.plain)

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
                detailStat(label: T("CAPTURED"), value: pin.createdAt.cantaShort)
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
            .buttonStyle(.plain)

            Button {
                store.revealPin(pin)
            } label: {
                Label(T("Reveal"), systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label(T("Delete"), systemImage: "trash")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.red)
            }
            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}