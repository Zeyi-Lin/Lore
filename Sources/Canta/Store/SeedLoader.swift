import Foundation

enum CantaResourceBundle {
    static let bundle: Bundle? = {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Canta_Canta.bundle", isDirectory: true))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("Canta_Canta.bundle", isDirectory: true))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Canta_Canta.bundle", isDirectory: true))
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }()
}

enum SeedLoader {
    static func seedDirectory() -> URL? {
        guard let bundle = CantaResourceBundle.bundle else { return nil }
        let candidates: [URL] = [
            bundle.url(forResource: "Seed", withExtension: nil),
            bundle.resourceURL?.appendingPathComponent("Seed", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("Resources/Seed", isDirectory: true)
        ].compactMap { $0 }

        let fm = FileManager.default
        return candidates.first { url in
            fm.fileExists(atPath: url.appendingPathComponent("seed.json").path)
        }
    }

    /// Reads the library exactly once (the old flow decoded it in
    /// `installIfNeeded` and then again in `LibraryStore.init`), installing the
    /// designed sample library on first launch or when an empty library was
    /// created before seeding. A hidden sentinel keeps an intentionally emptied
    /// library empty.
    static func loadOrInstall(root: URL) throws -> CantaLibrary {
        try CantaPaths.ensureDirectories(root: root)
        let fm = FileManager.default
        let libraryURL = CantaPaths.libraryFile(root: root)
        let seededMarker = root.appendingPathComponent(".canta-seeded")

        if fm.fileExists(atPath: libraryURL.path) {
            let data = try Data(contentsOf: libraryURL)
            let existing = try CantaJSON.makeDecoder().decode(CantaLibrary.self, from: data)
            if !existing.pins.isEmpty {
                if !fm.fileExists(atPath: seededMarker.path) {
                    try? Data().write(to: seededMarker, options: .atomic)
                }
                return existing
            }
            if fm.fileExists(atPath: seededMarker.path) {
                return existing
            }
        }

        guard let seedDirectory = seedDirectory() else {
            let empty = CantaLibrary()
            if !fm.fileExists(atPath: libraryURL.path) {
                try CantaJSON.makeEncoder().encode(empty).write(to: libraryURL, options: .atomic)
            }
            return empty
        }

        let seedFile = seedDirectory.appendingPathComponent("seed.json")
        guard let data = try? Data(contentsOf: seedFile),
              let seedLibrary = try? CantaJSON.makeDecoder().decode(CantaLibrary.self, from: data) else {
            let empty = CantaLibrary()
            try? CantaJSON.makeEncoder().encode(empty).write(to: libraryURL, options: .atomic)
            return empty
        }

        var installed: [Pin] = []
        for var pin in seedLibrary.pins {
            let imageSource = seedDirectory.appendingPathComponent(pin.image)
            guard fm.fileExists(atPath: imageSource.path) else { continue }
            let imageDestination = root.appendingPathComponent(pin.image)
            try fm.createDirectory(at: imageDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: imageDestination.path) { try? fm.removeItem(at: imageDestination) }
            do {
                try fm.copyItem(at: imageSource, to: imageDestination)
            } catch {
                continue
            }

            if let thumbnail = pin.thumbnail {
                let thumbSource = seedDirectory.appendingPathComponent(thumbnail)
                if fm.fileExists(atPath: thumbSource.path) {
                    let thumbDestination = root.appendingPathComponent(thumbnail)
                    try? fm.createDirectory(at: thumbDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: thumbDestination.path) { try? fm.removeItem(at: thumbDestination) }
                    try? fm.copyItem(at: thumbSource, to: thumbDestination)
                }
            }
            if pin.fileSize == 0 {
                pin.fileSize = (try? fm.attributesOfItem(atPath: imageDestination.path)[.size] as? Int) ?? 0
            }
            installed.append(pin)
        }

        guard !installed.isEmpty else {
            let empty = CantaLibrary()
            if !fm.fileExists(atPath: libraryURL.path) {
                try CantaJSON.makeEncoder().encode(empty).write(to: libraryURL, options: .atomic)
            }
            return empty
        }

        let library = CantaLibrary(version: 1, pins: installed)
        try CantaJSON.makeEncoder().encode(library).write(to: libraryURL, options: .atomic)
        try? Data().write(to: seededMarker, options: .atomic)
        return library
    }
}
