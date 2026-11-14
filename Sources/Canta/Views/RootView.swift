import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView()

                VStack(spacing: 0) {
                    TopBarView()
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if dropTargeted {
                dropOverlay
                    .transition(.opacity)
                    .zIndex(4)
            }

            if store.capturePresented {
                CaptureSheet()
                    .environmentObject(store)
                    .zIndex(6)
            }

            if let pin = store.selectedPin {
                PinDetailOverlay(pin: pin)
                    .environmentObject(store)
                    .zIndex(7)
            }

            if let toast = store.toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast)
                        .padding(.bottom, store.isSelectingPins ? 100 : 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(9)
            }
        }
        .tint(Theme.red)
        .focusEffectDisabled()
        .background(WindowConfigurator().frame(width: 0, height: 0))
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted) { providers in
            DropReceiver.handle(providers: providers, store: store)
        }
        .task {
            store.startAgentServerIfNeeded()
            if let error = store.startupError {
                store.showToast(error, icon: "exclamationmark.triangle")
                store.startupError = nil
            }
            applyDemoModeIfNeeded()
        }
        .onExitCommand {
            if store.selectedPin != nil {
                store.dismissDetail()
            } else if store.capturePresented {
                withAnimation(.easeOut(duration: 0.18)) { store.capturePresented = false }
            } else if store.isSelectingPins {
                store.endSelection()
            } else if !store.searchText.isEmpty {
                store.searchText = ""
            }
        }
        .animation(.easeOut(duration: 0.18), value: dropTargeted)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: store.capturePresented)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: store.selectedPinID)
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
                let ids = Set(store.filteredPins.prefix(4).map(\.id))
                store.beginSelection()
                store.selectedPinIDs = ids
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