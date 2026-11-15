import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @ObservedObject private var language = LanguageManager.shared
    @State private var updates = UpdateController.shared
    @State private var portField = ""
    @State private var boardMenuHovering = false

    var body: some View {
        ScrollViewReader { proxy in
            settingsContent(proxy)
        }
    }

    private func settingsContent(_ proxy: ScrollViewProxy) -> some View {
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
                        .pointerCursor()
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
                            .pointerCursor()
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
                            .buttonStyle(PointerPlainButtonStyle())
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            Spacer()
                            Button(T("Restart")) { store.restartAgentServer() }
                                .buttonStyle(PointerPlainButtonStyle())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(T("Allow metadata edits"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(T("Agents can update titles, notes, boards, tags, and favorites through PATCH /api/v1/pins/{id}."))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 12)
                            Toggle("", isOn: Binding(
                                get: { store.allowsAgentMetadataEdits },
                                set: { store.setAgentMetadataEdits($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(Theme.red)
                            .pointerCursor()
                        }

                        HStack(spacing: 7) {
                            SmallPillButton(title: T("Open docs"), icon: "book") { store.openAgentDocs() }
                            SmallPillButton(title: T("Copy endpoint"), icon: "doc.on.doc") {
                                store.copyText(store.agentBaseURL, message: T("Endpoint copied"), icon: "link")
                            }
                            Spacer()
                        }

                        Text(T("Serves and accepts images on 127.0.0.1 only. No authentication required for local agents."))
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
                                .background(Capsule().fill(boardMenuHovering ? Theme.parchmentDeep : Theme.parchment))
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .focusable(false)
                            .fixedSize()
                            .pointerCursor()
                            .onHover { boardMenuHovering = $0 }
                            .animation(.easeOut(duration: 0.14), value: boardMenuHovering)
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
                                .buttonStyle(PointerPlainButtonStyle())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }

                settingsGroup(title: T("ABOUT"), icon: "info.circle") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            LoreMark(size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                // Read from the bundle (stamped by build-app.sh from
                                // Version.swift); never hard-code the number here.
                                Text(verbatim: LoreVersion.display)
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

                        Hairline()

                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: updates.statusIcon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(updateStatusColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(updates.statusTitle)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                if let detail = updates.statusDetail {
                                    Text(detail)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Theme.inkTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 12)
                            updateControls
                        }
                    }
                }
                .id("settings.about")
            }
            .padding(26)
            .frame(width: 600)
        }
        .background(Theme.parchment)
        .onAppear {
            portField = "\(store.agentPort)"
            scrollToAboutIfRequested(proxy)
            if updates.revealAboutOnAppear {
                updates.revealAboutOnAppear = false
                scrollToAbout(proxy, delay: 0.35)
            }
        }
        .onChange(of: updates.phase) { _, phase in
            if case .available = phase, updates.revealAboutOnAppear {
                updates.revealAboutOnAppear = false
                scrollToAbout(proxy, delay: 0.35)
            }
        }
    }

    /// Hidden design-verification hook: `Lore --show settings --settings-section about`
    /// opens Settings already scrolled to the version/update card, so it can be
    /// captured without synthetic scroll events.
    private func scrollToAboutIfRequested(_ proxy: ScrollViewProxy) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--settings-section"),
              arguments.indices.contains(index + 1),
              arguments[index + 1] == "about" else { return }
        scrollToAbout(proxy, delay: 0.6)
    }

    private func scrollToAbout(_ proxy: ScrollViewProxy, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo("settings.about", anchor: .center)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(T("Settings"))
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(Theme.ink)
                Text(T("Keep Lore quiet, local, and ready for your agent."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var updateControls: some View {
        switch updates.phase {
        case .checking, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 92)
        case .downloading(_, let progress):
            HStack(spacing: 7) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .labelsHidden()
                    .frame(width: 64)
                Text("\(Int(progress * 100))%")
                    .font(Theme.mono(9, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 34, alignment: .trailing)
            }
        case .available(let release):
            HStack(spacing: 8) {
                if release.installerAsset != nil {
                    UpdateActionButton(title: T("Install Update"), icon: "arrow.down.circle.fill", filled: true) {
                        Task { await updates.installAvailableUpdate() }
                    }
                } else {
                    UpdateActionButton(title: T("Open Release Page"), icon: "safari", filled: true) {
                        updates.openReleasePage()
                    }
                }
                UpdateActionButton(title: T("Release Notes"), icon: "doc.text") {
                    updates.openReleasePage()
                }
            }
        case .failed:
            HStack(spacing: 8) {
                UpdateActionButton(title: T("Try Again"), icon: "arrow.clockwise") {
                    Task { await updates.checkForUpdates() }
                }
                UpdateActionButton(title: T("Release Notes"), icon: "doc.text") {
                    updates.openReleasePage()
                }
            }
        case .idle, .upToDate:
            UpdateActionButton(title: T("Check for Updates"), icon: "arrow.triangle.2.circlepath") {
                Task { await updates.checkForUpdates() }
            }
        }
    }

    private var updateStatusColor: Color {
        switch updates.phase {
        case .upToDate: return Theme.moss
        case .available: return Theme.red
        case .failed: return Theme.amber
        case .checking, .downloading, .installing: return Theme.inkSecondary
        case .idle: return Theme.inkTertiary
        }
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
/// Compact capsule used by the update row: a filled red action for "install",
/// a quiet tinted one for "check" and "release notes".
private struct UpdateActionButton: View {
    let title: String
    let icon: String
    var filled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(filled ? Color.white : Theme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(filled ? Color.clear : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PointerPlainButtonStyle())
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var background: Color {
        if filled {
            return hovering ? Theme.redDeep : Theme.red
        }
        return hovering ? Theme.parchmentDeep : Theme.parchment
    }
}
