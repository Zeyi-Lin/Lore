import SwiftUI

/// Window chrome metrics shared by the sidebar, its full-height divider and
/// the root layout. The sidebar is a single plane that runs from the window's
/// top edge down, so the traffic-light strip reads as part of it instead of a
/// separate title-bar band.
enum LoreLayout {
    static let sidebarWidth: CGFloat = 246
    /// Height of the window's title-bar band. The sidebar keeps its content
    /// clear of the traffic lights by this much; the content column lifts into
    /// the band instead, so its top row sits beside the window controls.
    static let titlebarInset: CGFloat = 32
    /// Top padding of the content column's toolbar row, measured from the
    /// window's top edge.
    static let contentTopPadding: CGFloat = 10
    /// Height of the toolbar row itself (the search field's pill). The
    /// title-bar-like zoom zone fills exactly this row.
    static let toolbarHeight: CGFloat = 41
}

