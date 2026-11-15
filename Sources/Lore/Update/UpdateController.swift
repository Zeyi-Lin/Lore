import AppKit
import Foundation
import LoreAgentKit
import Observation

/// Owns the "is this the newest Lore?" question and the one-click install path.
///
/// Checking is deliberately tiny and stateless: GitHub's `/releases/latest` is
/// the source of truth, the tag is compared against the bundle version, and the
/// release's DMG is handed to `UpdateInstaller` only after the user asks for it.
/// Automatic checks run at most once a day and stay silent on failure; manual
/// checks surface the reason.
@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(UpdateRelease)
        case downloading(UpdateRelease, progress: Double)
        case installing(UpdateRelease)
        case failed(title: String, message: String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastCheck: Date?
    /// Set when a newer release is found; Settings consumes it to bring the
    /// About card into view instead of leaving the update hidden below the fold.
    var revealAboutOnAppear = false

    private let defaults = UserDefaults.standard
    private var checkInFlight = false

    private static let lastCheckKey = "lore.update.lastCheck"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    private init() {
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    // MARK: - State read by Settings

    var currentVersion: String { LoreVersion.installed }
    var currentSemanticVersion: SemanticVersion? { SemanticVersion(currentVersion) }
    var availableRelease: UpdateRelease? {
        if case .available(let release) = phase { return release }
        return nil
    }
    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var statusTitle: String {
        switch phase {
        case .idle:
            return TF("Lore %@ is installed", currentVersion)
        case .checking:
            return T("Checking for updates…")
        case .upToDate:
            return T("You're up to date")
        case .available(let release):
            return TF("Lore %@ is available", release.version.description)
        case .downloading:
            return T("Downloading update…")
        case .installing:
            return T("Installing update…")
        case .failed(let title, _):
            return title
        }
    }

    var statusDetail: String? {
        switch phase {
        case .idle:
            return T("Check GitHub Releases for the latest version.")
        case .checking:
            return nil
        case .upToDate(let date):
            return TF("Last checked %@", timeText(date))
        case .available(let release):
            return TF("Latest release: %@", release.title)
        case .downloading(_, let progress):
            return TF("%d%% downloaded", Int(progress * 100))
        case .installing:
            return T("Lore will quit and relaunch when the update is ready.")
        case .failed(_, let message):
            return message
        }
    }

    var statusIcon: String {
        switch phase {
        case .upToDate: return "checkmark.circle.fill"
        case .available: return "arrow.down.circle.fill"
        case .downloading, .installing: return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .idle: return "arrow.triangle.2.circlepath"
        }
    }

    // MARK: - Checking

    /// Called shortly after launch. Throttled to once a day and skipped while an
    /// update is already waiting, so reopening the window does not spam GitHub.
    func checkIfDue() async {
        guard !updatesDisabled else { return }
        guard case .idle = phase else { return }
        guard currentSemanticVersion != nil else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.autoCheckInterval { return }
        await checkForUpdates(userInitiated: false)

        // Smoke-test hook: lets a scripted run exercise download → mount →
        // swap → relaunch without clicking. Not reachable from the UI or feed.
        if defaults.bool(forKey: "lore.debugAutoInstallUpdate"),
           case .available = phase {
            await installAvailableUpdate()
        }
    }

    func checkForUpdates(userInitiated: Bool = true) async {
        guard !checkInFlight else { return }
        guard let current = currentSemanticVersion else {
            phase = .failed(title: T("Update check failed"),
                            message: T("Lore's version couldn't be read."))
            return
        }
        checkInFlight = true
        phase = .checking
        defer { checkInFlight = false }
        do {
            let release = try await UpdateFeed.fetchLatest(
                from: feedURL,
                userAgent: "Lore/\(currentVersion)"
            )
            let now = Date()
            lastCheck = now
            defaults.set(now, forKey: Self.lastCheckKey)
            if release.isNewer(than: current) {
                phase = .available(release)
                revealAboutOnAppear = true
            } else {
                phase = .upToDate(now)
            }
        } catch {
            // A failed background check stays quiet: the next launch retries.
            if userInitiated {
                phase = .failed(title: T("Update check failed"), message: checkMessage(for: error))
            } else {
                phase = .idle
            }
        }
    }

    /// App-menu entry: reveal the status in Settings, then refresh it.
    func checkFromMenu() {
        presentSettings()
        Task { await checkForUpdates(userInitiated: true) }
    }

    // MARK: - Installing

    func installAvailableUpdate() async {
        guard case .available(let release) = phase else { return }
        guard let asset = release.installerAsset else {
            openReleasePage()
            return
        }
        phase = .downloading(release, progress: 0)

        let downloaded: URL
        do {
            downloaded = try await download(asset, release: release)
        } catch {
            phase = .failed(
                title: T("Download failed"),
                message: T("Couldn't download the update. Check your connection and try again.")
            )
            return
        }

        phase = .installing(release)
        let installer = UpdateInstaller(
            targetApp: Bundle.main.bundleURL,
            allowLocalAssets: feedURL.isFileURL
        )
        do {
            try await Task.detached(priority: .userInitiated) {
                try installer.install(
                    downloadedFile: downloaded,
                    asset: asset,
                    expectedVersion: release.version
                )
            }.value
        } catch {
            handleInstallFailure(error, downloaded: downloaded)
            return
        }

        // The helper waits for this process to exit before touching the bundle.
        try? await Task.sleep(nanoseconds: 350_000_000)
        NSApp.terminate(nil)
    }

    private func handleInstallFailure(_ error: Error, downloaded: URL) {
        var keepDownloaded = false
        defer {
            if !keepDownloaded { try? FileManager.default.removeItem(at: downloaded) }
        }
        guard let installError = error as? UpdateInstallError else {
            phase = .failed(title: T("Update install failed"),
                            message: T("The update couldn't be installed. Try again from the GitHub release page."))
            return
        }
        switch installError {
        case .notAPackagedApp:
            phase = .failed(
                title: T("Update install failed"),
                message: T("This build isn't a packaged app, so it can't install updates. Download the release instead.")
            )
        case .notWritable:
            // Hand the user the mounted installer so they can drag Lore into
            // /Applications themselves; the app cannot escalate its own rights.
            keepDownloaded = true
            NSWorkspace.shared.open(downloaded)
            phase = .failed(
                title: T("Update install failed"),
                message: T("Lore can't replace itself at this location. The installer is open — drag Lore to Applications.")
            )
        case .untrustedDownload:
            phase = .failed(title: T("Update install failed"),
                            message: T("Lore only installs updates downloaded from GitHub."))
        case .identityMismatch, .versionMismatch:
            phase = .failed(title: T("Update install failed"),
                            message: T("The downloaded app doesn't match this release."))
        case .unsupportedAsset:
            phase = .failed(title: T("Update install failed"),
                            message: T("This release doesn't include an installer."))
        case .mountFailed, .appNotFound, .stagingFailed, .helperFailed:
            phase = .failed(title: T("Update install failed"),
                            message: T("The installer couldn't be opened. Try again from the GitHub release page."))
        }
    }

    // MARK: - Networking

    private func download(_ asset: UpdateAsset, release: UpdateRelease) async throws -> URL {
        let name = URL(fileURLWithPath: asset.name).lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lore-\(UUID().uuidString)-\(name)")

        if asset.downloadURL.isFileURL {
            try FileManager.default.copyItem(at: asset.downloadURL, to: destination)
            return destination
        }

        let downloader = UpdateDownloader(destination: destination) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .downloading(let current, _) = self.phase,
                      current.tag == release.tag else { return }
                self.phase = .downloading(current, progress: progress)
            }
        }
        try await downloader.start(asset.downloadURL)
        return destination
    }

    func openReleasePage() {
        if case .available(let release) = phase {
            NSWorkspace.shared.open(release.pageURL)
        } else if let page = URL(string: "https://github.com/\(UpdateFeed.repository)/releases") {
            NSWorkspace.shared.open(page)
        }
    }

    private var feedURL: URL {
        let override = ProcessInfo.processInfo.environment["LORE_UPDATE_FEED"]
            ?? defaults.string(forKey: "lore.debugUpdateFeed")
            ?? ""
        guard !override.isEmpty else { return UpdateFeed.latestReleaseURL }
        if override.hasPrefix("/") { return URL(fileURLWithPath: override) }
        return URL(string: override) ?? UpdateFeed.latestReleaseURL
    }

    private var updatesDisabled: Bool {
        ProcessInfo.processInfo.environment["LORE_UPDATE_DISABLE"] == "1"
            || defaults.bool(forKey: "lore.debugDisableUpdateCheck")
    }

    // MARK: - Copy helpers

    private func checkMessage(for error: Error) -> String {
        guard let feedError = error as? UpdateFeedError else {
            return T("Couldn't check for updates. Try again later.")
        }
        switch feedError {
        case .httpStatus(403), .httpStatus(429):
            return T("GitHub is rate limiting checks. Try again in a few minutes.")
        case .httpStatus(let code):
            return TF("GitHub returned an unexpected status (%ld).", code)
        case .network:
            return T("Couldn't reach GitHub. Check your connection and try again.")
        case .malformedRelease:
            return T("GitHub returned an update Lore couldn't read.")
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - Downloading

/// Bridges `URLSession`'s delegate download (needed for byte progress and for a
/// destination that survives the callback) into one `async` call.
private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func start(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(UpdateFeedError.httpStatus(http.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if FileManager.default.fileExists(atPath: destination.path) {
            finish(.success(()))
        } else {
            finish(.failure(UpdateFeedError.network("The download produced no file.")))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(with: result)
    }
}
