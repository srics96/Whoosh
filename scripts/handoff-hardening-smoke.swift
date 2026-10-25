import Foundation
@testable import RelayCore

@main struct HardeningSmoke {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh-Hardening-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path: String? in [nil, "", "relative", "/definitely-missing-whoosh-test", root.path + "\0"] {
            precondition(ProjectFolder.available(path) == nil)
        }
        let hostile = root.appendingPathComponent("quote' $(touch PWNED); spaced")
        try FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
        for agent in [TerminalHandoff.Agent.claude, .codex] {
            let command = try TerminalHandoff.launchCommand(agent: agent, projectURL: hostile)
            // Execute only the generated cd prefix plus pwd, never a real CLI or prompt.
            let prefix = String(command.prefix(upTo: command.range(of: " && command ")!.lowerBound))
            let result = try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", prefix + " && pwd"], timeout: 2, maximumOutputBytes: 4096)
            precondition(result.status == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == hostile.path)
            precondition(!FileManager.default.fileExists(atPath: hostile.appendingPathComponent("PWNED").path))
            precondition(command.hasSuffix(" && command " + agent.rawValue))
        }
        print("PASS missing/invalid project rejected; shell metacharacters stay literal; CLI launch has no prompt")
        for _ in 0..<30 {
            let result = try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["ok"], timeout: 1, maximumOutputBytes: 1024)
            precondition(result.status == 0 && result.stdout == "ok")
        }
        print("PASS 30 rapid child exits with complete pipe output")
        do {
            _ = try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.03, maximumOutputBytes: 1024, operation: "synthetic sleep")
            preconditionFailure("Timeout accepted")
        } catch { precondition(error.localizedDescription.contains("process-exit timeout")) }
        let worker = Task.detached {
            try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 60, maximumOutputBytes: 1024)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = Date(); worker.cancel()
        do { _ = try await worker.value; preconditionFailure("Cancellation accepted") }
        catch { precondition(error is CancellationError) }
        precondition(Date().timeIntervalSince(start) < 2)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try GitSnapshotReader.captureCheckingCancellation(projectURL: root, includeDiff: true); preconditionFailure("Cancellation swallowed") }
            catch { precondition(error is CancellationError) }
        }
        await cancelled.value
        print("PASS bounded timeout, running-child cancellation and snapshot cancellation propagation")
        do {
            _ = try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: [String(repeating: "x", count: 4096)], timeout: 2, maximumOutputBytes: 16)
            preconditionFailure("Oversized output accepted")
        } catch { precondition(error.localizedDescription.contains("no truncated snapshot")) }
        print("PASS oversized output fails instead of truncating")
    }
}
