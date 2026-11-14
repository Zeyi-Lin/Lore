import Foundation

/// `--bench` launch argument: prints the data-layer costs against the current
/// library and quits. Set `LORA_BENCH_JSON=1` for machine-readable output
/// (used by `scripts/perf-guard.sh`).
@MainActor
enum DataLayerBench {
    static func run(store: LibraryStore) {
        let pins = store.pins
        var metrics: [String: Double] = [:]
        var sink = 0

        func measure(_ label: String, key: String, iterations: Int = 21, _ body: () -> Void) {
            body()
            var best = Double.infinity
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                best = min(best, elapsed)
            }
            metrics[key] = best
            let padded = label.count >= 46 ? label : label + String(repeating: " ", count: 46 - label.count)
            print("  " + padded + String(format: "%8.4f ms", best))
        }

        if ProcessInfo.processInfo.environment["LORA_BENCH_JSON"] != "1" {
            print("== Lora data layer ==  pins: \(pins.count)")
        }
        guard !pins.isEmpty else {
            emit(metrics: metrics, pins: 0, sink: 0)
            return
        }

        let snapshot = LibrarySnapshot(revision: 1, pins: pins)
        let projection = GalleryProjection(snapshot: snapshot, root: store.root)
        let base = GalleryQuery(
            sectionRaw: "all",
            board: nil,
            filterRaw: "all",
            sortRaw: "recent",
            needle: "",
            languageRaw: "en",
            revision: 1
        )

        measure("visible pins, memo hit (body read)", key: "memo_hit_ms") {
            sink &+= projection.visiblePins(for: base).count
        }

        var counter = 0
        measure("cold search query (byte scan)", key: "search_scan_ms") {
            counter += 1
            var query = base
            query.needle = "dark ui \(counter)"
            sink &+= projection.visiblePins(for: query).count
        }

        var boardCounter = 0
        let boards = ["web dashboards", "mobile flows", "landing pages", "editorial", "unsorted"]
        measure("cold board switch query", key: "board_ms") {
            boardCounter += 1
            var query = base
            query.board = boards[boardCounter % boards.count]
            query.needle = "\(boardCounter)"
            sink &+= projection.visiblePins(for: query).count
        }

        measure("card models, memo hit", key: "models_hit_ms") {
            sink &+= projection.cards(for: base).count
        }

        let models = projection.cards(for: base)
        measure("masonry column split", key: "columns_ms") {
            sink &+= MasonryComposer.split(models: models, columns: 4, availableWidth: 1100, spacing: 20).count
        }

        let library = LoraLibrary(version: 1, pins: pins)
        let encoder = LoraJSON.makeEncoder()
        var data = Data()
        measure("library.json encode", key: "encode_ms") {
            data = (try? encoder.encode(library)) ?? Data()
        }
        measure("library.json decode (fast dates)", key: "decode_ms") {
            sink &+= (try? LoraJSON.makeDecoder().decode(LoraLibrary.self, from: data))?.pins.count ?? 0
        }

        if ProcessInfo.processInfo.environment["LORA_BENCH_JSON"] != "1" {
            print("  library.json: \(data.count / 1024) KB")
            print("== bench done ==")
        }
        emit(metrics: metrics, pins: pins.count, sink: sink)
    }

    private static func emit(metrics: [String: Double], pins: Int, sink: Int) {
        guard ProcessInfo.processInfo.environment["LORA_BENCH_JSON"] == "1" else { return }
        let payload: [String: Any] = [
            "pins": pins,
            "metrics": metrics,
            "checksum": sink
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("LORA_BENCH_JSON " + text)
        }
    }
}
