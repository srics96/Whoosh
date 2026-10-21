import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum GitSnapshotReader {
    public static func capture(projectURL: URL, includeDiff: Bool) -> GitSnapshot {
        do {
            guard projectURL.isFileURL,
                  try projectURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw RelayError.invalidInput("The selected project folder is no longer available.")
            }
            let root = try command(["rev-parse", "--show-toplevel"], in: projectURL).trimmed
            let commit = try? command(["rev-parse", "--verify", "HEAD"], in: projectURL).trimmed
            let branch = try? command(["symbolic-ref", "--quiet", "--short", "HEAD"], in: projectURL).trimmed
            // IMPORTANT: even git status may run repository-configured clean filters.
            // Until a fully sandboxed provider exists, do not inspect worktree status or diffs.
            // rev-parse and symbolic-ref inspect metadata without applying content filters.
            let status: String? = nil
            let diff: String? = nil
            var note = "Metadata only. Working-tree status, tracked diffs, untracked contents and submodule changes were not captured because Git content filters can execute repository-defined commands. No commit, stash, reset or index update."
            if includeDiff { note += " Diff capture was requested but is intentionally disabled in this prototype." }
            if commit == nil { note += " No HEAD commit was available (this may be a new repository)." }
            if branch == nil, commit != nil { note += " HEAD is detached or the branch could not be read." }
            return GitSnapshot(available: true, branch: branch, commit: commit,
                               repositoryRoot: root, status: status, trackedDiff: diff, note: note)
        } catch {
            return GitSnapshot(available: false, note: "Git snapshot unavailable: \(error.localizedDescription). The archive can still be saved.")
        }
    }

    /// Arguments are separate argv entries. No shell, string interpolation into commands, hooks,
    /// credentials, global configuration, network access or writes to the selected repository.
    public static func arguments(for command: [String], projectURL: URL) -> [String] {
        ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
         "-c", "core.quotePath=true", "-C", projectURL.path] + command
    }

    private static func command(_ args: [String], in folder: URL) throws -> String {
        let result = try BoundedGitProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments(for: args, projectURL: folder),
            timeout: 8, maximumOutputBytes: 1_048_576
        )
        guard result.status == 0 else {
            throw RelayError.processFailed(String(result.stderr.prefix(800)).trimmed.isEmpty
                ? "git exited with code \(result.status)" : String(result.stderr.prefix(800)).trimmed)
        }
        return result.stdout
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct GitProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private final class BoundedCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()
    private var exceeded = false
    let limit: Int
    init(limit: Int) { self.limit = limit }
    func consume(_ handle: FileHandle) {
        defer { try? handle.close() }
        while true {
            guard let chunk = try? handle.read(upToCount: 16_384), !chunk.isEmpty else { break }
            lock.lock()
            let remaining = max(0, limit - stored.count)
            stored.append(chunk.prefix(remaining))
            if chunk.count > remaining { exceeded = true }
            lock.unlock()
        }
    }
    var result: (Data, Bool) { lock.lock(); defer { lock.unlock() }; return (stored, exceeded) }
}

private enum BoundedGitProcess {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                    maximumOutputBytes: Int) throws -> GitProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // A minimal environment avoids inherited credential helpers and injected Git config.
        process.environment = [
            "PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C",
            "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_PAGER": "cat"
        ]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        // Closing our copies ensures EOF arrives after the child's descriptor closes.
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        let stdout = BoundedCapture(limit: maximumOutputBytes)
        let stderr = BoundedCapture(limit: 16_384)
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async { stdout.consume(out.fileHandleForReading); readers.leave() }
        readers.enter()
        DispatchQueue.global(qos: .utility).async { stderr.consume(err.fileHandleForReading); readers.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 0.5) == .timedOut {
                #if canImport(Darwin) || canImport(Glibc)
                _ = kill(process.processIdentifier, SIGKILL)
                #endif
                _ = done.wait(timeout: .now() + 1)
            }
            throw RelayError.processFailed("Git exceeded the 8-second read timeout")
        }
        guard readers.wait(timeout: .now() + 1) == .success else {
            throw RelayError.processFailed("Git output did not close cleanly")
        }
        let (outData, outExceeded) = stdout.result
        let (errData, errExceeded) = stderr.result
        guard !outExceeded, !errExceeded else {
            throw RelayError.processFailed("Git output exceeded the safe capture limit; no truncated snapshot was accepted")
        }
        return GitProcessResult(status: process.terminationStatus,
                                stdout: String(decoding: outData, as: UTF8.self),
                                stderr: String(decoding: errData, as: UTF8.self))
    }
}
