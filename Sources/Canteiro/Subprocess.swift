import Foundation

/// Runs a short-lived tool (`node`, `git`) and collects
/// its output, with a hard deadline.
///
/// Every tool call goes through here so two failure modes are handled in one
/// place: a child that writes more than a pipe buffer (~64 KB) blocks until
/// someone reads, so waiting for exit before reading deadlocks; and a tool that
/// hangs would otherwise stall the app forever without anyone noticing.
///
/// Blocking: call from a background task, never the main actor.
enum Subprocess {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
        var stderrString: String { String(decoding: stderr, as: UTF8.self) }
    }

    enum Failure: LocalizedError, Equatable {
        case unlaunchable(reason: String)
        case timedOut(seconds: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .unlaunchable(let reason):
                return reason
            case .timedOut(let seconds):
                return "no answer after \(Int(seconds.rounded())) seconds"
            }
        }
    }

    static let defaultTimeout: TimeInterval = 5

    static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = defaultTimeout,
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> Output {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        if let environment {
            task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        task.currentDirectoryURL = currentDirectory
        task.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

        do {
            try task.run()
        } catch {
            throw Failure.unlaunchable(reason: error.localizedDescription)
        }

        // Drain both pipes while the child runs, not after it exits.
        let drained = DispatchGroup()
        let out = drain(outPipe.fileHandleForReading, group: drained)
        let err = drain(errPipe.fileHandleForReading, group: drained)

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut {
                kill(task.processIdentifier, SIGKILL)
            }
            // Don't wait any further: a process stuck in the kernel ignores
            // even SIGKILL, and the caller must get its answer now. The drain
            // threads finish whenever the child finally goes away.
            throw Failure.timedOut(seconds: timeout)
        }

        // The child is gone. A grandchild could still hold the pipe open, so
        // bound this wait too rather than trusting EOF to arrive. Past the
        // deadline the buffers are still being written, so don't touch them.
        guard drained.wait(timeout: .now() + 1) == .success else {
            return Output(status: task.terminationStatus, stdout: Data(), stderr: Data())
        }

        return Output(status: task.terminationStatus, stdout: out.data, stderr: err.data)
    }

    private final class Buffer: @unchecked Sendable {
        // Written once on the drain thread, read after `DispatchGroup.wait`.
        var data = Data()
    }

    private static func drain(_ handle: FileHandle, group: DispatchGroup) -> Buffer {
        let buffer = Buffer()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            buffer.data = handle.readDataToEndOfFile()
            group.leave()
        }
        return buffer
    }
}
