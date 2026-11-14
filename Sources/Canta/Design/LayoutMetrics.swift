import SwiftUI

/// Width of the main content column, i.e. the window width minus the sidebar.
/// Views use it to recompute responsive layouts synchronously during a window
/// resize instead of relying on a lagging geometry preference.
private struct CantaContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var cantaContentWidth: CGFloat {
        get { self[CantaContentWidthKey.self] }
        set { self[CantaContentWidthKey.self] = newValue }
    }
}
