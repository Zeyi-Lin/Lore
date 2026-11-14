import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @State private var dropTargeted = false
    /// The scroll-view warm-up is only useful while the app is starting; after
    /// that it is a live subtree that every resize pass has to lay out.
    @State private var prewarming = true

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            // The sidebar is one full-height plane: its tint starts at the
            // window's top edge so the traffic-light strip belongs to the
            // panel instead of floating in a separate title-bar band. The
            // divider itself is drawn after the content (see below) so the
            // sidebar's own background cannot cover it.
            HStack(spacing: 0) {
                Theme.parchment
                    .frame(width: LoraLayout.sidebarWidth)
                Color.clear
            }
            .ignoresSafeArea()

            // A fixed-width sidebar plus a content column pinned to the width
            // the window gives it. The pin is not optional: the gallery's grid
            // has a minimum width of its own (the sum of its columns), so
            // without it a narrow window keeps the old, wide content, the
            // column overflows instead of shrinking, and the gallery never
            // sheds a column. Keeping the sidebar *outside* the reader means a
            // drag still never re-evaluates the sidebar tree.
            HStack(spacing: 0) {
                // The sidebar still clears the traffic lights, so it keeps
                // the title-bar inset; the content column lifts into that
                // band (its top row shares the row with the window
                // controls) so the library starts at the window's top edge.
                SidebarView()
                    .frame(width: LoraLayout.sidebarWidth)
                    .padding(.top, LoraLayout.titlebarInset)

                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        TopBarView()
                        content(columnWidth: geometry.size.width)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
                }
            }
            .ignoresSafeArea(edges: .top)
            // The only zoom target on the left edge: the empty title-bar
            // strip above the brand, where the window controls live. It
            // deliberately stops short of the sidebar's rows.
            .overlay(alignment: .topLeading) {
                WindowZoomZone()
                    .frame(width: LoraLayout.sidebarWidth, height: LoraLayout.titlebarInset)
            }

            // Continuous sidebar edge: from the window's top edge all the way
            // down, so the strip and the sidebar read as one piece.
            HStack(spacing: 0) {
                Theme.hairline
                    .frame(width: 1)
                Spacer(minLength: 0)
            }
            .padding(.leading, LoraLayout.sidebarWidth - 1)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if dropTargeted {
                dropOverlay
                    .transition(.opacity)
                    .zIndex(4)
            }

            CaptureLayer()
            BoardManagerLayer()
            DetailLayer()
            ToastLayer()
        }
        .tint(Theme.red)
        .focusEffectDisabled()
        .dismissTextFocusOnClickOutside()
        .background(WindowConfigurator().frame(width: 0, height: 0))
        .background {
            if prewarming { DetailPrewarm() }
        }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted) { providers in
            DropReceiver.handle(providers: providers, store: store)
        }
        .task {
            if ResizeBench.isRequested() {
                await ResizeBench.run(store: store)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--bench") {
                DataLayerBench.run(store: store)
                NSApp.terminate(nil)
                return
            }
            store.startAgentServerIfNeeded()
            store.startBackgroundMaintenance()
            if let error = store.startupError {
                store.showToast(error, icon: "exclamationmark.triangle")
                store.startupError = nil
            }
            applyDemoModeIfNeeded()

            // Keep the warm-up for the launch window only, then drop it out of
            // the tree so it stops taking part in layout passes.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withTransaction(Transaction(animation: nil)) { prewarming = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flushPersistenceAndWait()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            store.flushPersistence()
        }
        .onExitCommand {
            if store.boardManagerPresented {
                withAnimation(.easeOut(duration: 0.16)) { store.boardManagerPresented = false }
            } else if store.selectedPin != nil {
                store.dismissDetail()
            } else if store.capturePresented {
                withAnimation(.easeOut(duration: 0.18)) { store.capturePresented = false }
            } else if store.isSelectingPins {
                store.endSelection()
            } else if !store.searchText.isEmpty {
                store.clearSearch()
            }
        }
        .animation(.easeOut(duration: 0.18), value: dropTargeted)
    }

    /// Hidden launch-argument hooks used for automated design verification:
    /// open Lora.app --args --show agent|detail|capture
    private func applyDemoModeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        var mode = ProcessInfo.processInfo.environment["LORA_SHOW"]
            ?? UserDefaults.standard.string(forKey: "lora.debugShow")
        if let index = arguments.firstIndex(of: "--show"), arguments.indices.contains(index + 1) {
            mode = arguments[index + 1]
        }
        guard let mode, mode != "gallery" else { return }
        switch mode {
        case "agent":
            store.select(section: .agent)
        case "settings":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows
                        .first { $0.canBecomeKey && $0.title.contains("Settings") }?
                        .makeKeyAndOrderFront(nil)
                }
            }
        case "capture":
            store.capturePresented = true
        case "boards":
            store.boardManagerPresented = true
        case "batch":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let ids = store.filteredPins.prefix(4).map(\.id)
                store.beginSelection()
                // Toggle on separate runloop turns so the debug state follows
                // the same path as real clicks.
                for (index, id) in ids.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(index) * 0.15) {
                        store.toggleSelection(id)
                    }
                }
            }
        case "detail":
            if let query = UserDefaults.standard.string(forKey: "lora.debugPin"),
               let pin = store.pins.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
                store.openDetail(pin)
            } else if let pin = store.filteredPins.first {
                store.openDetail(pin)
            }
        default:
            break
        }
    }

    @ViewBuilder
    private func content(columnWidth: CGFloat) -> some View {
        if store.section == .agent {
            AgentAccessView()
                .transition(.opacity)
        } else {
            LibraryView(columnWidth: columnWidth)
                .transition(.opacity)
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Theme.paper.opacity(0.62)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.red, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .padding(18)

            VStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 56, height: 56)
                        .shadow(color: Theme.red.opacity(0.28), radius: 16, y: 6)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(T("Drop to pin"))
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                Text(T("Screenshots, images, or a pile of references"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Presentation layers

/// Each overlay observes only the slice of state it needs, so opening a
/// detail or showing a toast does not re-evaluate the gallery.

private struct DetailLayer: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            if let pin = store.selectedPin {
                PinDetailOverlay(pin: pin)
                    .transition(.opacity.combined(with: .scale(scale: 0.975)))
                    .zIndex(7)
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.selectedPinID)
    }
}

private struct CaptureLayer: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            if store.capturePresented {
                CaptureSheet()
                    .transition(.opacity)
                    .zIndex(6)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.capturePresented)
    }
}

private struct BoardManagerLayer: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            if store.boardManagerPresented {
                BoardManagerSheet()
                    .transition(.opacity)
                    .zIndex(8)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.boardManagerPresented)
    }
}

private struct ToastLayer: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            if let toast = store.toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast)
                        .padding(.bottom, store.isSelectingPins ? 100 : 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .zIndex(9)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.toast?.id)
    }
}

/// Warms AppKit's scroll-view machinery once at launch so the first detail
/// open does not pay the NSScrollView creation cost on the critical frame.
private struct DetailPrewarm: View {
    var body: some View {
        ScrollView(.vertical) {
            Color.clear.frame(height: 600)
        }
        .frame(width: 240, height: 240)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
