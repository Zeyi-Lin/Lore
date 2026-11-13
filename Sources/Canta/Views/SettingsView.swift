import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var language = LanguageManager.shared
    @State private var portField = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                settingsGroup(title: T("LANGUAGE"), icon: "globe") {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(T("App language"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(T("Follows your macOS language unless changed."))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Picker("", selection: Binding(
                            get: { language.selection },
                            set: { language.select($0) }
                        )) {
                            ForEach(AppLanguage.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                }

                settingsGroup(title: T("AGENT API"), icon: "sparkles") {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 7, height: 7)
                            Text(store.agentStatusLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { store.agentAPIEnabled },
                                set: { store.setAgentEnabled($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(Theme.red)
                        }

                        HStack(spacing: 8) {
                            Text(T("PORT"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.inkSecondary)
                            TextField("4242", text: $portField)
                                .textFieldStyle(.plain)
                                .font(Theme.mono(11, weight: .medium))
                                .padding(.horizontal, 8)
                                .frame(width: 74, height: 27)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.parchment))
                            Button(T("Apply")) {
                                if let value = UInt16(portField), value >= 1024 {
                                    store.setAgentPort(value)
                                    store.showToast(TF("Agent API restarted on :%ld", Int(value)), icon: "arrow.triangle.2.circlepath")
                                } else {
                                    portField = "\(store.agentPort)"
                                    store.showToast(T("Port must be 1024–65535"), icon: "exclamationmark.triangle")
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            Spacer()
                            Button(T("Restart")) { store.restartAgentServer() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        HStack(spacing: 7) {
                            SmallPillButton(title: T("Open docs"), icon: "book") { store.openAgentDocs() }
                            SmallPillButton(title: T("Copy endpoint"), icon: "doc.on.doc") {
                                store.copyText(store.agentBaseURL, message: T("Endpoint copied"), icon: "link")
                            }
                            Spacer()
                        }

                        Text(T("Serves the library on 127.0.0.1 only. Read-only, no authentication required for local agents."))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.inkTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                settingsGroup(title: T("CAPTURE"), icon: "pin") {
                    VStack(spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(T("Default board"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(T("New pins land here unless you pick another board."))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            Spacer()
                            Menu {
                                ForEach(store.allBoardNames, id: \.self) { name in
                                    Button {
                                        store.defaultBoard = name
                                    } label: {
                                        if store.defaultBoard == name {
                                            Label(localizedBoard(name), systemImage: "checkmark")
                                        } else {
                                            Text(localizedBoard(name))
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.boardColor(store.defaultBoard)).frame(width: 6, height: 6)
                                    Text(localizedBoard(store.defaultBoard))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.inkSecondary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(Capsule().fill(Theme.parchment))
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .focusable(false)
                            .fixedSize()
                        }

                        Hairline()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(T("Library location"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(store.dataFolderPath)
                                    .font(Theme.mono(8.5, weight: .regular))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(T("Reveal")) { store.openDataFolder() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }

                settingsGroup(title: T("ABOUT"), icon: "info.circle") {
                    HStack(spacing: 12) {
                        CantaMark(size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(T("Canta 1.0"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(T("A quiet visual library for humans and their agents."))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer()
                        Text(T("Made for macOS"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .padding(26)
            .frame(width: 600)
        }
        .background(Theme.parchment)
        .onAppear { portField = "\(store.agentPort)" }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(T("Settings"))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(Theme.ink)
                Text(T("Keep Canta quiet, local, and ready for your agent."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private func settingsGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(Theme.inkTertiary)
            }
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
    }

    private var statusColor: Color {
        switch store.agentStatus {
        case .running: return Theme.moss
        case .starting: return Theme.amber
        case .failed: return Theme.red
        case .stopped: return Theme.inkTertiary
        }
    }
}