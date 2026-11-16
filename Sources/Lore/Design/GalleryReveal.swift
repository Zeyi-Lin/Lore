import Foundation

/// Remembers which cards have already played their entrance animation.
///
/// The lazy columns recycle card views: a card scrolled out of the feed and
/// back is a new view with fresh `@State`, and replaying the fade on every
/// return would make scrolling feel like it is constantly loading. The
/// "first time" memory therefore lives outside a single card, and the card
/// seeds its initial opacity from it so a returning card never flashes.
///
/// Main-thread only: views read and write it from `init`, `body` and
/// `onAppear`.
final class GalleryReveal: @unchecked Sendable {
    static let shared = GalleryReveal()

    private var seen: Set<UUID> = []

    private init() {}

    func hasSeen(_ id: UUID) -> Bool { seen.contains(id) }

    func markSeen(_ id: UUID) { seen.insert(id) }
}
