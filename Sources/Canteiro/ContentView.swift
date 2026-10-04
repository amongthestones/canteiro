import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(SiteStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showPublish = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) { UploadBar() }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPublish = true
                        } label: {
                            Label("Publish", systemImage: "arrow.up.circle")
                        }
                        .badge(store.contentChanges.count)
                        .help("Commit and push your changes")
                        .disabled(store.changes.isEmpty)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        // The preview has its own window, kept out of this
                        // one's layout: as a side panel it squeezed the
                        // sidebar, and as an .inspector it crashed the app.
                        Toggle(isOn: Binding(
                            get: { store.previewOpen },
                            set: { $0 ? openWindow(id: "preview") : dismissWindow(id: "preview") }
                        )) {
                            Label("Preview", systemImage: "eye")
                        }
                        .help("Show the page as the site renders it, drafts included, in its own window")
                        .keyboardShortcut("p", modifiers: [.command, .option])
                        .disabled(store.phase != .ready)
                    }
                }
        }
        .navigationTitle(store.siteName)
        .sheet(isPresented: $showPublish) { PublishSheet() }
        .onReceive(NotificationCenter.default.publisher(for: AsideHotKey.pressed)) { _ in
            NSApp.activate()
            openWindow(id: "aside")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Catch commits and edits made outside the app.
            store.refreshChanges()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.phase {
        case .noSite:
            ContentUnavailableView {
                Label("No Site Open", systemImage: "folder")
            } description: {
                Text("Open a site folder that has a keystatic.config.ts.")
            } actions: {
                Button("Open Site…") { store.chooseSite() }
            }
        case .loading:
            ProgressView("Reading \(store.siteName)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Open the Site", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).textSelection(.enabled)
            } actions: {
                Button("Open Site…") { store.chooseSite() }
                Button("Try Again") { store.reload() }
            }
        case .ready:
            if let key = store.selectedItem, let item = store.schema?.item(key) {
                switch item.kind {
                case .collection: CollectionView(item: item).id(item.key)
                case .singleton: SingletonView(item: item).id(item.key)
                }
            } else {
                ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left")
            }
        }
    }
}

struct SidebarView: View {
    @Environment(SiteStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedItem) {
            if let schema = store.schema {
                ForEach(schema.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { item in
                            Label(item.label, systemImage: Self.icon(for: item))
                                .badge(store.count(item) ?? 0)
                                .tag(item.key)
                        }
                    }
                }
            }
            if !store.problems.isEmpty {
                Section("Problems") {
                    ForEach(store.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    /// An icon from what the item holds, so a new collection gets a fair
    /// one without the app knowing its name.
    static func icon(for item: SchemaItem) -> String {
        let types = Set(item.fields.map(\.type))
        if item.kind == .singleton {
            if types == ["array"] { return "list.bullet.rectangle" }
            return "slider.horizontal.3"
        }
        if item.fields.contains(where: { $0.key.lowercased().contains("audio") }) { return "mic" }
        if item.format.contentField == nil {
            return item.isStream ? "text.bubble" : "square.stack"
        }
        if item.path.hasSuffix("**") { return "books.vertical" }
        return item.dateField != nil ? "doc.text" : "doc"
    }
}
