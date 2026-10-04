import SwiftUI
import WebKit

/// The right-hand panel: the open entry as the site renders it.
struct PreviewPane: View {
    @Environment(SiteStore.self) private var store
    @Environment(PreviewServer.self) private var server

    var body: some View {
        Group {
            switch server.state {
            case .running(let base):
                if let path = store.previewPath {
                    WebView(url: base.appending(path: path), reloadToken: store.saveCount)
                } else {
                    ContentUnavailableView("No Preview", systemImage: "eye.slash",
                                           description: Text("This section has no page of its own."))
                }
            case .idle, .looking:
                ProgressView("Looking for the dev server…")
            case .starting:
                ProgressView("Starting astro dev…")
            case .off:
                ContentUnavailableView {
                    Label("Preview Is Off", systemImage: "eye")
                } description: {
                    Text("The site's dev server isn't running. It shows drafts with a Draft banner.")
                } actions: {
                    Button("Start Dev Server") { server.start() }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Preview Didn't Start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { server.start() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: store.siteURL) {
            if let site = store.siteURL { server.find(for: site) }
        }
    }
}

/// A WKWebView that loads a page and reloads it after each save.
struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        context.coordinator.loaded = (url, reloadToken)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let last = context.coordinator.loaded
        if last?.url != url {
            view.load(URLRequest(url: url))
        } else if last?.token != reloadToken {
            // Astro reloads on its own when content changes; this covers the
            // times its watcher is slower than the save.
            view.reload()
        }
        context.coordinator.loaded = (url, reloadToken)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded: (url: URL, token: Int)?
    }
}
