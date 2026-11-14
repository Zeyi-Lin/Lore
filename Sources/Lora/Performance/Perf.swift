import Foundation
import os

/// Signposts for the interaction hot paths. Open Instruments' "Points of
/// Interest" track to see query / write / decode costs per action.
enum Perf {
    static let signposter = OSSignposter(subsystem: "studio.lora.library", category: "interaction")

    @inline(__always)
    static func interval<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return body()
    }

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
