import SwiftUI

enum EmptyMode {
    case emptyLibrary
    case noResults
}

struct EmptyStateView: View {
    @Environment(LibraryStore.self) private var store
    var mode: EmptyMode

    var body: some View {
        VStack(spacing: 0) {
            if mode == .emptyLibrary {
                EmptyArtwork()
                    .frame(width: 300, height: 208)
                    .padding(.bottom, 26)
            } else {
                ZStack {
                    Circle().fill(Theme.parchment).frame(width: 104, height: 104)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .padding(.bottom, 22)
            }

            Text(mode == .emptyLibrary ? T("Your library is waiting") : T("No pins match"))
                .font(Theme.display(24, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)

            Text(subtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            HStack(spacing: 9) {
                if mode == .emptyLibrary {
                    LoreButton(title: T("Capture screenshot"), icon: "viewfinder", variant: .primary) {
                        store.capturePresented = true
                    }
                    LoreButton(title: T("Import images"), icon: "square.and.arrow.down", variant: .secondary) {
                        ImportPanel.present(store: store)
                    }
                } else {
                    LoreButton(title: T("Clear search & filters"), icon: "arrow.counterclockwise", variant: .secondary) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.clearSearch()
                            store.filter = .all
                            store.selectedBoard = nil
                            store.clearColorFilters()
                            store.section = .all
                        }
                    }
                }
            }
            .padding(.top, 22)

            if mode == .emptyLibrary {
                HStack(spacing: 7) {
                    Image(systemName: "clipboard")
                    Text(T("or press ⌘V to pin the clipboard"))
                    Text("·")
                    Image(systemName: "viewfinder")
                    Text(T("⇧⌘2 for a screen capture"))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkTertiary.opacity(0.9))
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
    }

    private var subtitle: String {
        switch mode {
        case .emptyLibrary:
            return T("Pin the interfaces that make you stop scrolling.\nEvery capture keeps its pixels, palette, and context — ready for your agent.")
        case .noResults:
            return T("Try a different phrase, or loosen the filters.\nBoards, tags, and colors are searchable too.")
        }
    }
}

struct EmptyArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.parchmentDeep)
                .frame(width: 208, height: 138)
                .rotationEffect(.degrees(-10))
                .offset(x: -36, y: 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                        .frame(width: 208, height: 138)
                        .rotationEffect(.degrees(-10))
                        .offset(x: -36, y: 7)
                }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.parchmentDeep.opacity(0.7))
                .frame(width: 208, height: 138)
                .rotationEffect(.degrees(9))
                .offset(x: 40, y: 3)

            screenshotCard
                .rotationEffect(.degrees(-2))
                .offset(x: 2, y: 0)

            // small floating tag
            HStack(spacing: 5) {
                Circle().fill(Theme.moss).frame(width: 5, height: 5)
                Text(T("agent ready"))
                    .font(Theme.mono(8.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Theme.paper))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .offset(x: -128, y: 82)
        }
    }

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(Theme.red.opacity(0.75)).frame(width: 5, height: 5)
                Circle().fill(Theme.amber.opacity(0.65)).frame(width: 5, height: 5)
                Circle().fill(Theme.moss.opacity(0.55)).frame(width: 5, height: 5)
                Spacer()
                Capsule().fill(Theme.parchmentDeep).frame(width: 44, height: 5)
            }
            .padding(.horizontal, 13)
            .frame(height: 25)

            Hairline(color: Theme.hairline.opacity(0.8))

            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? Theme.red.opacity(0.7) : Theme.parchmentDeep)
                            .frame(width: index == 0 ? 30 : 24, height: 4)
                    }
                }
                .frame(width: 33, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Text(T("A quiet dashboard"))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Capsule().fill(Theme.parchmentDeep).frame(width: 26, height: 9)
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.red.opacity(0.12)).frame(height: 25)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.parchment).frame(height: 25)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.moss.opacity(0.13)).frame(height: 25)
                    }
                    HStack(spacing: 4) {
                        Capsule().fill(Theme.parchmentDeep).frame(width: 48, height: 4)
                        Capsule().fill(Theme.parchmentDeep).frame(width: 22, height: 4)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        }
        .frame(width: 208, height: 138)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.09), radius: 24, x: 0, y: 12)
    }
}