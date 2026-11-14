import Foundation

enum LoraPaths {
    /// `LORA_HOME` — and the pre-rename `CANTA_HOME` — let benchmarks and smoke
    /// tests point at a scratch library.
    static var dataRoot: URL {
        if let override = environmentRoot { return override }
        return applicationSupportBase.appendingPathComponent("Lora", isDirectory: true)
    }

    private static var applicationSupportBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static var environmentRoot: URL? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["LORA_HOME", "CANTA_HOME"] {
            if let value = environment[key], !value.isEmpty {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
        }
        return nil
    }

    static func imagesDirectory(root: URL) -> URL {
        root.appendingPathComponent("Images", isDirectory: true)
    }

    static func thumbnailsDirectory(root: URL) -> URL {
        root.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// Small (640 px) derivatives used by the gallery grid. Paths are derived
    /// from the pin id, so this directory needs no representation in
    /// `library.json` and existing libraries keep working unchanged.
    static func cardsDirectory(root: URL) -> URL {
        root.appendingPathComponent("Cards", isDirectory: true)
    }

    static func libraryFile(root: URL) -> URL {
        root.appendingPathComponent("library.json")
    }

    static func ensureDirectories(root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: imagesDirectory(root: root), withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnailsDirectory(root: root), withIntermediateDirectories: true)
        try fm.createDirectory(at: cardsDirectory(root: root), withIntermediateDirectories: true)
    }

    // MARK: - Rename migration

    /// The pre-rename library lived in `Application Support/Canta`. Move it
    /// once, so a rename never costs a pin. A same-volume move is a rename, so
    /// even a multi-gigabyte library moves instantly; if that fails we copy
    /// instead of risking the library.
    static func migrateLegacyLibraryIfNeeded() {
        guard environmentRoot == nil else { return }
        let fm = FileManager.default
        let current = applicationSupportBase.appendingPathComponent("Lora", isDirectory: true)
        let legacy = applicationSupportBase.appendingPathComponent("Canta", isDirectory: true)
        guard !fm.fileExists(atPath: current.path),
              fm.fileExists(atPath: legacy.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: current)
        } catch {
            try? fm.copyItem(at: legacy, to: current)
        }
    }

    /// The bundle identifier changed too, so the new app starts with an empty
    /// defaults domain. Carry the handful of settings we persist, once.
    static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let marker = "lora.migration.canta"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)

        guard let legacy = legacyPreferences() else { return }
        let mapping = [
            "canta.language": "lora.language",
            "canta.agent.port": "lora.agent.port",
            "canta.agent.enabled": "lora.agent.enabled",
            "canta.agent.metadataEdits": "lora.agent.metadataEdits",
            "canta.defaultBoard": "lora.defaultBoard",
            "canta.expandedBoardGroups": "lora.expandedBoardGroups"
        ]
        for (old, new) in mapping {
            if let value = legacy[old] {
                defaults.set(value, forKey: new)
            }
        }
    }

    private static func legacyPreferences() -> [String: Any]? {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/studio.canta.library.plist")
        if let data = try? Data(contentsOf: plist),
           let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = value as? [String: Any] {
            return dictionary
        }
        return UserDefaults(suiteName: "studio.canta.library")?.dictionaryRepresentation()
    }
}

// MARK: - JSON

enum LoraJSON {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// On-disk format: `2026-11-13T09:12:00Z`. Hand-rolled because
    /// `ISO8601DateFormatter` costs ~33 µs per parse; two dates per pin made
    /// date parsing ~80% of library load time.
    static func parseDate(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        if bytes.count == 20,
           bytes[4] == 45, bytes[7] == 45, bytes[10] == 84,
           bytes[13] == 58, bytes[16] == 58, bytes[19] == 90,
           bytes[0] >= 48, bytes[1] >= 48, bytes[2] >= 48, bytes[3] >= 48,
           bytes[5] >= 48, bytes[6] >= 48, bytes[8] >= 48, bytes[9] >= 48,
           bytes[11] >= 48, bytes[12] >= 48, bytes[14] >= 48, bytes[15] >= 48,
           bytes[17] >= 48, bytes[18] >= 48 {
            let year = Int(bytes[0] - 48) * 1000 + Int(bytes[1] - 48) * 100 + Int(bytes[2] - 48) * 10 + Int(bytes[3] - 48)
            let month = Int(bytes[5] - 48) * 10 + Int(bytes[6] - 48)
            let day = Int(bytes[8] - 48) * 10 + Int(bytes[9] - 48)
            let hour = Int(bytes[11] - 48) * 10 + Int(bytes[12] - 48)
            let minute = Int(bytes[14] - 48) * 10 + Int(bytes[15] - 48)
            let second = Int(bytes[17] - 48) * 10 + Int(bytes[18] - 48)
            guard (1...12).contains(month), (1...31).contains(day),
                  (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
                return nil
            }
            let days = daysFromCivil(year, month, day)
            return Date(timeIntervalSince1970: Double(days * 86_400 + hour * 3_600 + minute * 60 + second))
        }
        return iso8601.date(from: string) ?? iso8601Fractional.date(from: string)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's
    /// `days_from_civil`), integer-only.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        var y = year
        if month <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func makeEncoder(prettyPrinted: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = parseDate(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        return decoder
    }

}
