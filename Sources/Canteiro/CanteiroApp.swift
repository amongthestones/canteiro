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
