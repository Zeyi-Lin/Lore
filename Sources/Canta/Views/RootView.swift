import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            GeometryReader { geometry in
                let sidebarWidth: CGFloat = 246
                let contentWidth = max(geometry.size.width - sidebarWidth, 0)
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: sidebarWidth)

                    VStack(spacing: 0) {
                        TopBarView()
                        content
                    }
                    .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
                    .clipped()
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .environment(\.cantaContentWidth, contentWidth)
            }

            if dropTargeted {
                dropOverlay
                    .transition(.opacity)
                    .zIndex(4)
            }

            CaptureLayer()
            DetailLayer()
            ToastLayer()
        }
        .tint(Theme.red)
        .focusEffectDisabled()
        .background(WindowConfigurator().frame(width: 0, height: 0))
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted) { providers in
            DropReceiver.handle(providers: providers, store: store)
        }
        .task {
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flushPersistenceAndWait()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            store.flushPersistence()
        }
        .onExitCommand {
            if store.selectedPin != nil {
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
    /// open Canta.app --args --show agent|detail|capture
    private func applyDemoModeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        var mode = ProcessInfo.processInfo.environment["CANTA_SHOW"]
            ?? UserDefaults.standard.string(forKey: "canta.debugShow")
        if let index = arguments.firstIndex(of: "--show"), arguments.indices.contains(index + 1) {
            mode = arguments[index + 1]
        }
        guard let mode, mode != "gallery" else { return }
        switch mode {
        case "agent":
            store.select(section: .agent)
        case "capture":
            store.capturePresented = true
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
            if let query = UserDefaults.standard.string(forKey: "canta.debugPin"),
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
    private var content: some View {
        if store.section == .agent {
            AgentAccessView()
                .transition(.opacity)
        } else {
            LibraryView()
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
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: store.selectedPinID)
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
