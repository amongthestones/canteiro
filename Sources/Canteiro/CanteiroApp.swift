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

        // The open entry as the site renders it. Its own window, so it can sit
        // beside the editor or on another screen at any size.
        Window("Preview", id: "preview") {
            PreviewPane()
                .environment(store)
                .environment(preview)
                .frame(minWidth: 360, minHeight: 400)
                .navigationTitle("Preview")
                .onAppear { store.previewOpen = true }
                .onDisappear { store.previewOpen = false }
        }
        .defaultSize(width: 620, height: 820)
        .defaultPosition(.trailing)

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
        }
        .commands {
            SaveCommand()
            BodyModeCommand()
            CommandGroup(replacing: .newItem) {
                NewEntryButton(inMenu: true)
                    .environment(store)
                NewAsideButton()
                Divider()
                Button("Open Site…") { store.chooseSite() }
                    .keyboardShortcut("o")
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

/// View › Show Rich Text / Show Markdown (⌘R), as in iA Writer.
private struct BodyModeCommand: Commands {
    @AppStorage("bodyMode") private var bodyMode = BodyMode.markdown

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(bodyMode == .markdown ? "Show Rich Text" : "Show Markdown") {
                bodyMode = bodyMode == .markdown ? .rich : .markdown
            }
            .keyboardShortcut("r")
            Divider()
        }
    }
}
