import AppKit
import Foundation

/// Window-resize benchmark for the gallery.
///
/// Live resize is the one interaction where SwiftUI has to lay the whole
/// gallery out again for every point of width change, so it is the easiest
/// place to lose frames. `--resize-bench` sweeps the window width the way a
/// drag does and reports the cost of one layout pass, which is what the frame
/// budget is spent on:
///
///     ./scripts/resize-bench.sh --pins 1000
///
/// The sweep runs three rounds and reports the cheapest one: the machine's
/// background load only ever makes a round slower, so the minimum is the
/// honest estimate of the layout cost. Numbers only mean something in a
/// release build.
@MainActor
enum ResizeBench {
    static func isRequested() -> Bool {
        ProcessInfo.processInfo.arguments.contains("--resize-bench")
    }

    private static let rounds = 3

    static func run(store: LibraryStore) async {
        setvbuf(stdout, nil, _IONBF, 0)
        var report: [String] = []
        func emit(_ line: String) {
            print(line)
            report.append(line)
        }

        guard let window = await mainWindow() else {
            emit("RESIZE_BENCH no window")
            NSApp.terminate(nil)
            return
        }

        // Fixed geometry so runs are comparable, then let the first layout
        // settle (image decode, scroll-view warm-up).
        window.setFrame(NSRect(x: 120, y: 120, width: 1440, height: 900), display: true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let height = window.frame.height
        let origin = window.frame.origin
        // 2 pt per step models a moderate drag: fast enough that the gallery
        // quantises, slow enough to see what the frames in between cost.
        Perf.gridRelayouts = 0
        var widths = Array(stride(from: 1120.0, through: 1720.0, by: 2.0))
        widths += widths.reversed()

        var layout: [[Double]] = []
        var display: [[Double]] = []
        for _ in 0..<rounds {
            var roundLayout: [Double] = []
            var roundDisplay: [Double] = []
            for width in widths {
                let rect = NSRect(x: origin.x, y: origin.y, width: width, height: height)
                // The clock covers resize + layout + display, i.e. what one
                // frame of a drag has to fit into.
                let start = DispatchTime.now().uptimeNanoseconds
                window.setFrame(rect, display: false)
                window.contentView?.layoutSubtreeIfNeeded()
                let layoutEnd = DispatchTime.now().uptimeNanoseconds
                window.contentView?.displayIfNeeded()
                let end = DispatchTime.now().uptimeNanoseconds
                roundLayout.append(Double(layoutEnd - start) / 1_000_000)
                roundDisplay.append(Double(end - layoutEnd) / 1_000_000)
            }
            layout.append(roundLayout)
            display.append(roundDisplay)
        }

        var columns: [Double] = []
        for width in widths {
            let available = max(width - LoraLayout.sidebarWidth - 68, 240)
            let start = DispatchTime.now().uptimeNanoseconds
            _ = store.columns(forWidth: available)
            columns.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }

        let narrow = store.columns(forWidth: max(1120 - LoraLayout.sidebarWidth - 68, 240))
        let wide = store.columns(forWidth: max(1720 - LoraLayout.sidebarWidth - 68, 240))

        emit("RESIZE_BENCH pins=\(store.pins.count) columns=\(narrow.count)..\(wide.count) height=\(Int(height))")
        for (index, round) in layout.enumerated() {
            emit("RESIZE_BENCH layout round\(index) " + stats(round))
        }
        emit("RESIZE_BENCH layout best " + stats(best(layout)))
        emit("RESIZE_BENCH display best " + stats(best(display)))
        emit("RESIZE_BENCH columns " + stats(columns))
        emit("RESIZE_BENCH grid-relayouts=\(Perf.gridRelayouts) for \(widths.count * rounds) frames")
        // When launched through LaunchServices (see scripts/resize-bench.sh)
        // stdout is not connected to the caller, so mirror the report to a file.
        if let path = UserDefaults.standard.string(forKey: "lora.benchOutput"), !path.isEmpty {
            try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }

    /// The cheapest round: background load can only add time.
    private static func best(_ rounds: [[Double]]) -> [Double] {
        rounds.min { lhs, rhs in
            (lhs.reduce(0, +) / Double(max(lhs.count, 1))) < (rhs.reduce(0, +) / Double(max(rhs.count, 1)))
        } ?? []
    }

    private static func mainWindow() async -> NSWindow? {
        for _ in 0..<400 {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                return window
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private static func stats(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return "n=0" }
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return String(
            format: "n=%d mean=%.2fms p50=%.2fms p95=%.2fms max=%.2fms",
            sorted.count, mean, p50, p95, sorted.last ?? 0
        )
    }
}
