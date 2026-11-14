import SwiftUI
import AppKit
import CantaAgentKit

@MainActor
final class LibraryStore: ObservableObject {
    let root: URL

    @Published private(set) var pins: [Pin] = []
    @Published var section: LibrarySection = .all
    @Published var selectedBoard: String?
    @Published var searchText: String = ""
    @Published var filter: GalleryFilter = .all
    @Published var sort: PinSort = .recent
    @Published var selectedPinID: UUID?
    @Published var isSelectingPins = false
    @Published var selectedPinIDs: Set<UUID> = []
    @Published var capturePresented = false
    @Published var isImporting = false
    @Published var toast: ToastMessage?
    @Published var startupError: String?

    @Published private(set) var agentStatus: AgentServerStatus = .stopped
    @Published private(set) var agentPort: UInt16
    @Published private(set) var agentAPIEnabled: Bool
    @Published var defaultBoard: String {
        didSet { UserDefaults.standard.set(defaultBoard, forKey: Keys.defaultBoard) }
    }

    private enum Keys {
        static let agentPort = "canta.agent.port"
        static let agentEnabled = "canta.agent.enabled"
        static let defaultBoard = "canta.defaultBoard"
    }

    private var agentServer: CantaAgentServer?
    private var agentGeneration = 0
    private var toastTask: Task<Void, Never>?

    static let suggestedBoards = ["Web dashboards", "Mobile flows", "Landing pages", "Editorial", "Unsorted"]

    init(root: URL = CantaPaths.dataRoot) {
        if let debugHome = UserDefaults.standard.string(forKey: "canta.debugHome"), !debugHome.isEmpty {
            self.root = URL(fileURLWithPath: debugHome, isDirectory: true)
        } else {
            self.root = root
        }
        let defaults = UserDefaults.standard
        let storedPort = defaults.integer(forKey: Keys.agentPort)
        self.agentPort = UInt16(clamping: storedPort > 1024 ? storedPort : 4242)
        if defaults.object(forKey: Keys.agentEnabled) == nil {
            self.agentAPIEnabled = true
        } else {
            self.agentAPIEnabled = defaults.bool(forKey: Keys.agentEnabled)
        }
        self.defaultBoard = defaults.string(forKey: Keys.defaultBoard) ?? "Unsorted"

        do {
            try CantaPaths.ensureDirectories(root: self.root)
            _ = try SeedLoader.installIfNeeded(root: self.root)
            let data = try Data(contentsOf: CantaPaths.libraryFile(root: self.root))
            let library = try CantaJSON.decoder.decode(CantaLibrary.self, from: data)
            self.pins = library.pins
        } catch {
            self.pins = []
            self.startupError = TF("Canta couldn't read your library. New pins will start a fresh one. (%@)", error.localizedDescription)
        }
    }

    // MARK: - Derived collections

    var selectedPin: Pin? {
        guard let selectedPinID else { return nil }
        return pins.first { $0.id == selectedPinID }
    }

    var selectedPins: [Pin] {
        filteredPins.filter { selectedPinIDs.contains($0.id) }
    }

    var allVisibleSelected: Bool {
        !filteredPins.isEmpty && filteredPins.allSatisfy { selectedPinIDs.contains($0.id) }
    }

    var selectedPinsAreFavorites: Bool {
        !selectedPins.isEmpty && selectedPins.allSatisfy(\.isFavorite)
    }

    var filteredPins: [Pin] {
        var result = pins

        switch section {
        case .favorites:
            result = result.filter(\.isFavorite)
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            result = result.filter { $0.createdAt >= cutoff }
        case .all, .agent:
            break
        }

        if let selectedBoard {
            result = result.filter { $0.board.caseInsensitiveCompare(selectedBoard) == .orderedSame }
        }

        switch filter {
        case .all: break
        case .screenshots: result = result.filter { $0.kind == .screenshot }
        case .favorites: result = result.filter(\.isFavorite)
        }

        let needle = searchText.trimmed.lowercased()
        if !needle.isEmpty {
            let tokens = needle.split(separator: " ").map(String.init)
            result = result.filter { pin in
                let haystack = [
                    pin.title,
                    pin.note,
                    pin.board,
                    localizedBoard(pin.board),
                    pin.sourceLabel ?? "",
                    pin.tags.joined(separator: " "),
                    pin.kind.label
                ].joined(separator: " ").lowercased()
                return tokens.allSatisfy { haystack.contains($0) }
            }
        }

        switch sort {
        case .recent:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return result
    }

    var boardSummaries: [BoardSummary] {
        var counts: [String: Int] = [:]
        for pin in pins {
            let board = pin.board.trimmed.isEmpty ? "Unsorted" : pin.board
            counts[board, default: 0] += 1
        }
        let orderedNames = Self.suggestedBoards.filter { counts[$0] != nil }
        let extraNames = counts.keys.filter { !Self.suggestedBoards.contains($0) }.sorted()
        return (orderedNames + extraNames).map { BoardSummary(name: $0, count: counts[$0] ?? 0) }
    }

    var allBoardNames: [String] {
        var names = Self.suggestedBoards
        for pin in pins where !names.contains(pin.board) && !pin.board.trimmed.isEmpty {
            names.append(pin.board)
        }
        return names
    }

    var favoriteCount: Int { pins.filter(\.isFavorite).count }
    var screenshotCount: Int { pins.filter { $0.kind == .screenshot }.count }
    var recentCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return pins.filter { $0.createdAt >= cutoff }.count
    }

    var allTags: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pin in pins {
            for tag in pin.tags where !tag.trimmed.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
    }

    var pageTitle: String {
        switch section {
        case .all:
            return selectedBoard.map(localizedBoard) ?? T("All pins")
        case .favorites:
            return T("Favorites")
        case .recent:
            return T("Recent captures")
        case .agent:
            return T("Agent access")
        }
    }

    var pageSubtitle: String {
        switch section {
        case .all:
            if let selectedBoard {
                let count = boardSummaries.first(where: { $0.name == selectedBoard })?.count ?? 0
                return TF("%ld pins curated in this board", count)
            }
            return TF("%ld pins · a small, searchable visual memory for building interfaces", pins.count)
        case .favorites:
            return TF("%ld hand-picked references", favoriteCount)
        case .recent:
            return TF("%ld pins added in the last 30 days", recentCount)
        case .agent:
            return T("Give your coding agent eyes for good design")
        }
    }

    var currentListIdentity: String {
        "\(section.rawValue)|\(selectedBoard ?? "")|\(filter.rawValue)|\(sort.rawValue)|\(searchText)"
    }

    var dataFolderPath: String { root.path }
    var libraryFileURL: URL { CantaPaths.libraryFile(root: root) }

    func originalURL(for pin: Pin) -> URL { root.appendingPathComponent(pin.image) }
    func thumbnailURL(for pin: Pin) -> URL {
        if let thumbnail = pin.thumbnail {
            let url = root.appendingPathComponent(thumbnail)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return originalURL(for: pin)
    }

    // MARK: - Navigation

    func select(section newSection: LibrarySection) {
        endSelection()
        withAnimation(.snappy(duration: 0.28)) {
            section = newSection
            if newSection != .all || selectedBoard != nil {
                selectedBoard = nil
            }
            if newSection == .favorites { filter = .all }
        }
    }

    func select(board: String) {
        endSelection()
        withAnimation(.snappy(duration: 0.28)) {
            section = .all
            selectedBoard = board
            filter = .all
        }
    }

    func openDetail(_ pin: Pin) {
        if isSelectingPins { endSelection() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedPinID = pin.id
        }
    }

    func dismissDetail() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            selectedPinID = nil
        }
    }

    func showAdjacentPin(offset: Int) {
        let list = filteredPins
        guard !list.isEmpty else { return }
        let currentIndex = list.firstIndex(where: { $0.id == selectedPinID }) ?? -1
        let nextIndex = min(max(currentIndex + offset, 0), list.count - 1)
        guard nextIndex != currentIndex else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            selectedPinID = list[nextIndex].id
        }
    }

    // MARK: - Batch selection

    func beginSelection() {
        withAnimation(.snappy(duration: 0.24)) {
            isSelectingPins = true
            selectedPinIDs.removeAll()
            selectedPinID = nil
        }
    }

    func endSelection() {
        guard isSelectingPins || !selectedPinIDs.isEmpty else { return }
        withAnimation(.snappy(duration: 0.24)) {
            isSelectingPins = false
            selectedPinIDs.removeAll()
        }
    }

    func toggleSelection(_ pinID: UUID) {
        withAnimation(.snappy(duration: 0.18)) {
            if selectedPinIDs.contains(pinID) {
                selectedPinIDs.remove(pinID)
            } else {
                selectedPinIDs.insert(pinID)
            }
        }
    }

    func selectAllVisible() {
        withAnimation(.snappy(duration: 0.2)) {
            selectedPinIDs = Set(filteredPins.map(\.id))
        }
    }

    func clearSelection() {
        withAnimation(.snappy(duration: 0.18)) {
            selectedPinIDs.removeAll()
        }
    }

    func setFavorite(_ favorite: Bool, for pinIDs: Set<UUID>) {
        var changed = 0
        for index in pins.indices where pinIDs.contains(pins[index].id) {
            if pins[index].isFavorite != favorite {
                pins[index].isFavorite = favorite
                pins[index].updatedAt = Date()
                changed += 1
            }
        }
        guard changed > 0 else {
            showToast(favorite ? T("Saved to favorites") : T("Removed from favorites"), icon: favorite ? "heart.fill" : "heart")
            return
        }
        persist()
        let message = favorite
            ? TF("%ld pins added to favorites", changed)
            : TF("%ld pins removed from favorites", changed)
        showToast(message, icon: favorite ? "heart.fill" : "heart")
    }

    func toggleSelectedFavorites() {
        guard !selectedPins.isEmpty else { return }
        setFavorite(!selectedPinsAreFavorites, for: selectedPinIDs)
    }

    func moveSelectedPins(toBoard board: String) {
        let ids = selectedPinIDs
        guard !ids.isEmpty else { return }
        let clean = board.trimmed.nilIfEmpty ?? "Unsorted"
        var changed = 0
        for index in pins.indices where ids.contains(pins[index].id) {
            pins[index].board = clean
            pins[index].updatedAt = Date()
            changed += 1
        }
        persist()
        showToast(TF("%ld pins moved to %@", changed, localizedBoard(clean)), icon: "folder")
        endSelection()
    }

    func deleteSelectedPins() {
        let ids = selectedPinIDs
        let targets = pins.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        let fm = FileManager.default
        for pin in targets {
            try? fm.removeItem(at: root.appendingPathComponent(pin.image))
            if let thumbnail = pin.thumbnail {
                try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
            }
        }
        pins.removeAll { ids.contains($0.id) }
        if let selectedPinID, ids.contains(selectedPinID) { self.selectedPinID = nil }
        persist()
        showToast(TF("%ld pins deleted", targets.count), icon: "trash")
        endSelection()
    }

    func copySelectedAgentContext() {
        let chosen = selectedPins
        guard !chosen.isEmpty else { return }
        copyText(
            agentContext(includePins: chosen),
            message: TF("%ld pins copied as agent context", chosen.count),
            icon: "sparkles"
        )
    }

    // MARK: - Mutations

    func updatePin(id: UUID, _ mutate: (inout Pin) -> Void) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        var pin = pins[index]
        mutate(&pin)
        pin.updatedAt = Date()
        pins[index] = pin
        persist()
    }

    func toggleFavorite(_ pin: Pin) {
        updatePin(id: pin.id) { $0.isFavorite.toggle() }
        let favorite = pins.first(where: { $0.id == pin.id })?.isFavorite ?? false
        showToast(favorite ? T("Saved to favorites") : T("Removed from favorites"), icon: favorite ? "heart.fill" : "heart")
    }

    func addTag(_ rawTag: String, to pinID: UUID) {
        var tag = rawTag.trimmed.lowercased()
        if tag.hasPrefix("#") { tag.removeFirst() }
        guard !tag.isEmpty else { return }
        updatePin(id: pinID) { pin in
            if !pin.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                pin.tags.append(tag)
            }
        }
    }

    func removeTag(_ tag: String, from pinID: UUID) {
        updatePin(id: pinID) { $0.tags.removeAll { $0 == tag } }
    }

    func movePin(_ pinID: UUID, toBoard board: String) {
        let clean = board.trimmed.nilIfEmpty ?? "Unsorted"
        updatePin(id: pinID) { $0.board = clean }
    }

    func deletePin(_ pin: Pin) {
        let fm = FileManager.default
        try? fm.removeItem(at: root.appendingPathComponent(pin.image))
        if let thumbnail = pin.thumbnail {
            try? fm.removeItem(at: root.appendingPathComponent(thumbnail))
        }
        pins.removeAll { $0.id == pin.id }
        if selectedPinID == pin.id { selectedPinID = nil }
        persist()
        showToast(T("Pin deleted"), icon: "trash")
    }

    // MARK: - Import

    func addFiles(_ urls: [URL], sourceLabel: String = "Imported", preferredTitle: String? = nil, board explicitBoard: String? = nil) async {
        guard !urls.isEmpty else { return }
        guard !isImporting else {
            showToast(T("Canta is still importing"), icon: "hourglass")
            return
        }

        isImporting = true
        defer { isImporting = false }

        let targetBoard = (explicitBoard ?? selectedBoard ?? defaultBoard).trimmed.nilIfEmpty ?? "Unsorted"
        var created: [Pin] = []
        var failure: String?

        for (index, url) in urls.enumerated() {
            let id = UUID()
            do {
                let processed = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.process(fileURL: url, root: self.root, id: id)
                }.value

                let baseTitle = urls.count == 1 ? (preferredTitle ?? Self.defaultTitle(for: url)) : Self.defaultTitle(for: url)
                let pin = Pin(
                    id: id,
                    title: index == 0 && preferredTitle != nil ? preferredTitle! : baseTitle,
                    note: "",
                    image: processed.image,
                    thumbnail: processed.thumbnail,
                    width: processed.width,
                    height: processed.height,
                    fileSize: processed.fileSize,
                    createdAt: Date(),
                    updatedAt: Date(),
                    tags: [],
                    board: targetBoard,
                    sourceURL: nil,
                    sourceLabel: sourceLabel,
                    colors: processed.colors,
                    isFavorite: false,
                    kind: processed.kind
                )
                created.append(pin)
            } catch {
                failure = error.localizedDescription
            }
        }

        guard !created.isEmpty else {
            showToast(failure ?? T("Couldn't add that image"), icon: "exclamationmark.triangle")
            return
        }

        pins.append(contentsOf: created)
        persist()
        revealFreshlyAdded(board: targetBoard)

        let localizedTargetBoard = localizedBoard(targetBoard)
        if let failure {
            let countLabel = created.count == 1 ? TF("%ld pin", created.count) : TF("%ld pins", created.count)
            showToast(TF("%@ added · %@", countLabel, failure), icon: "exclamationmark.circle")
        } else if created.count == 1 {
            showToast(TF("%ld pin added to %@", created.count, localizedTargetBoard), icon: "pin.fill")
        } else {
            showToast(TF("%ld pins added to %@", created.count, localizedTargetBoard), icon: "pin.fill")
        }
    }

    func addImageData(_ data: Data, preferredExtension: String? = nil, sourceLabel: String = "Clipboard", title: String? = nil, board: String? = nil) async {
        guard !isImporting else {
            showToast(T("Canta is still importing"), icon: "hourglass")
            return
        }
        isImporting = true
        defer { isImporting = false }

        let targetBoard = (board ?? selectedBoard ?? defaultBoard).trimmed.nilIfEmpty ?? "Unsorted"
        let id = UUID()
        do {
            let processed = try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.process(data: data, preferredExtension: preferredExtension, root: self.root, id: id)
            }.value
            let pin = Pin(
                id: id,
                title: title ?? TF("Pasted screenshot · %@", Self.captureStamp()),
                image: processed.image,
                thumbnail: processed.thumbnail,
                width: processed.width,
                height: processed.height,
                fileSize: processed.fileSize,
                tags: [],
                board: targetBoard,
                sourceLabel: sourceLabel,
                colors: processed.colors,
                kind: .screenshot
            )
            pins.append(pin)
            persist()
            revealFreshlyAdded(board: targetBoard)
            showToast(TF("Screenshot added to %@", localizedBoard(targetBoard)), icon: "pin.fill")
        } catch {
            showToast(error.localizedDescription, icon: "exclamationmark.triangle")
        }
    }

    @discardableResult
    func pasteFromClipboard(board: String? = nil) async -> Bool {
        let pasteboard = NSPasteboard.general

        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = objects.compactMap { ($0 as? NSURL) as URL? }
            let imageURLs = urls.filter { Self.isLikelyImage($0) }
            if !imageURLs.isEmpty {
                await addFiles(imageURLs, sourceLabel: "Clipboard", board: board)
                return true
            }
        }

        if let png = pasteboard.data(forType: .png) {
            await addImageData(png, preferredExtension: "png", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()), board: board)
            return true
        }
        if let tiff = pasteboard.data(forType: .tiff), let png = ImageProcessor.pngData(fromTIFF: tiff) {
            await addImageData(png, preferredExtension: "png", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()))
            return true
        }
        if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            await addImageData(jpeg, preferredExtension: "jpg", sourceLabel: "Clipboard", title: TF("Pasted screenshot · %@", Self.captureStamp()), board: board)
            return true
        }

        showToast("No image on the clipboard", icon: "doc.on.clipboard")
        return false
    }

    func captureScreenshot(board: String? = nil) async {
        guard !isImporting else {
            showToast(T("Canta is still importing"), icon: "hourglass")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Canta-Screen-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempURL.path]

        let succeeded: Bool = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }

        guard succeeded, FileManager.default.fileExists(atPath: tempURL.path) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        await addFiles(
            [tempURL],
            sourceLabel: "Screen capture",
            preferredTitle: TF("Screen capture · %@", Self.captureStamp()),
            board: board
        )
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func revealFreshlyAdded(board: String) {
        withAnimation(.snappy(duration: 0.3)) {
            section = .all
            selectedBoard = board
            filter = .all
            searchText = ""
        }
    }

    // MARK: - Sharing / clipboard

    var agentBaseURL: String { "http://127.0.0.1:\(agentPort)" }
    var agentDocsURL: URL? { URL(string: agentBaseURL + "/docs") }
    var agentContextURL: URL? { URL(string: agentBaseURL + "/api/v1/context") }
    var agentManifestURL: URL? { URL(string: agentBaseURL + "/llms.txt") }

    func apiImageURL(for pin: Pin) -> String {
        agentBaseURL + "/api/v1/pins/\(pin.id.uuidString)/image"
    }

    func agentSnippet(for pin: Pin) -> String {
        var lines: [String] = []
        lines.append("### \(pin.title)")
        lines.append("")
        lines.append("![Canta reference: \(pin.title)](\(apiImageURL(for: pin)))")
        lines.append("")
        lines.append("- Board: \(pin.board)")
        if !pin.tags.isEmpty { lines.append("- Tags: " + pin.tags.map { "#\($0)" }.joined(separator: " ")) }
        lines.append("- Pixels: \(pin.pixelLabel)")
        if !pin.colors.isEmpty { lines.append("- Palette: " + pin.colors.joined(separator: ", ")) }
        if !pin.note.isEmpty { lines.append("- Design note: \(pin.note)") }
        lines.append("- Captured: \(pin.createdAt.cantaTime)")
        return lines.joined(separator: "\n")
    }

    func agentContext(includePins subset: [Pin]? = nil) -> String {
        let chosen = subset ?? filteredPins
        var lines: [String] = []
        lines.append("# Canta design context")
        lines.append("")
        lines.append("A local visual reference library for building interfaces. Treat these as art direction, not code to copy verbatim.")
        lines.append("")
        lines.append("- API docs: \(agentBaseURL)/docs")
        lines.append("- Full JSON library: \(agentBaseURL)/api/v1/library")
        lines.append("- Pins in this context: \(chosen.count)")
        lines.append("")
        for pin in chosen {
            lines.append(agentSnippet(for: pin))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func copyAgentSnippet(for pin: Pin) {
        copyText(agentSnippet(for: pin), message: T("Agent snippet copied"), icon: "sparkles")
    }

    func copyAgentContext() {
        copyText(agentContext(), message: T("Agent context copied"), icon: "sparkles")
    }

    func copyPinJSON(_ pin: Pin) {
        let payload: [String: Any] = [
            "id": pin.id.uuidString,
            "title": pin.title,
            "note": pin.note,
            "board": pin.board,
            "tags": pin.tags,
            "kind": pin.kind.rawValue,
            "width": pin.width,
            "height": pin.height,
            "colors": pin.colors,
            "favorite": pin.isFavorite,
            "image": pin.image,
            "imageURL": apiImageURL(for: pin),
            "sourceLabel": pin.sourceLabel ?? NSNull(),
            "sourceURL": pin.sourceURL ?? NSNull()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            copyText(string, message: T("Pin JSON copied"), icon: "curlybraces")
        }
    }

    func copyText(_ text: String, message: String? = nil, icon: String = "doc.on.doc") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast(message ?? T("Copied"), icon: icon)
    }

    func copyImage(_ pin: Pin) {
        guard let image = NSImage(contentsOf: thumbnailURL(for: pin)) else {
            showToast(T("Couldn't load that image"), icon: "exclamationmark.triangle")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        showToast(T("Image copied"), icon: "photo.on.rectangle")
    }

    func openOriginal(_ pin: Pin) {
        NSWorkspace.shared.open(originalURL(for: pin))
    }

    func revealPin(_ pin: Pin) {
        NSWorkspace.shared.activateFileViewerSelecting([originalURL(for: pin)])
    }

    func openSource(_ pin: Pin) {
        guard let source = pin.sourceURL, let url = URL(string: source) else { return }
        NSWorkspace.shared.open(url)
    }

    func openAgentDocs() {
        if let agentDocsURL { NSWorkspace.shared.open(agentDocsURL) }
    }

    func openAgentContext() {
        if let agentContextURL { NSWorkspace.shared.open(agentContextURL) }
    }

    func openAgentManifest() {
        if let agentManifestURL { NSWorkspace.shared.open(agentManifestURL) }
    }

    func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryFileURL])
    }

    // MARK: - Agent server

    func startAgentServerIfNeeded() {
        guard agentAPIEnabled, agentServer == nil else { return }

        agentGeneration += 1
        let generation = agentGeneration
        let server = CantaAgentServer(
            config: AgentServerConfig(port: agentPort, libraryRoot: root)
        )
        server.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.agentGeneration == generation else { return }
                self.agentStatus = status
            }
        }
        agentServer = server
        agentStatus = .starting
        server.start()
    }

    func stopAgentServer() {
        agentGeneration += 1
        agentServer?.onStatusChange = nil
        agentServer?.stop()
        agentServer = nil
        agentStatus = .stopped
    }

    func restartAgentServer() {
        stopAgentServer()
        if agentAPIEnabled { startAgentServerIfNeeded() }
    }

    func setAgentEnabled(_ enabled: Bool) {
        agentAPIEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.agentEnabled)
        if enabled {
            startAgentServerIfNeeded()
        } else {
            stopAgentServer()
        }
    }

    func setAgentPort(_ port: UInt16) {
        guard port >= 1024 else { return }
        agentPort = port
        UserDefaults.standard.set(Int(port), forKey: Keys.agentPort)
        if agentServer != nil || agentStatus.isRunning {
            restartAgentServer()
        }
    }

    var agentStatusLabel: String {
        switch agentStatus {
        case .stopped: return T(agentAPIEnabled ? "API stopped" : "API off")
        case .starting: return T("API starting…")
        case .running: return T("Agent API live")
        case .failed: return T("API unavailable")
        }
    }

    var agentStatusDetail: String? {
        switch agentStatus {
        case .failed(let message): return message
        default: return nil
        }
    }

    // MARK: - Utilities

    func showToast(_ text: String, icon: String = "checkmark") {
        let message = ToastMessage(text: text, icon: icon)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            toast = message
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.toast?.id == message.id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }

    private func persist() {
        do {
            try CantaPaths.ensureDirectories(root: root)
            let library = CantaLibrary(version: 1, pins: pins)
            let data = try CantaJSON.encoder.encode(library)
            try data.write(to: CantaPaths.libraryFile(root: root), options: .atomic)
        } catch {
            showToast(T("Couldn't save the library"), icon: "exclamationmark.triangle")
        }
    }

    private static func defaultTitle(for url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let cleaned = raw
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmed
        let lower = cleaned.lowercased()
        if lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("screencapture") || lower.contains("截屏") {
            return TF("Screenshot · %@", captureStamp())
        }
        if cleaned.count < 3 { return T("Untitled capture") }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private static func captureStamp() -> String {
        Date().cantaTime
    }

    private static func isLikelyImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"].contains(ext)
    }
}