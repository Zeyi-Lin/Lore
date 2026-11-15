import SwiftUI
import AppKit

/// Card actions are passed in as values so `PinCard` does not observe the
/// store. They are intentionally excluded from `Equatable`: recreating them
/// must not force every visible card to rebuild.
struct PinCardActions {
    var open: (UUID) -> Void
    var toggleSelection: (UUID) -> Void
    var toggleFavorite: (UUID) -> Void
    var copySnippet: (UUID) -> Void
    var copyImage: (UUID) -> Void
    var moveToBoard: (UUID, String) -> Void
    var openOriginal: (UUID) -> Void
    var reveal: (UUID) -> Void
    var openSource: (UUID) -> Void
    var requestDelete: (UUID) -> Void
    var prefetchDetail: (UUID) -> Void
    var boardNames: () -> [String]
    /// Starts a drag of this card (or of the whole selection) so it can be
    /// dropped on a sidebar board.
    var beginDrag: (UUID) -> String
    /// How many pins the drag starting on this card carries. Used only for the
    /// compact drag preview badge.
    var dragCount: (UUID) -> Int
}

struct PinCard: View, Equatable {
    let model: PinCardModel
    let isSelected: Bool
    let isSelecting: Bool
    let actions: PinCardActions

    @State private var hovering = false
    @State private var hoverPrefetchTask: Task<Void, Never>?

    static func == (lhs: PinCard, rhs: PinCard) -> Bool {
        lhs.model == rhs.model && lhs.isSelected == rhs.isSelected && lhs.isSelecting == rhs.isSelecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            image
            caption
        }
        .contentShape(Rectangle())
        .onDrag {
            LoreDrag.provider(marker: actions.beginDrag(model.id))
        } preview: {
            PinDragPreview(model: model, count: max(1, actions.dragCount(model.id)))
        }
        .onTapGesture {
            if isSelecting {
                actions.toggleSelection(model.id)
            } else {
                actions.open(model.id)
            }
        }
        .onHover { value in
            guard hovering != value else { return }
            withAnimation(.easeOut(duration: 0.16)) { hovering = value }
            hoverPrefetchTask?.cancel()
            if value && !isSelecting {
                hoverPrefetchTask = Task {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    actions.prefetchDetail(model.id)
                }
            }
        }
        .onDisappear { hoverPrefetchTask?.cancel() }
        .contextMenu { contextMenu }
        .scaleEffect(hovering && !isSelecting ? 1.004 : 1)
        .shadow(
            color: .black.opacity(hovering && !isSelecting ? 0.10 : 0),
            radius: hovering ? 10 : 0,
            x: 0,
            y: 4
        )
        .pointerCursor()
    }

    private var image: some View {
        Color.clear
            .aspectRatio(model.aspectRatio, contentMode: .fit)
            .overlay {
                LibraryImage(paths: model.imageCandidates, maxPixel: 640, contentMode: .fill)
            }
            .overlay {
                if model.isGIF, hovering, !isSelecting {
                    AnimatedGIFView(paths: model.animatedPaths)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isSelecting && isSelected ? Theme.red : Color.clear, lineWidth: 3)
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    selectionBadge
                        .padding(10)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                saveButton
                    .padding(10)
                    .opacity(isSelecting ? 0 : (hovering ? 1 : 0))
                    .scaleEffect(hovering ? 1 : 0.9, anchor: .topTrailing)
                    .allowsHitTesting(!isSelecting)
            }
            .overlay(alignment: .bottomTrailing) {
                if model.isGIF {
                    gifBadge
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomLeading) {
                metadataPill
                    .padding(10)
                    .opacity(isSelecting ? 0 : (hovering ? 1 : 0))
                    .offset(y: hovering ? 0 : 5)
            }
            .opacity(isSelecting && !isSelected ? 0.86 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.red : Color.white.opacity(0.94))
                .frame(width: 25, height: 25)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Circle()
                    .strokeBorder(Theme.ink.opacity(0.16), lineWidth: 1)
                    .frame(width: 25, height: 25)
            }
        }
        .allowsHitTesting(false)
    }

    private var saveButton: some View {
        Button {
            actions.toggleFavorite(model.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .bold))
                Text(model.isFavorite ? T("Saved") : T("Save"))
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Theme.red))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(PressableStyle())
        .help(model.isFavorite ? T("Remove from favorites") : T("Save to favorites"))
    }

    private var gifBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 7, weight: .bold))
            Text(T("GIF"))
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .frame(height: 21)
        // A flat tint instead of `.ultraThinMaterial`: the material re-samples
        // the backdrop whenever the card's size changes, which is every frame
        // of a window resize, and the visual difference at this size is nil.
        .background(Capsule().fill(Color.black.opacity(0.56)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var metadataPill: some View {
        HStack(spacing: 6) {
            Image(systemName: model.kindIcon)
                .font(.system(size: 9, weight: .semibold))
            Text(model.pixelLabel)
                .font(Theme.mono(9.5, weight: .medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.boardColor(model.board))
                    .frame(width: 5.5, height: 5.5)
                Text(model.boardLabel)
                    .lineLimit(1)
                Text("·")
                Text(model.pixelLabel)
                if model.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.red)
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(T("Open pin")) { actions.open(model.id) }
        Button(model.isFavorite ? T("Remove from favorites") : T("Add to favorites")) {
            actions.toggleFavorite(model.id)
        }
        Divider()
        Button(T("Copy agent snippet")) { actions.copySnippet(model.id) }
        Button(T("Copy image")) { actions.copyImage(model.id) }
        Menu(T("Move to board")) {
            ForEach(actions.boardNames(), id: \.self) { board in
                Button {
                    actions.moveToBoard(model.id, board)
                } label: {
                    if board == model.board {
                        Label(localizedBoard(board), systemImage: "checkmark")
                    } else {
                        Text(localizedBoard(board))
                    }
                }
            }
        }
        Divider()
        Button(T("Open original")) { actions.openOriginal(model.id) }
        Button(T("Reveal in Finder")) { actions.reveal(model.id) }
        if model.hasSource {
            Button(T("Open source page")) { actions.openSource(model.id) }
        }
        Divider()
        Button(T("Delete pin"), role: .destructive) {
            actions.requestDelete(model.id)
        }
    }
}

/// A small drag ghost instead of the full card: the gallery card is large, and
/// its default preview hides the board rows and the new trash target while the
/// user is trying to aim. Keep the thumbnail but drop the captions, buttons and
/// hover chrome.
private struct PinDragPreview: View {
    let model: PinCardModel
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LibraryImage(paths: model.imageCandidates, maxPixel: 640, contentMode: .fill)
                .frame(width: 132, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.24), radius: 12, y: 5)

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.red))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                    .offset(x: 5, y: -5)
            }
        }
        .frame(width: 142, height: 98)
    }
}
