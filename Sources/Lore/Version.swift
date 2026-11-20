import Foundation

/// The single source of truth for the app version.
///
/// `scripts/build-app.sh` reads the `static let current` line and stamps it into
/// `CFBundleShortVersionString`; Settings → About renders the bundle version and
/// the updater compares GitHub's latest tag against it. Bumping this one line is
/// therefore enough to move all three in lockstep. The release procedure lives in
/// `docs/RELEASING.md`.
enum LoreVersion {
    static let current = "1.3.0"

    /// What the running app reports. A packaged `Lore.app` answers with its
    /// Info.plist; a bare `swift run Lore` (no bundle) falls back to the
    /// compiled constant. `LORE_VERSION_OVERRIDE` exists so update smokes can
    /// pretend to be an older build without rebuilding.
    static var installed: String {
        if let override = ProcessInfo.processInfo.environment["LORE_VERSION_OVERRIDE"],
           !override.isEmpty {
            return override
        }
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let bundled, !bundled.isEmpty { return bundled }
        return current
    }

    /// Shown in Settings → About and the app menu, e.g. `Lore 1.2.1`.
    static var display: String { "Lore \(installed)" }
}
