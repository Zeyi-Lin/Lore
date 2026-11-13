import SwiftUI

struct TopBarView: View {
    @EnvironmentObject private var store: LibraryStore
    @FocusState private var searchFocused: Bool
    @State private var statusPulse = false

    var body: some View {
        HStack(spacing: 14) {
            searchField
                .layoutPriority(1)

            Spacer(minLength: 0)

            statusPill

            CircleActionButton(icon: "sparkles", size: 38) {
                store.copyAgentContext()
            }
            .help(T("Copy filtered pins as agent context"))

            CircleActionButton(icon: "plus", filled: true, size: 38) {
                store.capturePresented = true
            }
            .help(T("Capture a new pin"))
        }
        .padding(.horizontal, 30)
        .padding(.top, 19)
        .padding(.bottom, 8)
        .onReceive(NotificationCenter.default.publisher(for: .cantaFocusSearch)) { _ in
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.ink : Theme.inkTertiary)

            TextField(T("Search pins, tags, boards…"), text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }

            if store.searchText.isEmpty {
                Text("⌘F")
                    .font(Theme.mono(9.5, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 7)
                    .frame(height: 21)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.paper.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline, lineWidth: 1))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { store.searchText = "" }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.paper))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: 620)
        .frame(height: 41)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Theme.parchment)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(searchFocused ? Theme.ink.opacity(0.16) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.16), value: searchFocused)
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
            .background(Capsule().fill(Theme.parchment))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
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