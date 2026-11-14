import SwiftUI

struct BatchActionBar: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showBoardPicker = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 5) {
            countChip

            barDivider

            BatchBarButton(
                icon: store.allVisibleSelected ? "checkmark.circle.fill" : "checkmark.circle",
                label: store.allVisibleSelected ? T("Deselect all") : T("Select all"),
                isEnabled: !store.filteredPins.isEmpty
            ) {
                if store.allVisibleSelected {
                    store.clearSelection()
                } else {
                    store.selectAllVisible()
                }
            }

            barDivider

            BatchBarButton(
                icon: store.selectedPinsAreFavorites ? "heart.fill" : "heart",
                label: store.selectedPinsAreFavorites ? T("Unfavorite") : T("Favorite"),
                isEnabled: !store.selectedPinIDs.isEmpty
            ) {
                store.toggleSelectedFavorites()
            }

            BatchBarButton(
                icon: "folder",
                label: T("Move"),
                isEnabled: !store.selectedPinIDs.isEmpty
            ) {
                showBoardPicker.toggle()
            }
            .popover(isPresented: $showBoardPicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.allBoardNames, id: \.self) { board in
                        Button {
                            store.moveSelectedPins(toBoard: board)
                            showBoardPicker = false
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Theme.boardColor(board))
                                    .frame(width: 7, height: 7)
                                Text(localizedBoard(board))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer(minLength: 30)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PointerPlainButtonStyle())
                    }
                }
                .padding(6)
                .frame(width: 220)
            }

            BatchBarButton(
                icon: "sparkles",
                label: T("Copy"),
                isEnabled: !store.selectedPinIDs.isEmpty
            ) {
                store.copySelectedAgentContext()
            }
            .help(T("Copy context"))

            BatchBarButton(
                icon: "trash",
                label: T("Delete"),
                isEnabled: !store.selectedPinIDs.isEmpty,
                destructive: true
            ) {
                showDeleteConfirm = true
            }

            barDivider

            BatchBarButton(icon: "xmark", label: T("Done"), isEnabled: true) {
                store.endSelection()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.ink.opacity(0.97))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .alert(TF("Delete %ld pins?", store.selectedPinIDs.count), isPresented: $showDeleteConfirm) {
            Button(T("Delete"), role: .destructive) {
                store.deleteSelectedPins()
            }
            Button(T("Cancel"), role: .cancel) { }
        } message: {
            Text(T("This removes the original images and metadata from Canta."))
        }
    }

    private var countChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(TF("%ld selected", store.selectedPinIDs.count))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .frame(minWidth: 98, alignment: .leading)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 3)
    }
}

private struct BatchBarButton: View {
    var icon: String
    var label: String
    var isEnabled: Bool
    var destructive: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(destructive
                             ? Color(hex: 0xFF8A8A)
                             : Color.white.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering && isEnabled ? Color.white.opacity(0.09) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusEffectDisabled()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}