import SwiftUI
import AppKit

struct AgentAccessView: View {
    @Environment(LibraryStore.self) private var store
    @State private var portField: String?
    @State private var copiedBlock: String?
    @State private var showsPanels = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                heroCard
                if showsPanels {
                    panels
                        .transition(.opacity)
                } else {
                    panelsSkeleton
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 22)
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .onAppear {
            if !showsPanels {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    showsPanels = true
                }
            }
        }
    }

    @ViewBuilder
    private var panels: some View {
        HStack(alignment: .top, spacing: 18) {
            quickstartCard
            promptCard
        }
        HStack(alignment: .top, spacing: 18) {
            endpointsCard
            localCard
        }
        .padding(.bottom, 48)
    }

    private var panelsSkeleton: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
                    .frame(height: 190)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
                    .frame(height: 190)
            }
            HStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
                    .frame(height: 250)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Theme.parchment.opacity(0.55))
                    .frame(height: 250)
            }
            Color.clear.frame(height: 48)
        }
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(T("Give your agent eyes."))
                    .font(.system(size: 35, weight: .bold))
                    .tracking(-1.35)
                    .foregroundStyle(Theme.ink)
                Text(T("Every pin is a queryable JSON record with a direct image stream. Agents can read the library — and add new images — over the same loopback API."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.45), radius: 5)
            Text(store.agentStatusLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(verbatim: ":\(store.agentPort)")
                .font(Theme.mono(9.5, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Theme.parchment))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0x1B1714), Color(hex: 0x2B2520)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Theme.red.opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 420, y: -150)

            Circle()
                .fill(Color(hex: 0x4569D4).opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: 700, y: 70)

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 7) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10, weight: .semibold))
                        Text(T("LOCALHOST · READ + WRITE"))
                            .font(Theme.mono(8.5, weight: .semibold))
                            .tracking(1.2)
                    }
                    .foregroundStyle(Color.white.opacity(0.55))

                    Text(T("Your library, readable\nby your coding agent."))
                        .font(.system(size: 27, weight: .bold))
                        .tracking(-0.9)
                        .foregroundStyle(Color.white)
                        .lineSpacing(2)

                    Text(T("Point Claude Code, Codex, or Cursor at the docs endpoint.\nIt gets structured metadata and exact image URLs — no exports, no screenshots of screenshots."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        CantaButton(title: T("Open API docs"), icon: "book", variant: .primary) {
                            store.openAgentDocs()
                        }
                        heroGhostButton
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 12)

                terminalPreview
                    .frame(width: 350)
            }
            .padding(26)
        }
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 32, y: 14)
    }

    private var heroGhostButton: some View {
        Button {
            store.copyText(store.agentBaseURL, message: T("Endpoint copied"), icon: "link")
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(T("Copy endpoint"))
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 17)
            .frame(height: 42)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: 0xEF6A5E)).frame(width: 7, height: 7)
                Circle().fill(Color(hex: 0xE9B44C)).frame(width: 7, height: 7)
                Circle().fill(Color(hex: 0x6FBF8A)).frame(width: 7, height: 7)
                Spacer()
                Text("agent — canta")
                    .font(Theme.mono(8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            VStack(alignment: .leading, spacing: 7) {
                terminalLine(prompt: "$", text: "curl -s localhost:\(store.agentPort)/api/v1/context")
                terminalLine(prompt: "→", text: "# Canta design context")
                terminalLine(prompt: " ", text: "\(store.pins.count) pins · \(store.boardSummaries.count) boards · \(store.allTags.count) tags", dim: true)
                if let feature = store.pins.first {
                    terminalLine(prompt: " ", text: "![\(feature.title)]", dim: true)
                    terminalLine(prompt: " ", text: "board: \(feature.board)", dim: true)
                    terminalLine(prompt: " ", text: "palette: \(feature.colors.joined(separator: " "))", dim: true)
                }
                HStack(spacing: 5) {
                    Text("$")
                        .font(Theme.mono(9.5, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 5, height: 11)
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func terminalLine(prompt: String, text: String, dim: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text(prompt)
                .font(Theme.mono(8.5, weight: .semibold))
                .foregroundStyle(prompt == "$" ? Theme.red : Color.white.opacity(0.35))
            Text(text)
                .font(Theme.mono(8.5, weight: .regular))
                .foregroundStyle(dim ? Color.white.opacity(0.42) : Color.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var quickstartCard: some View {
        AgentPanel(title: T("QUICKSTART"), icon: "bolt") {
            VStack(alignment: .leading, spacing: 11) {
                Text(T("Fetch the whole design context in one request."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
                codeBlock("curl -s \(store.agentBaseURL)/api/v1/context", id: "quickstart")
                HStack(spacing: 7) {
                    SmallPillButton(title: T("Copy command"), icon: "doc.on.doc") {
                        store.copyText("curl -s \(store.agentBaseURL)/api/v1/context", message: T("Command copied"), icon: "terminal")
                    }
                    SmallPillButton(title: T("Open context"), icon: "arrow.up.right") {
                        store.openAgentContext()
                    }
                }

                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 1)

                Text(T("Or let your agent add an image:"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
                codeBlock(uploadCommand, id: "upload")
                HStack(spacing: 7) {
                    SmallPillButton(title: T("Copy upload command"), icon: "doc.on.doc") {
                        store.copyText(uploadCommand, message: T("Command copied"), icon: "terminal")
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 1)
                    Text(T("Prefix the product name and nest with “/” — board=Linear/Settings files the pin under Linear in the sidebar."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var uploadCommand: String {
        "curl -X POST \"\(store.agentBaseURL)/api/v1/pins?title=Settings&board=Linear%2FSettings\" \\\n  -H \"Content-Type: image/png\" \\\n  --data-binary @screenshot.png"
    }

    private var promptCard: some View {
        AgentPanel(title: T("AGENT PROMPT"), icon: "sparkles") {
            VStack(alignment: .leading, spacing: 11) {
                Text(T("Paste this into your coding agent to establish the reference loop."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkTertiary)
                codeBlock(store.agentBrief, id: "prompt", lineLimit: 7)
                HStack(spacing: 7) {
                    SmallPillButton(title: T("Copy prompt"), icon: "doc.on.doc") {
                        store.copyText(store.agentBrief, message: T("Prompt copied"), icon: "sparkles")
                    }
                    SmallPillButton(title: T("Open docs"), icon: "book") {
                        store.openAgentDocs()
                    }
                }
            }
        }
    }

    private var endpointsCard: some View {
        AgentPanel(title: T("API SURFACE"), icon: "point.3.connected.trianglepath.dotted") {
            VStack(spacing: 0) {
                endpointRow("POST", "/api/v1/pins", T("Add an image from an agent"))
                endpointRow("PATCH", "/api/v1/pins/{id}", store.allowsAgentMetadataEdits ? T("Update pin metadata") : T("Metadata edits are off"))
                endpointRow("GET", "/api/v1/library", T("Everything in one payload"))
                endpointRow("GET", "/api/v1/pins", T("Filter by q, tag, board, favorite"))
                endpointRow("GET", "/api/v1/pins/{id}", T("A single enriched pin"))
                endpointRow("GET", "/api/v1/pins/{id}/image", T("Original or thumbnail stream"))
                endpointRow("GET", "/api/v1/context", T("Markdown design context"))
                endpointRow("GET", "/docs", T("Human + agent documentation"))
            }
        }
    }

    private var localCard: some View {
        AgentPanel(title: T("THE SERVER"), icon: "server.rack") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(store.agentStatusLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("127.0.0.1")
                        .font(Theme.mono(9.5, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                }

                if let detail = store.agentStatusDetail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text(T("PORT"))
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkTertiary)
                    TextField("4242", text: Binding(
                        get: { portField ?? "\(store.agentPort)" },
                        set: { portField = $0 }
                    ))
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(width: 70, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.parchment))
                    Button(T("Apply")) {
                        let text = portField ?? String(store.agentPort)
                        if let value = UInt16(text), value >= 1024 {
                            store.setAgentPort(value)
                            portField = nil
                            store.showToast(TF("Agent API restarted on :%ld", Int(value)), icon: "arrow.triangle.2.circlepath")
                        } else {
                            store.showToast(T("Port must be 1024–65535"), icon: "exclamationmark.triangle")
                            portField = nil
                        }
                    }
                    .buttonStyle(PointerPlainButtonStyle())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.red)
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

                HStack(spacing: 7) {
                    Button(T("Restart")) { store.restartAgentServer() }
                        .buttonStyle(PointerPlainButtonStyle())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("·").foregroundStyle(Theme.inkTertiary)
                    Button(T("Data folder")) { store.openDataFolder() }
                        .buttonStyle(PointerPlainButtonStyle())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("·").foregroundStyle(Theme.inkTertiary)
                    Button(T("llms.txt")) { store.openAgentManifest() }
                        .buttonStyle(PointerPlainButtonStyle())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Text(T("Bound to loopback only. Images and metadata never leave this Mac."))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineSpacing(1.5)
            }
        }
    }

    private func endpointRow(_ method: String, _ path: String, _ description: String) -> some View {
        HStack(spacing: 9) {
            Text(method)
                .font(Theme.mono(7.5, weight: .bold))
                .foregroundStyle(method == "POST" ? Theme.red : Theme.moss)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(method == "POST" ? Theme.redWash : Theme.mossWash))
            Text(path)
                .font(Theme.mono(9.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer()
            Text(description)
                .font(.system(size: 9))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if path != "/docs" {
                Rectangle().fill(Theme.hairline.opacity(0.75)).frame(height: 1)
            }
        }
    }

    private func codeBlock(_ text: String, id: String, lineLimit: Int = 3) -> some View {
        Button {
            store.copyText(text, message: T("Copied"), icon: "doc.on.doc")
            copiedBlock = id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(Theme.mono(9.5, weight: .bold))
                    .foregroundStyle(Theme.red)
                Text(text)
                    .font(Theme.mono(9.5, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(lineLimit)
                Spacer(minLength: 4)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.parchment))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PointerPlainButtonStyle())
        .help(T("Copy"))
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

struct AgentPanel<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.35)
                    .foregroundStyle(Theme.inkTertiary)
                Spacer()
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Theme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}