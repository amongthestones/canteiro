import AppKit
import SwiftUI

@main
struct CanteiroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SiteStore()
    @State private var preview = PreviewServer()
    @State private var inbox = DraftInbox()

    var body: some Scene {
        Window("Canteiro", id: "main") {
            ContentView()
                .environment(store)
                .environment(preview)
                .environment(inbox)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    preview.stop()
                }
                .frame(minWidth: 960, minHeight: 600)
                .task { await store.restore() }
        }
        .defaultSize(width: 1280, height: 820)

        Window("New Aside", id: "aside") {
            QuickAsideView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(store)
                .environment(inbox)
        }
        .commands {
            SaveCommand()
            BodyModeCommand(store: store, server: preview)
            CommandGroup(after: .sidebar) {
                Button("Arrange Sections…") { store.arrangingSections = true }
                    .disabled(store.schema == nil)
            }
            FormatCommands()
            CommandGroup(replacing: .newItem) {
                NewEntryButton(inMenu: true)
                    .environment(store)
                NewAsideButton()
                Divider()
                Button("Open Site…") { store.chooseSite() }
                    .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(Array(store.recentSites.enumerated()), id: \.element) { index, url in
                        let button = Button(store.menuName(url)) { store.openRecent(url) }
                        if index < 9 {
                            button.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                        } else {
                            button
                        }
                    }
                    Divider()
                    Button("Clear Menu") { store.clearRecents() }
                        .disabled(store.recentSites.count <= 1)
                }
                Button("Reload Site") { store.reload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.siteURL == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let asideHotKey = AsideHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        asideHotKey.register()
        // Under `swift run` there's no bundle to say this is a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// File › New Aside. A view, so it can open the window.
private struct NewAsideButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Aside") { openWindow(id: "aside") }
            .keyboardShortcut("a", modifiers: [.command, .shift])
    }
}

/// View › Show Rich Text / Show Markdown (⌘R), as in iA Writer, and Open
/// in Browser (⌥⌘P).
private struct BodyModeCommand: Commands {
    let store: SiteStore
    let server: PreviewServer
    @AppStorage("bodyMode") private var bodyMode = BodyMode.markdown

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(bodyMode == .rich ? "Show Markdown" : "Show Rich Text") {
                bodyMode = bodyMode == .rich ? .markdown : .rich
            }
            .keyboardShortcut("r")
            OpenInBrowserButton(inMenu: true)
                .environment(store)
                .environment(server)
            Divider()
        }
    }
}
