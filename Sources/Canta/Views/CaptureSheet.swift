import SwiftUI
import UniformTypeIdentifiers

struct CaptureSheet: View {
    @Environment(LibraryStore.self) private var store
    @State private var board = "Unsorted"
    @State private var dropTargeted = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.36)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                VStack(alignment: .leading, spacing: 0) {
                    header
                    dropZone
                        .padding(.top, 22)
                    actions
                        .padding(.top, 16)
                    Divider()
                        .overlay(Theme.hairline)
                        .padding(.top, 22)
                    footer
                        .padding(.top, 16)
                }
                .padding(26)
                .frame(width: min(640, geo.size.width - 80))
                .background(Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 50, y: 22)
                .overlay(alignment: .topTrailing) {
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 29, height: 29)
                            .background(Circle().fill(Theme.parchment))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(16)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.975)))
        .onAppear {
            board = store.selectedBoard ?? store.defaultBoard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(Theme.red).frame(width: 5, height: 5)
                Text(T("QUICK CAPTURE"))
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(Theme.inkTertiary)
            }

            Text(T("Pin something worth referencing."))
                .font(.system(size: 26, weight: .bold))
                .tracking(-1)
                .foregroundStyle(Theme.ink)

            Text(T("Screenshots in, structure out. Canta reads pixels, palette, and dimensions for you."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .lineSpacing(2)
        }
        .padding(.trailing, 24)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(dropTargeted ? Theme.redWash : Theme.parchment)
                    .frame(width: 58, height: 58)
                Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "photo.stack")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(dropTargeted ? Theme.red : Theme.inkSecondary)
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(Theme.red))
                    .offset(x: 23, y: -23)
                    .shadow(color: Theme.red.opacity(0.3), radius: 5, y: 2)
            }

            Text(dropTargeted ? T("Release to pin") : T("Drop screenshots here"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(T("or paste with ⇧⌘V · PNG, JPEG, HEIC, TIFF"))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 195)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(dropTargeted ? Theme.redWash.opacity(0.55) : Theme.parchment.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    dropTargeted ? Theme.red : Theme.inkTertiary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
        )
        .scaleEffect(dropTargeted ? 1.01 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: dropTargeted)
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted) { providers in
            let accepted = DropReceiver.handle(providers: providers, store: store, board: board)
            if accepted { close() }
            return accepted
        }
    }

    private var actions: some View {
        HStack(spacing: 9) {
            CantaButton(title: T("Take screenshot"), icon: "viewfinder", variant: .primary, shortcut: "⇧⌘2") {
                close()
                Task { await store.captureScreenshot(board: board) }
            }

            CantaButton(title: T("Choose images"), icon: "square.and.arrow.down", variant: .secondary) {
                close()
                ImportPanel.present(store: store, board: board)
            }

            CantaButton(title: T("Paste"), icon: "doc.on.clipboard", variant: .ghost, shortcut: "⇧⌘V") {
                close()
                Task { await store.pasteFromClipboard(board: board) }
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(T("ADD TO"))
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkTertiary)
                Menu {
                    ForEach(store.allBoardNames, id: \.self) { name in
                        Button {
                            board = name
                        } label: {
                            if board == name {
                                Label(localizedBoard(name), systemImage: "checkmark")
                            } else {
                                Label(localizedBoard(name), systemImage: "circle.fill")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.boardColor(board)).frame(width: 6, height: 6)
                        Text(localizedBoard(board))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .background(Capsule().fill(Theme.parchment))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .focusable(false)
                .fixedSize()
                .pointerCursor()
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text(T("Local only"))
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(Theme.inkTertiary)
            .help(T("Images are stored on this Mac and never uploaded."))
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            store.capturePresented = false
        }
    }
}