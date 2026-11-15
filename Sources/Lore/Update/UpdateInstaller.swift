import Foundation
import LoreAgentKit

/// Errors the self-updater can hit. Each case carries a short technical detail
/// for the update log; the Settings screen maps them to localized copy.
enum UpdateInstallError: LocalizedError, Equatable {
    case notAPackagedApp
    case unsupportedAsset
    case untrustedDownload(String)
    case mountFailed(String)
    case appNotFound
    case identityMismatch(String)
    case versionMismatch(expected: String, found: String)
    case notWritable(String)
    case stagingFailed(String)
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAPackagedApp:
            return "Lore is not running from a .app bundle."
        case .unsupportedAsset:
            return "The release has no .dmg or .zip installer."
        case .untrustedDownload(let url):
            return "Refusing to install from \(url)."
        case .mountFailed(let detail):
            return "Could not mount the disk image: \(detail)"
        case .appNotFound:
            return "The disk image did not contain a Lore app."
        case .identityMismatch(let found):
            return "The downloaded app has bundle id \(found), not studio.lore.library."
        case .versionMismatch(let expected, let found):
            return "The downloaded app is version \(found), expected \(expected)."
        case .notWritable(let path):
            return "Lore cannot write to \(path)."
        case .stagingFailed(let detail):
            return "Could not stage the update: \(detail)"
        case .helperFailed(let detail):
            return "Could not start the update helper: \(detail)"
        }
    }
}

/// Downloads an installer disk image (the controller owns the download) and
/// swaps the running bundle for the one inside it.
///
/// A running app cannot reliably replace its own bundle: the OS keeps executing
/// the old binary while resources disappear underneath it. So the last step
/// stages the new app next to the old one, writes a small shell helper, and lets
/// the helper do the swap after Lore has quit. The helper reopens Lore when it
/// finishes, and restores the old bundle if the copy fails.
struct UpdateInstaller {
    static let bundleIdentifier = "studio.lore.library"

    /// Where the app currently lives, normally `/Applications/Lore.app`.
    let targetApp: URL
    /// `true` only when the feed itself came from a local file (the update smoke
    /// test); production feeds must use GitHub over HTTPS.
    let allowLocalAssets: Bool

    func install(
        downloadedFile: URL,
        asset: UpdateAsset,
        expectedVersion: SemanticVersion
    ) throws {
        guard targetApp.pathExtension.lowercased() == "app" else {
            throw UpdateInstallError.notAPackagedApp
        }
        try validate(asset.downloadURL)
        let parent = targetApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.notWritable(parent.path)
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoreUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        var mountedVolume: URL?
        var helperStarted = false
        defer {
            if let mountedVolume { try? detach(mountedVolume) }
            if !helperStarted { try? FileManager.default.removeItem(at: workspace) }
        }

        let sourceApp: URL
        switch asset.kind {
        case .diskImage:
            let mountPoint = workspace.appendingPathComponent("Mounted", isDirectory: true)
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            mountedVolume = mountPoint
            try mountDiskImage(downloadedFile, at: mountPoint)
            sourceApp = try findApp(in: mountPoint)
        case .zip:
            let extracted = workspace.appendingPathComponent("Extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            let result = try run("/usr/bin/ditto", ["-x", "-k", downloadedFile.path, extracted.path])
            guard result.status == 0 else {
                throw UpdateInstallError.stagingFailed(result.output)
            }
            sourceApp = try findApp(in: extracted)
        case .other:
            throw UpdateInstallError.unsupportedAsset
        }

        try verify(sourceApp, expectedVersion: expectedVersion)

        let stagedApp = workspace.appendingPathComponent("Staged/Lore.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagedApp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let copy = try run("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        guard copy.status == 0 else {
            throw UpdateInstallError.stagingFailed(copy.output)
        }

        // The mounted image is no longer needed once the app has been copied.
        if let mountedVolume {
            try? detach(mountedVolume)
        }
        mountedVolume = nil

        let helper = workspace.appendingPathComponent("apply-update.sh")
        let log = try updateLogURL()
        try makeHelperScript(target: targetApp, staged: stagedApp, workspace: workspace, log: log)
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let helperProcess = Process()
        helperProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        helperProcess.arguments = [helper.path]
        helperProcess.standardOutput = FileHandle.nullDevice
        helperProcess.standardError = FileHandle.nullDevice
        do {
            try helperProcess.run()
        } catch {
            throw UpdateInstallError.helperFailed(error.localizedDescription)
        }
        helperStarted = true
    }

    // MARK: - Verification

    private func validate(_ url: URL) throws {
        if url.isFileURL {
            guard allowLocalAssets else {
                throw UpdateInstallError.untrustedDownload(url.absoluteString)
            }
            return
        }
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateInstallError.untrustedDownload(url.absoluteString)
        }
        let host = url.host?.lowercased() ?? ""
        let trusted = host == "github.com"
            || host == "objects.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
        guard trusted else {
            throw UpdateInstallError.untrustedDownload(url.absoluteString)
        }
    }

    /// A DMG could contain any app; only replace Lore with an app that calls
    /// itself Lore and carries exactly the version the feed advertised.
    private func verify(_ app: URL, expectedVersion: SemanticVersion) throws {
        guard let bundle = Bundle(url: app) else {
            throw UpdateInstallError.appNotFound
        }
        let identifier = bundle.bundleIdentifier ?? ""
        guard identifier == Self.bundleIdentifier else {
            throw UpdateInstallError.identityMismatch(identifier.isEmpty ? "none" : identifier)
        }
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard let version = SemanticVersion(raw) else {
            throw UpdateInstallError.versionMismatch(expected: expectedVersion.description, found: raw)
        }
        guard version == expectedVersion else {
            throw UpdateInstallError.versionMismatch(expected: expectedVersion.description, found: raw)
        }
    }

    // MARK: - Disk image

    private func mountDiskImage(_ image: URL, at mountPoint: URL) throws {
        let result = try run(
            "/usr/bin/hdiutil",
            ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, image.path]
        )
        guard result.status == 0 else {
            throw UpdateInstallError.mountFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func detach(_ mountPoint: URL) throws {
        let result = try run("/usr/bin/hdiutil", ["detach", mountPoint.path])
        if result.status != 0 {
            _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path])
        }
    }

    /// Releases keep `Lore.app` at the image root; older ones nested it one
    /// folder deep, so a short breadth-first walk covers both without trusting
    /// an arbitrary path from the feed.
    private func findApp(in root: URL) throws -> URL {
        var frontier = [root]
        for _ in 0..<3 {
            var next: [URL] = []
            for directory in frontier {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for item in contents {
                    if item.pathExtension.lowercased() == "app" { return item }
                    let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    // Never follow the `Applications` symlink into the real
                    // /Applications and install whatever Lore happens to be there.
                    if values?.isSymbolicLink == true { continue }
                    if values?.isDirectory == true {
                        next.append(item)
                    }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        throw UpdateInstallError.appNotFound
    }

    // MARK: - Helper

    private func makeHelperScript(target: URL, staged: URL, workspace: URL, log: URL) -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        return """
        #!/bin/sh
        # Written by Lore \(LoreVersion.installed). Waits for the app to quit,
        # swaps the bundle, restores it on failure, then reopens Lore.
        exec >> \(shellQuote(log.path)) 2>&1
        echo "[$(date)] helper started for pid \(pid)"
        target=\(shellQuote(target.path))
        staged=\(shellQuote(staged.path))
        backup="${target}.lore-backup"
        i=0
        while kill -0 \(pid) 2>/dev/null; do
          i=$((i+1))
          [ "$i" -ge 300 ] && break
          sleep 0.1
        done
        if kill -0 \(pid) 2>/dev/null; then
          echo "[$(date)] app \(pid) did not quit; leaving bundle untouched"
          exit 1
        fi
        sleep 0.4
        rm -rf "$backup"
        if [ -e "$target" ]; then
          /bin/mv "$target" "$backup" || { echo "[$(date)] could not move current app"; exit 1; }
        fi
        if /usr/bin/ditto "$staged" "$target"; then
          /usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null
          rm -rf "$backup"
          echo "[$(date)] update installed"
          rm -rf \(shellQuote(workspace.path))
          /usr/bin/open "$target"
        else
          echo "[$(date)] copy failed; restoring previous app"
          rm -rf "$target"
          [ -e "$backup" ] && /bin/mv "$backup" "$target"
          /usr/bin/open "$target"
          exit 1
        fi
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func updateLogURL() throws -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let directory = logs.appendingPathComponent("Logs/Lore", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("update.log")
    }

    // MARK: - Process

    private struct CommandResult {
        let status: Int32
        let output: String
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.stagingFailed("\(tool): \(error.localizedDescription)")
        }
        // Drain before waiting: hdiutil can print more than the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
