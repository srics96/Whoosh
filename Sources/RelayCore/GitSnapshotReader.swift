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

            // Changed-file list and recent trajectory. External diff/textconv are disabled and the
            // environment ignores system/global config, so no repository-defined program is executed.
            let porcelain = (try? command(["status", "--porcelain=v1", "-uall", "--no-renames"], in: projectURL))?.trimmed
            let recentLog = (try? command(["log", "-n", "10", "--format=%h %s"], in: projectURL))?.trimmed
            var statusParts: [String] = []
            if let p = porcelain { statusParts.append(p.isEmpty ? "Working tree clean (no uncommitted changes)." : "Changed files:\n" + p) }
            if let l = recentLog, !l.isEmpty { statusParts.append("Recent commits:\n" + l) }
            let status: String? = statusParts.isEmpty ? nil : statusParts.joined(separator: "\n\n")

            var diff: String? = nil
            var note = "Read-only working-tree snapshot. No commit, stash, reset, index update, hook, or network."
            if includeDiff {
                if hasContentFilters(projectURL) {
                    note += " Diff content was skipped: this repository configures Git content filters (clean/smudge); only the changed-file list is included."
                } else {
                    let staged = (try? command(["diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-color"], in: projectURL)) ?? ""
                    let unstaged = (try? command(["diff", "--no-ext-diff", "--no-textconv", "--no-color"], in: projectURL)) ?? ""
                    let combined = [staged.isEmpty ? nil : "# Staged changes\n" + staged,
                                    unstaged.isEmpty ? nil : "# Unstaged changes\n" + unstaged].compactMap { $0 }.joined(separator: "\n\n")
                    if !combined.isEmpty { diff = combined }
                    else if porcelain?.isEmpty == false { note += " A diff was requested but could not be captured (it may exceed the size budget); the changed-file list is still included." }
                }
            }
            if commit == nil { note += " No HEAD commit (this may be a new repository)." }
            if branch == nil, commit != nil { note += " HEAD is detached or the branch could not be read." }
            return GitSnapshot(available: true, branch: branch, commit: commit,
                               repositoryRoot: root, status: status, trackedDiff: diff, note: note)
        } catch {
            return GitSnapshot(available: false, note: "Git snapshot unavailable: \(error.localizedDescription). The archive can still be saved.")
        }
    }

    /// True when the repository declares Git content filters (clean/smudge), in which case diff
    /// content is skipped so no repository-defined command can run while normalizing the working tree.
    private static func hasContentFilters(_ projectURL: URL) -> Bool {
        if let cfg = try? command(["config", "--get-regexp", "^filter\\."], in: projectURL),
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

    private static func command(_ args: [String], in folder: URL) throws -> String {
        try Task.checkCancellation()
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
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while done.wait(timeout: .now() + 0.02) == .timedOut {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                OwnedProcess.stopAndWait(process)
                _ = readers.wait(timeout: .now() + 1)
                try Task.checkCancellation()
                throw RelayError.processFailed("Git exceeded the 8-second read timeout")
            }
        }
        try Task.checkCancellation()
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
