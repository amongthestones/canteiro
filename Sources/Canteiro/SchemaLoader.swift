import Foundation

/// Reads the site's Keystatic config by running `schema-dump.mjs` with the
/// site's own Node and Vite. The app keeps no copy of the field list.
enum SchemaLoader {
    enum Failure: LocalizedError {
        case noNode
        case noScript
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noNode: return "Node isn't installed, or isn't where Canteiro looks (Homebrew, /usr/local or your shell's PATH)."
            case .noScript: return "schema-dump.mjs is missing from the app."
            case .failed(let detail): return "Couldn't read keystatic.config.ts. \(detail)"
            }
        }
    }

    static func load(site: URL) async throws -> SiteSchema {
        try await Task.detached(priority: .userInitiated) {
            guard let node = NodeLocator.path() else { throw Failure.noNode }
            guard let script = scriptURL() else { throw Failure.noScript }
            let out: Subprocess.Output
            do {
                out = try Subprocess.run(node, [script.path, site.path], timeout: 30, currentDirectory: site)
            } catch {
                throw Failure.failed(error.localizedDescription)
            }
            guard out.status == 0 else {
                let lines = out.stderrString.split(separator: "\n").prefix(6).joined(separator: "\n")
                throw Failure.failed(lines)
            }
            do {
                return try JSONDecoder().decode(SiteSchema.self, from: out.stdout)
            } catch {
                throw Failure.failed("The schema didn't decode: \(error)")
            }
        }.value
    }

    /// In the app bundle once packaged; next to the sources under `swift run`.
    static func scriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "schema-dump", withExtension: "mjs") { return bundled }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appending(path: "scripts/schema-dump.mjs")
        return FileManager.default.fileExists(atPath: script.path) ? script : nil
    }
}

/// Finds `node`. An app opened from Finder doesn't get the shell's PATH, so
/// check the usual places, then ask a login shell.
enum NodeLocator {
    static func path() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(home)/.volta/bin/node"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        guard let out = try? Subprocess.run("/bin/zsh", ["-lic", "command -v node"], timeout: 5) else { return nil }
        let found = out.stdoutString.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        guard let found, FileManager.default.isExecutableFile(atPath: found) else { return nil }
        return found
    }
}
