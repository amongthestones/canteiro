import SwiftUI

struct ContentView: View {
    @Environment(SiteStore.self) private var store
    @AppStorage("showPreview") private var showPreview = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .inspector(isPresented: $showPreview) {
                    PreviewPane()
                        .inspectorColumnWidth(min: 360, ideal: 560, max: 1000)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(isOn: $showPreview) {
                            Label("Preview", systemImage: "eye")
                        }
                        .help("Show the page as the site renders it, drafts included")
                        .disabled(store.phase != .ready)
                    }
                }
        }
        .navigationTitle(store.siteName)
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
