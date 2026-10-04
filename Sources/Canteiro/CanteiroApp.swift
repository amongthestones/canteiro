import AppKit
import SwiftUI

@main
struct CanteiroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SiteStore()
    @State private var preview = PreviewServer()

    var body: some Scene {
        Window("Canteiro", id: "main") {
            ContentView()
                .environment(store)
                .environment(preview)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    preview.stop()
                }
                .frame(minWidth: 960, minHeight: 600)
                .task { await store.restore() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            SaveCommand()
            CommandGroup(replacing: .newItem) {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under `swift run` there's no bundle to say this is a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
