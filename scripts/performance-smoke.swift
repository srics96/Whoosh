// Direct-compiler fallback for hosts whose SwiftPM/XCTest installation is unavailable.
// Compile with RelayCore and run with assertions enabled (not -Ounchecked). Synthetic data only.
import Foundation
import RelayCore

@main struct PerformanceSmoke {
    @MainActor static func main() async throws {
        let secrets = ["-----BEGIN PRIVATE KEY-----", "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----",
            "sk-" + String(repeating: "x", count: 20), "AKIA1234567890ABCDEF",
            "PaSsWoRd = 'abcdefghijkl'", "API_KEY:\"abcdefghijkl\"", "access-token=abcdefghijkl",
            "clientsecret=abcdefghijkl", "4111 1111 1111 1111", "4111-1111-1111-1111", "４１１１ １１１１ １１１１ １１１１"]
            + ["p", "o", "u", "s", "r"].map { "gh\($0)_" + String(repeating: "a", count: 20) }
        for secret in secrets {
            precondition(tryScan("前 🌙\n" + secret + "\n後"))
        }
        // Differential checks against the old String.range scanner: no old positive may disappear.
        let oldPatterns = [
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            #"\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})\b"#,
            #"(?i)(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[=:]\s*[\"']?[A-Za-z0-9_+/=-]{12,}"#
        ]
        for prefix in ["", "é", "🌙", "a\u{0301}", "\0", "\n"] {
            for value in secrets + ["paſſword=abcdefghijkl", "API_KEY=abcdefghijkl", "api_key\u{2028}=abcdefghijkl"] {
                let candidate = prefix + value
                if oldPatterns.contains(where: { candidate.range(of: $0, options: .regularExpression) != nil }) {
                    precondition(tryScan(candidate), "Old scanner positive was lost")
                }
            }
        }
        for safe in ["ordinary task notes", "password=short", "sk-short", "4111 1111 1111 1112", "0000000000000000"] {
            precondition(!tryScan(safe))
        }
        for offset in [65_530, 65_536, 1_048_570, 2_097_152] {
            precondition(tryScan(String(repeating: "a", count: offset) + "\napi_key=abcdefghijkl"))
        }
        precondition(tryScan("password" + String(repeating: " ", count: 100_000) + "=abcdefghijkl"))
        var invalid = Data([0xff, 0]); invalid.append(Data("\npassword=abcdefghijkl".utf8))
        let invalidBlocked = try SensitiveContentScreen.scan(invalid)
        precondition(invalidBlocked)
        print("PASS credential/card/Unicode/invalid-UTF8 coverage, long whitespace, and end-of-input boundaries")

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try SensitiveContentScreen.scan(Data("safe".utf8)); preconditionFailure("Cancelled screen returned") }
            catch { precondition(error is CancellationError) }
            precondition(SensitiveContentScreen.requiresRedaction(Data("safe".utf8)))
            do { _ = try SHA256.hexDigestCheckingCancellation(Data("safe".utf8)); preconditionFailure("Cancelled hash returned") }
            catch { precondition(error is CancellationError) }
        }
        await cancelled.value
        print("PASS cancelled screening/hashing throws; Boolean screening fails closed")

        let (events, continuation) = AsyncStream<Void>.makeStream()
        let work = Task {
            try await CancellableWork.run {
                continuation.yield(())
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return 1
            }
        }
        for await _ in events { break }
        work.cancel()
        do { _ = try await work.value; preconditionFailure("Worker ignored cancellation") }
        catch { precondition(error is CancellationError) }
        print("PASS parent cancellation propagates to detached worker")

        for timeout in [false, true] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["30"]
            try child.run()
            let start = Date()
            let task = Task { try await OwnedProcess.waitForExit(child, timeout: timeout ? 0.02 : 60) }
            if !timeout { task.cancel() }
            do { try await task.value; preconditionFailure("Expected cancellation/timeout") }
            catch { precondition(timeout || error is CancellationError) }
            precondition(!child.isRunning && Date().timeIntervalSince(start) < 3)
        }
        print("PASS owned subprocess exits before cancellation/timeout returns")

        let large = Data(repeating: 97, count: 16 * 1024 * 1024)
        let scanTask = Task.detached { try SensitiveContentScreen.scan(large) }
        try await Task.sleep(nanoseconds: 30_000_000)
        let cancelledAt = Date()
        scanTask.cancel()
        do { _ = try await scanTask.value; preconditionFailure("Running scanner ignored cancellation") }
        catch { precondition(error is CancellationError) }
        precondition(Date().timeIntervalSince(cancelledAt) < 2)
        print("PASS cancellation interrupts an in-progress 16 MiB scan")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh-Regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let conversation = try ImportedConversation(fileName: "synthetic.txt", data: Data("synthetic".utf8))
        let checkpoint = Checkpoint(sourceName: "synthetic", goal: "test", decisions: "", nextStep: "test", verification: "", sourceSessionStopped: true)
        let archiveTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try HandoffWriter.prepare(conversation: conversation, checkpoint: checkpoint, projectURL: root,
                    outputParent: root, gitSnapshot: GitSnapshot(available: false, note: "test"))
                preconditionFailure("Cancelled archive returned")
            } catch { precondition(error is CancellationError) }
        }
        await archiveTask.value
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(contents.isEmpty)
        print("PASS cancelled archive creates no package")

        for mib in [1, 16, 64] {
            let data = Data(repeating: 97, count: mib * 1024 * 1024)
            var heartbeats = 0
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeats += 1
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            let start = Date()
            let blocked = try await CancellableWork.run { try SensitiveContentScreen.scan(data) }
            let elapsed = Date().timeIntervalSince(start)
            heartbeat.cancel()
            await heartbeat.value
            precondition(!blocked && heartbeats > 1, "Main actor could not service the heartbeat")
            print("screen_\(mib)MiB: \(elapsed) seconds; main-actor heartbeats: \(heartbeats)")
        }
    }
    static func tryScan(_ string: String) -> Bool { try! SensitiveContentScreen.scan(Data(string.utf8)) }
}
