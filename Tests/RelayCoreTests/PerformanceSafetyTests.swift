import Foundation
import XCTest
@testable import RelayCore

final class PerformanceSafetyTests: XCTestCase {
    func testScreenPreservesCredentialAndCardCoverage() throws {
        let secrets = [
            "-----BEGIN PRIVATE KEY-----", "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----", "-----BEGIN OPENSSH PRIVATE KEY-----",
            "sk-" + String(repeating: "x", count: 20),
            "ghp_" + String(repeating: "a", count: 20),
            "gho_" + String(repeating: "a", count: 20),
            "ghu_" + String(repeating: "a", count: 20),
            "ghs_" + String(repeating: "a", count: 20),
            "ghr_" + String(repeating: "a", count: 20),
            "AKIA1234567890ABCDEF", "PaSsWoRd = 'abcdefghijkl'",
            "API_KEY:\"abcdefghijkl\"", "access-token = abcdefghijkl",
            "clientsecret=abcdefghijkl", "4111 1111 1111 1111", "4111-1111-1111-1111",
            "４１１１ １１１１ １１１１ １１１１"
        ]
        for secret in secrets {
            XCTAssertTrue(try SensitiveContentScreen.scan(Data(("前 🌙\n" + secret + "\n後").utf8)), secret)
        }
        for safe in ["ordinary task notes", "password=short", "sk-short", "4111 1111 1111 1112", "0000000000000000"] {
            XCTAssertFalse(try SensitiveContentScreen.scan(Data(safe.utf8)), safe)
        }
    }

    func testScreenDoesNotTruncateOrMissBoundaries() throws {
        for offset in [65_530, 65_536, 1_048_570, 2_097_152] {
            let data = Data((String(repeating: "a", count: offset) + "\napi_key = abcdefghijkl\n").utf8)
            XCTAssertTrue(try SensitiveContentScreen.scan(data))
        }
        XCTAssertTrue(try SensitiveContentScreen.scan(Data(("password" + String(repeating: " ", count: 100_000) + "=abcdefghijkl").utf8)))
        var bytes = Data([0xff, 0x00]); bytes.append(Data("\npassword=abcdefghijkl".utf8))
        XCTAssertTrue(try SensitiveContentScreen.scan(bytes))
    }

    func testCancelledScreenAndHashThrowAndWrapperFailsClosed() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try SensitiveContentScreen.scan(Data("safe".utf8))) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertTrue(SensitiveContentScreen.requiresRedaction(Data("safe".utf8)))
            XCTAssertThrowsError(try SHA256.hexDigestCheckingCancellation(Data("safe".utf8))) { XCTAssertTrue($0 is CancellationError) }
        }
        await task.value
    }

    func testCancellationInterruptsRunningScan() async throws {
        let data = Data(repeating: 97, count: 16 * 1024 * 1024)
        let task = Task.detached { try SensitiveContentScreen.scan(data) }
        try await Task.sleep(nanoseconds: 30_000_000)
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Running scan ignored cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testDetachedWorkReceivesCancellation() async throws {
        let started = expectation(description: "worker started")
        let stopped = expectation(description: "worker cleanup completed")
        let task = Task {
            try await CancellableWork.run {
                defer { stopped.fulfill() }
                started.fulfill()
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return 1
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled worker returned a result") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testOwnedProcessIsReapedOnCancellation() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let task = Task { try await OwnedProcess.waitForExit(child, timeout: 60) }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled process returned success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(child.isRunning)
    }

    func testOwnedProcessTimeoutStopsChild() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        do { try await OwnedProcess.waitForExit(child, timeout: 0.02); XCTFail("Expected timeout") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertFalse(child.isRunning)
    }

    func testCancelledArchiveDoesNotCreatePackage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let conversation = try ImportedConversation(fileName: "synthetic.txt", data: Data("synthetic".utf8))
        let checkpoint = Checkpoint(sourceName: "synthetic", goal: "test", decisions: "", nextStep: "test", verification: "", sourceSessionStopped: true)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try HandoffWriter.prepare(conversation: conversation, checkpoint: checkpoint, projectURL: root,
                outputParent: root, gitSnapshot: GitSnapshot(available: false, note: "test"))) { XCTAssertTrue($0 is CancellationError) }
        }
        await task.value
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
}
