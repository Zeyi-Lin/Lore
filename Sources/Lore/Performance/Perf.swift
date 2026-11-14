import Foundation
import os

/// Signposts for the interaction hot paths. Open Instruments' "Points of
/// Interest" track to see query / write / decode costs per action.
enum Perf {
    static let signposter = OSSignposter(subsystem: "studio.lore.library", category: "interaction")

    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return body()
    }

    /// How many times the gallery committed a new layout width. A resize
    /// sweep should touch this once per layout quantum rather than once per
    /// point of width change; `--resize-bench` reads it as a load-independent
    /// check on that behaviour.
    nonisolated(unsafe) static var gridRelayouts = 0

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
