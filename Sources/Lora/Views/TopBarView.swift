import SwiftUI
import AppKit

struct TopBarView: View {
    @Environment(LibraryStore.self) private var store
    @FocusState private var searchFocused: Bool
    @State private var statusPulse = false
    @State private var statusHovering = false
    @State private var searchHovering = false
    @State private var clearHovering = false

    var body: some View {
        HStack(spacing: 14) {
            searchField
                .layoutPriority(1)

            // The only zoom target on the right: the empty stretch of the
            // toolbar between the search field and the status pill. Nothing
            // else in the toolbar opts into the gesture.
            WindowZoomZone()
                .frame(maxWidth: .infinity)
                .frame(height: LoraLayout.toolbarHeight)

            statusPill

            CircleActionButton(icon: "sparkles", size: 38) {
                store.copyAgentContext()
            }
            .help(T("Copy agent prompt"))

            CircleActionButton(icon: "plus", filled: true, size: 38) {
                store.capturePresented = true
            }
            .help(T("Capture a new pin"))
        }
        .padding(.horizontal, 30)
        // The content column lifts into the window's title-bar band, so the
        // search row sits beside the traffic lights instead of below them.
        .padding(.top, LoraLayout.contentTopPadding)
        .padding(.bottom, 8)
        .onReceive(NotificationCenter.default.publisher(for: .loraFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .loraResignTextFocus)) { _ in
            searchFocused = false
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { store.searchText },
            set: { newValue in
                store.updateSearchText(newValue)
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    searchFocused
                        ? Theme.ink
                        : (searchHovering ? Theme.inkSecondary : Theme.inkTertiary)
                )

            TextField(T("Search pins, tags, boards, colors…"), text: searchTextBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }

            if store.searchText.isEmpty {
                if !searchFocused {
                    Text("⌘F")
                        .font(Theme.mono(9.5, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(RoundedRectangle(cornerRadius: 5).fill(
                            searchHovering ? Theme.parchmentDeep.opacity(0.75) : Theme.paper.opacity(0.85)
                        ))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline, lineWidth: 1))
                        .transition(.opacity)
                }
            } else {
                Button {
                    store.clearSearch()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(clearHovering ? Theme.parchmentDeep : Theme.paper))
                }
                .buttonStyle(PointerPlainButtonStyle())
                .onHover { clearHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: clearHovering)
            }
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: 620)
        .frame(height: LoraLayout.toolbarHeight)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    searchFocused
                        ? Theme.paper
                        : (searchHovering ? Theme.parchmentDeep.opacity(0.85) : Theme.parchment)
                )
                .shadow(
                    color: .black.opacity(searchFocused ? 0.07 : (searchHovering ? 0.045 : 0)),
                    radius: searchFocused ? 10 : 6,
                    y: searchFocused ? 3 : 2
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(
                    searchFocused
                        ? Theme.ink.opacity(0.24)
                        : (searchHovering ? Theme.ink.opacity(0.14) : Color.clear),
                    lineWidth: searchFocused ? 1.3 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .onHover { searchHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: searchFocused)
        .animation(.easeOut(duration: 0.16), value: searchHovering)
    }

    private var statusPill: some View {
        Button {
            store.select(section: .agent)
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(dotColor.opacity(0.18))
                        .frame(width: 13, height: 13)
                        .scaleEffect(statusPulse && store.agentStatus.isRunning ? 1.45 : 1)
                        .opacity(statusPulse && store.agentStatus.isRunning ? 0 : 1)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(statusTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(verbatim: ":\(store.agentPort)")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Capsule().fill(statusHovering ? Theme.parchmentDeep : Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .focusable(false)
        .onHover { statusHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: statusHovering)
        .help(T("Open Agent access"))
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                statusPulse = true
            }
        }
    }

    private var dotColor: Color {
        switch store.agentStatus {
        case .running: return Theme.moss
        case .starting: return Theme.amber
        case .failed: return Theme.red
        case .stopped: return Theme.inkTertiary
        }
    }

    private var statusTitle: String {
        switch store.agentStatus {
        case .running: return T("API live")
        case .starting: return T("Starting")
        case .failed: return T("Offline")
        case .stopped: return T("API off")
        }
    }
}