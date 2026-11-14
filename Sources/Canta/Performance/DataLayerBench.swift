import Foundation

/// `--bench` launch argument: prints the new data-layer costs against the
/// current library and quits. Used to verify the optimization on real data.
@MainActor
enum DataLayerBench {
    static func run(store: LibraryStore) {
        let pins = store.pins
        print("== Canta data layer ==  pins: \(pins.count)")
        guard !pins.isEmpty else {
            print("empty library — nothing to measure")
            return
        }

        let snapshot = LibrarySnapshot(revision: 1, pins: pins)
        let projection = GalleryProjection(snapshot: snapshot, root: store.root)
        var sink = 0
        let base = GalleryQuery(sectionRaw: "all", board: nil, filterRaw: "all", sortRaw: "recent", needle: "", languageRaw: "en", revision: 1)

        func measure(_ label: String, iterations: Int = 21, _ body: () -> Void) {
            body()
            var best = Double.infinity
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                best = min(best, elapsed)
            }
            let padded = label.count >= 46 ? label : label + String(repeating: " ", count: 46 - label.count)
            print("  " + padded + String(format: "%8.4f ms", best))
        }

        measure("visible pins, memo hit (body read)") {
            sink &+= projection.visiblePins(for: base).count
        }

        var counter = 0
        measure("cold search query (unique needle)") {
            counter += 1
            var query = base
            query.needle = "dark ui \(counter)"
            sink &+= projection.visiblePins(for: query).count
        }

        var boardCounter = 0
        let boards = ["web dashboards", "mobile flows", "landing pages", "editorial", "unsorted"]
        measure("cold board switch query") {
            boardCounter += 1
            var query = base
            query.board = boards[boardCounter % boards.count]
            query.needle = "\(boardCounter)"
            sink &+= projection.visiblePins(for: query).count
        }

        measure("card models, memo hit") {
            sink &+= projection.cards(for: base).count
        }

        let models = projection.cards(for: base)
        measure("masonry column split (1000+ cards)") {
            sink &+= MasonryComposer.split(models: models, columns: 4, availableWidth: 1100, spacing: 20).count
        }

        let library = CantaLibrary(version: 1, pins: pins)
        let encoder = CantaJSON.makeEncoder()
        var data = Data()
        measure("library.json encode") {
            data = (try? encoder.encode(library)) ?? Data()
        }
        measure("library.json decode (fast dates)") {
            sink &+= (try? CantaJSON.makeDecoder().decode(CantaLibrary.self, from: data))?.pins.count ?? 0
        }
        print("  library.json: \(data.count / 1024) KB   checksum \(sink)")
        print("== bench done ==")
    }
}
