import SwiftUI
import AppKit

@main
struct LoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: LibraryStore
    @StateObject private var language: LanguageManager

    init() {
        // The rename must not cost a single pin: move the old library and
        // carry the persisted settings before anything reads them.
        LoraPaths.migrateLegacyLibraryIfNeeded()
        LoraPaths.migrateLegacyPreferencesIfNeeded()
        _store = State(initialValue: LibraryStore())
        _language = StateObject(wrappedValue: LanguageManager.shared)
    }

    var body: some Scene {
        WindowGroup("Lora") {
            RootView()
                .environment(store)
                .id(language.resolved)
                .environment(\.locale, language.resolved.locale)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands { appCommands }

        Settings {
            SettingsView()
                .environment(store)
                .id(language.resolved)
                .environment(\.locale, language.resolved.locale)
                .preferredColorScheme(.light)
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(T("New Pin")) {
                store.capturePresented = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(T("Import Images…")) {
                ImportPanel.present(store: store)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button(T("Paste Image")) {
                Task { await store.pasteFromClipboard() }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(T("Capture Screenshot")) {
                Task { await store.captureScreenshot() }
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button(T("Search Pins")) {
                NotificationCenter.default.post(name: .loraFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu(T("Library")) {
            Button(T("All Pins")) { store.select(section: .all) }
                .keyboardShortcut("1", modifiers: .command)
            Button(T("Favorites")) { store.select(section: .favorites) }
                .keyboardShortcut("2", modifiers: .command)
            Button(T("Recent")) { store.select(section: .recent) }
                .keyboardShortcut("3", modifiers: .command)
            Button(T("Agent Access")) { store.select(section: .agent) }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            Button(T("Manage boards…")) { store.boardManagerPresented = true }
            Divider()
            Button(store.isSelectingPins ? T("Exit selection") : T("Select pins")) {
                if store.isSelectingPins {
                    store.endSelection()
                } else {
                    store.beginSelection()
                }
            }
            .keyboardShortcut("b", modifiers: .command)
            Divider()
            Button(T("Copy agent prompt")) { store.copyAgentContext() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(T("Open Data Folder")) { store.openDataFolder() }
        }

        CommandGroup(replacing: .help) {
            Button(T("Lora Agent API Documentation")) {
                store.openAgentDocs()
            }
            Button(T("Open llms.txt")) {
                store.openAgentManifest()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}