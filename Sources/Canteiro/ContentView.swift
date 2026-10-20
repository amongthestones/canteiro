import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(SiteStore.self) private var store
    @Environment(DraftInbox.self) private var inbox
    @Environment(PreviewServer.self) private var server
    @Environment(\.openWindow) private var openWindow
    @State private var showPublish = false
    @AppStorage("bodyMode") private var bodyMode = BodyMode.markdown

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
                        // Same text either way; Rich hides the marks.
                        Picker("View", selection: $bodyMode) {
                            Text("Markdown").tag(BodyMode.markdown)
                            Text("Rich").tag(BodyMode.rich)
                        }
                        .pickerStyle(.segmented)
                        .help("Markdown shows the marks, Rich hides them (⌘R)")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        OpenInBrowserButton()
                    }
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
                }
        }
        .navigationTitle(store.siteName)
        .sheet(isPresented: $showPublish) { PublishSheet() }
        .sheet(item: $store.newEntryItem) { NewEntrySheet(item: $0) }
        .sheet(isPresented: $store.arrangingSections) { ArrangeSectionsSheet() }
        .onReceive(NotificationCenter.default.publisher(for: AsideHotKey.pressed)) { _ in
            NSApp.activate()
            openWindow(id: "aside")
        }
        .onChange(of: store.siteURL) { server.siteChanged(store.siteURL) }
        .onChange(of: store.config, initial: true) { inbox.configure(store.config, site: store.siteURL) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Catch commits and edits made outside the app.
            store.refreshChanges()
            inbox.refresh()
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
            if store.selectedItem == DraftInbox.sidebarKey {
                InboxView()
            } else if let key = store.selectedItem, let item = store.schema?.item(key) {
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
    @Environment(DraftInbox.self) private var inbox

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selectedItem) {
            ForEach(Self.sections(store, inbox), id: \.self) { name in
                if name == DraftInbox.sidebarKey {
                    if let folder = inbox.folder {
                        Section {
                            Label(folder.lastPathComponent, systemImage: "tray")
                                .badge(inbox.drafts.count)
                                .tag(DraftInbox.sidebarKey)
                        } header: {
                            header("Inbox")
                        }
                    }
                } else if let group = store.schema?.groups.first(where: { $0.name == name }) {
                    Section {
                        ForEach(group.items) { item in
                            Label(item.label, systemImage: Self.icon(for: item))
                                .badge(store.count(item) ?? 0)
                                .tag(item.key)
                        }
                    } header: {
                        header(group.name)
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

    private func header(_ title: String) -> some View {
        Text(title)
            .contextMenu {
                Button("Arrange Sections…") { store.arrangingSections = true }
            }
    }

    /// The sections in the config's order: its groups, then the inbox.
    static func defaultSections(_ store: SiteStore, _ inbox: DraftInbox) -> [String] {
        var names = store.schema?.groups.map(\.name) ?? []
        if inbox.folder != nil, let key = inbox.collection, store.schema?.item(key) != nil {
            names.append(DraftInbox.sidebarKey)
        }
        return names
    }

    /// The sections in this site's order, if they've been arranged.
    static func sections(_ store: SiteStore, _ inbox: DraftInbox) -> [String] {
        SiteStore.arranged(defaultSections(store, inbox), by: store.sectionOrder)
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


/// View › Arrange Sections…: the sidebar's sections in a list to drag into
/// order. Saved per site on this Mac.
struct ArrangeSectionsSheet: View {
    @Environment(SiteStore.self) private var store
    @Environment(DraftInbox.self) private var inbox
    @Environment(\.dismiss) private var dismiss
    @State private var order: [String] = []

    var body: some View {
        let standard = SidebarView.defaultSections(store, inbox)
        VStack(spacing: 0) {
            Form {
                Section {
                    List {
                        ForEach(order, id: \.self) { name in
                            Label(title(name), systemImage: "line.3.horizontal")
                        }
                        .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(height: CGFloat(order.count) * 28 + 12)
                } header: {
                    Text("Arrange Sections")
                } footer: {
                    Text("Drag sections into the order the sidebar shows them.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Button("Restore Default Order") { order = standard }
                    .disabled(order == standard)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    store.arrangeSections(order == standard ? [] : order)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { order = SidebarView.sections(store, inbox) }
    }

    private func title(_ name: String) -> String {
        name == DraftInbox.sidebarKey ? "Inbox" : name
    }
}

/// Opens what's selected in the browser, from the site's dev server, which
/// it starts if need be. Edits are saved first, so the page has them.
struct OpenInBrowserButton: View {
    @Environment(SiteStore.self) private var store
    @Environment(PreviewServer.self) private var server
    @FocusedValue(\.saveEntry) private var saveEntry
    var inMenu = false

    var body: some View {
        Button {
            guard let path = store.previewPath, let site = store.siteURL else { return }
            saveEntry?()
            Task {
                do {
                    try await server.open(path, site: site)
                } catch {
                    store.lastError = error.localizedDescription
                }
            }
        } label: {
            if inMenu {
                Text("Open in Browser")
            } else if server.isStarting {
                ProgressView().controlSize(.small)
            } else {
                Label("Open in Browser", systemImage: "safari")
            }
        }
        .keyboardShortcut(inMenu ? KeyboardShortcut("p", modifiers: [.command, .option]) : nil)
        .help(server.state == .starting ? "Starting astro dev…" : "Open this page from the site's dev server, drafts included (⌥⌘P)")
        .disabled(store.previewPath == nil || server.isStarting)
    }
}
