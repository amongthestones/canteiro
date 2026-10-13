import Foundation
import Observation

/// The site's `astro dev` server, which renders drafts with a Draft banner.
/// Uses one that's already running for this site (a terminal's, another tool's), or
/// starts its own and stops it when Canteiro quits.
@MainActor
@Observable
final class PreviewServer {
    enum State: Equatable {
        case idle
        case looking
        case off
        case starting
        case running(URL)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var process: Process?
    private var site: URL?

    var baseURL: URL? {
        if case .running(let url) = state { return url }
        return nil
    }

    /// Looks for a dev server already serving this site.
    func find(for site: URL) {
        guard site != self.site || state == .idle || state == .off else { return }
        self.site = site
        state = .looking
        Task {
            let port = await Task.detached { DevServerScan.port(servingSite: site) }.value
            guard self.site == site else { return }
            state = port.map { .running(URL(string: "http://localhost:\($0)")!) } ?? .off
        }
    }

    func start() {
        guard let site, process == nil else { return }
        state = .starting
        Task {
            guard let node = await Task.detached(operation: { NodeLocator.path() }).value else {
                state = .failed(SchemaLoader.Failure.noNode.localizedDescription)
                return
            }
            let port = await Task.detached { DevServerScan.freePort() }.value
            let task = Process()
            task.executableURL = URL(fileURLWithPath: node)
            task.arguments = [site.appending(path: "node_modules/astro/astro.js").path, "dev", "--port", String(port)]
            task.currentDirectoryURL = site
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
            process = task
            let url = URL(string: "http://localhost:\(port)")!
            // Astro takes a few seconds to come up.
            for _ in 0..<80 {
                if await Self.responds(url) {
                    state = .running(url)
                    return
                }
                guard task.isRunning else { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            stop()
            state = .failed("astro dev didn't start. Try npm run dev in the site folder to see why.")
        }
    }

    /// Stops the server Canteiro started. One it found running stays up.
    func stop() {
        process?.terminate()
        process = nil
    }

    private static func responds(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        return (try? await URLSession.shared.data(for: request)) != nil
    }
}

/// Finds listening ports with lsof.
enum DevServerScan {
    static let ports = 4321...4340

    /// A port in Astro's range whose server runs in the site's folder.
    static func port(servingSite site: URL) -> Int? {
        let sitePath = site.resolvingSymlinksInPath().path
        for (port, pid) in listeners() {
            guard let out = try? Subprocess.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]) else { continue }
            let cwd = out.stdoutString.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
            if cwd.map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == sitePath { return port }
        }
        return nil
    }

    static func freePort() -> Int {
        let taken = Set(listeners().map(\.port))
        return ports.first { !taken.contains($0) } ?? ports.upperBound
    }

    private static func listeners() -> [(port: Int, pid: Int32)] {
        let range = "\(ports.lowerBound)-\(ports.upperBound)"
        guard let out = try? Subprocess.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(range)", "-sTCP:LISTEN", "-Fpn"]) else { return [] }
        var result: [(Int, Int32)] = []
        var pid: Int32?
        for line in out.stdoutString.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid, let port = line.split(separator: ":").last.flatMap({ Int($0) }) {
                result.append((port, pid))
            }
        }
        return result
    }
}
