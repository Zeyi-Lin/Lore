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
    var boardNames: () -> [String]
}

struct PinCard: View, Equatable {
    let model: PinCardModel
    let isSelected: Bool
    let isSelecting: Bool
    let actions: PinCardActions

    @State private var hovering = false

    static func == (lhs: PinCard, rhs: PinCard) -> Bool {
        lhs.model == rhs.model && lhs.isSelected == rhs.isSelected && lhs.isSelecting == rhs.isSelecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            image
            caption
        }
        .contentShape(Rectangle())
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
        }
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
        .background(.ultraThinMaterial, in: Capsule())
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
    }
}
