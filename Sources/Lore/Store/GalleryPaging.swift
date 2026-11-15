/// How the gallery grows while the user scrolls.
///
/// The library is local, so a "page" is not a network fetch: it is the point
/// where the grid is allowed to lay out more cards. Keeping the laid-out
/// prefix small is what makes the first frame (and every later relayout)
/// proportional to what is on screen rather than to the size of the library —
/// `LazyVStack` skips building offscreen cards, but its layout pass still
/// measures them.
enum GalleryPaging {
    /// Cards laid out on first paint. A few screens on a typical window, so
    /// the gallery is full before the user can scroll past it.
    static let firstPage = 40

    /// Cards added per append. Tied to the column count so one page is always
    /// roughly the same number of rows, whatever the window width.
    static func pageSize(columns: Int) -> Int {
        max(24, columns * 8)
    }

    static func nextLimit(current: Int, total: Int, columns: Int) -> Int {
        guard total > current else { return total }
        return min(total, current + pageSize(columns: columns))
    }
}
