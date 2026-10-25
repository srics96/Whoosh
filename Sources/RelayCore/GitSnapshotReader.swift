import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum GitSnapshotReader {
    public static func capture(projectURL: URL, includeDiff: Bool) -> GitSnapshot {
        (try? captureCheckingCancellation(projectURL: projectURL, includeDiff: includeDiff))
            ?? GitSnapshot(available: false, note: "Git snapshot cancelled. No snapshot was accepted.")
    }

    public static func captureCheckingCancellation(projectURL: URL, includeDiff: Bool) throws -> GitSnapshot {
        do {
            try Task.checkCancellation()
            var failures: [String] = []
            func optional(_ args: [String]) throws -> String? {
                do { return try command(args, in: projectURL) }
                catch is CancellationError { throw CancellationError() }
                catch { failures.append(error.localizedDescription); return nil }
            }
            guard projectURL.isFileURL,
                  try projectURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw RelayError.invalidInput("The selected project folder is no longer available.")
            }
            let root = try command(["rev-parse", "--show-toplevel"], in: projectURL).trimmed
            let commit = try optional(["rev-parse", "--verify", "HEAD"])?.trimmed
            let branch = try optional(["symbolic-ref", "--quiet", "--short", "HEAD"])?.trimmed

            // Changed-file list and recent trajectory. External diff/textconv are disabled and the
            // environment ignores system/global config, so no repository-defined program is executed.
            let porcelain = try optional(["status", "--porcelain=v1", "-uall", "--no-renames"])?.trimmed
            let recentLog = try optional(["log", "-n", "10", "--format=%h %s"])?.trimmed
            var statusParts: [String] = []
            if let p = porcelain { statusParts.append(p.isEmpty ? "Working tree clean (no uncommitted changes)." : "Changed files:\n" + p) }
            if let l = recentLog, !l.isEmpty { statusParts.append("Recent commits:\n" + l) }
            let status: String? = statusParts.isEmpty ? nil : statusParts.joined(separator: "\n\n")

            var diff: String? = nil
            var note = "Read-only working-tree snapshot. No commit, stash, reset, index update, hook, or network."
            if includeDiff {
                if try hasContentFilters(projectURL) {
                    note += " Diff content was skipped: this repository configures Git content filters (clean/smudge); only the changed-file list is included."
                } else {
                    let staged = (try optional(["diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-color"])) ?? ""
                    let unstaged = (try optional(["diff", "--no-ext-diff", "--no-textconv", "--no-color"])) ?? ""
                    let combined = [staged.isEmpty ? nil : "# Staged changes\n" + staged,
                                    unstaged.isEmpty ? nil : "# Unstaged changes\n" + unstaged].compactMap { $0 }.joined(separator: "\n\n")
                    if !combined.isEmpty { diff = combined }
                    else if porcelain?.isEmpty == false { note += " A diff was requested but could not be captured (it may exceed the size budget); the changed-file list is still included." }
                }
            }
            if commit == nil { note += " No HEAD commit (this may be a new repository)." }
            if branch == nil, commit != nil { note += " HEAD is detached or the branch could not be read." }
            try Task.checkCancellation()
            if !failures.isEmpty { note += " Incomplete Git snapshot: " + failures.joined(separator: "; ") }
            return GitSnapshot(available: true, branch: branch, commit: commit,
                               repositoryRoot: root, status: status, trackedDiff: diff, note: note)
        } catch is CancellationError { throw CancellationError() } catch {
            return GitSnapshot(available: false, note: "Git snapshot unavailable: \(error.localizedDescription). The archive can still be saved.")
        }
    }

    /// True when the repository declares Git content filters (clean/smudge), in which case diff
    /// content is skipped so no repository-defined command can run while normalizing the working tree.
    private static func hasContentFilters(_ projectURL: URL) throws -> Bool {
        let cfg = try command(["config", "--get-regexp", "^filter\\."], in: projectURL, allowedStatuses: [0, 1])
        if
           !cfg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        for rel in [".gitattributes", ".git/info/attributes"] {
            if let text = try? String(contentsOf: projectURL.appendingPathComponent(rel), encoding: .utf8),
               text.contains("filter=") { return true }
        }
        return false
    }

    /// Arguments are separate argv entries. No shell, string interpolation into commands, hooks,
    /// credentials, global configuration, network access or writes to the selected repository.
    public static func arguments(for command: [String], projectURL: URL) -> [String] {
        ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
         "-c", "core.quotePath=true", "-C", projectURL.path] + command
    }

    private static func command(_ args: [String], in folder: URL, allowedStatuses: Set<Int32> = [0]) throws -> String {
        try Task.checkCancellation()
        let result = try BoundedGitProcess.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments(for: args, projectURL: folder),
            timeout: 8, maximumOutputBytes: 1_048_576, operation: "git " + (args.first ?? "read")
        )
        guard allowedStatuses.contains(result.status) else {
            throw RelayError.processFailed("git \(args.first ?? "read") exited with code \(result.status): " + String(result.stderr.prefix(800)).trimmed)
        }
        return result.stdout
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct GitProcessResult {
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

enum BoundedGitProcess {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                    maximumOutputBytes: Int, operation: String = "Git") throws -> GitProcessResult {
        try Task.checkCancellation()
        let started = ProcessInfo.processInfo.systemUptime
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
        let deadline = started + timeout
        // Poll the owned child's state, not a termination-handler callback which can be
        // delayed by queue scheduling. Pipe readers drain concurrently to avoid deadlock.
        while process.isRunning {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                OwnedProcess.stopAndWait(process)
                _ = readers.wait(timeout: .now() + 1)
                try Task.checkCancellation()
                throw RelayError.processFailed("\(operation) exceeded its \(timeout)-second process-exit timeout (elapsed \(ProcessInfo.processInfo.systemUptime - started)s)")
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Even a cancellation racing child exit waits for output cleanup before returning.
        guard readers.wait(timeout: .now() + 1) == .success else {
            try Task.checkCancellation()
            throw RelayError.processFailed("\(operation) exited but output did not close within 1 second")
        }
        try Task.checkCancellation()
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
