import SwiftUI
import AppKit

struct PinCard: View {
    let pin: Pin

    @EnvironmentObject private var store: LibraryStore
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            image
            caption
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if store.isSelectingPins {
                store.toggleSelection(pin.id)
            } else {
                store.openDetail(pin)
            }
        }
        .onHover { value in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                hovering = value
            }
        }
        .contextMenu { contextMenu }
        .scaleEffect(hovering && !store.isSelectingPins ? 1.006 : 1)
        .shadow(color: .black.opacity(hovering && !store.isSelectingPins ? 0.12 : 0), radius: 20, x: 0, y: 10)
    }

    private var image: some View {
        Color.clear
            .aspectRatio(pin.aspectRatio, contentMode: .fit)
            .overlay {
                LibraryImage(path: store.thumbnailURL(for: pin).path, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(store.isSelectingPins && isSelected ? Theme.red : Color.clear, lineWidth: 3)
            }
            .overlay(alignment: .topLeading) {
                if store.isSelectingPins {
                    selectionBadge
                        .padding(10)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                saveButton
                    .padding(10)
                    .opacity(store.isSelectingPins ? 0 : (hovering ? 1 : 0))
                    .scaleEffect(hovering ? 1 : 0.9, anchor: .topTrailing)
                    .allowsHitTesting(!store.isSelectingPins)
            }
            .overlay(alignment: .bottomLeading) {
                metadataPill
                    .padding(10)
                    .opacity(store.isSelectingPins ? 0 : (hovering ? 1 : 0))
                    .offset(y: hovering ? 0 : 5)
            }
            .opacity(store.isSelectingPins && !isSelected ? 0.86 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var isSelected: Bool {
        store.selectedPinIDs.contains(pin.id)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                store.toggleFavorite(pin)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pin.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .bold))
                Text(pin.isFavorite ? T("Saved") : T("Save"))
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Theme.red))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(PressableStyle())
        .help(pin.isFavorite ? T("Remove from favorites") : T("Save to favorites"))
    }

    private var metadataPill: some View {
        HStack(spacing: 6) {
            Image(systemName: pin.kind.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(pin.pixelLabel)
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
            Text(pin.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.boardColor(pin.board))
                    .frame(width: 5.5, height: 5.5)
                Text(localizedBoard(pin.board))
                    .lineLimit(1)
                Text("·")
                Text(pin.pixelLabel)
                if pin.isFavorite {
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
        Button(T("Open pin")) { store.openDetail(pin) }
        Button(pin.isFavorite ? T("Remove from favorites") : T("Add to favorites")) {
            store.toggleFavorite(pin)
        }
        Divider()
        Button(T("Copy agent snippet")) { store.copyAgentSnippet(for: pin) }
        Button(T("Copy image")) { store.copyImage(pin) }
        Menu(T("Move to board")) {
            ForEach(store.allBoardNames, id: \.self) { board in
                Button {
                    store.movePin(pin.id, toBoard: board)
                } label: {
                    if board == pin.board {
                        Label(localizedBoard(board), systemImage: "checkmark")
                    } else {
                        Text(localizedBoard(board))
                    }
                }
            }
        }
        Divider()
        Button(T("Open original")) { store.openOriginal(pin) }
        Button(T("Reveal in Finder")) { store.revealPin(pin) }
        if pin.sourceURL != nil {
            Button(T("Open source page")) { store.openSource(pin) }
        }
    }
}