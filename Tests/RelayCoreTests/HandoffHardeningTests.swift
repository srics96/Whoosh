import Foundation
import XCTest
@testable import RelayCore

final class HandoffHardeningTests: XCTestCase {
    func testMissingProjectNeverFallsBack() throws {
        for value: String? in [nil, "", "relative", "/nonexistent-whoosh-regression", "/tmp\0"] {
            XCTAssertNil(ProjectFolder.available(value))
        }
    }
    func testTerminalLaunchDoesNotContainPromptAndQuotesPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh ' $(test) " + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for agent in [TerminalHandoff.Agent.claude, .codex] {
            let command = try TerminalHandoff.launchCommand(agent: agent, projectURL: folder)
            XCTAssertTrue(command.hasSuffix(" && command " + agent.rawValue))
            XCTAssertTrue(command.contains("'\"'\"'"))
        }
        try FileManager.default.removeItem(at: folder)
        XCTAssertThrowsError(try TerminalHandoff.launchCommand(agent: .codex, projectURL: folder))
    }
    func testGitCancellationIsNotOptionalFailure() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try GitSnapshotReader.captureCheckingCancellation(projectURL: FileManager.default.temporaryDirectory, includeDiff: true)) {
                XCTAssertTrue($0 is CancellationError)
            }
        }
        await task.value
    }
    func testProcessExitAndOutputLimit() throws {
        for _ in 0..<20 {
            let result = try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["complete"], timeout: 1, maximumOutputBytes: 100)
            XCTAssertEqual(result.stdout, "complete")
        }
        XCTAssertThrowsError(try BoundedGitProcess.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["oversized"], timeout: 1, maximumOutputBytes: 2))
    }
}
