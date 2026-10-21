import XCTest
@testable import RelayCore

final class RelayCoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Relay tests \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private var checkpoint: Checkpoint {
        Checkpoint(sourceName: "Codex", goal: "Keep the selected project working", decisions: "No dependencies",
                   nextStep: "Run the unit tests", verification: "Tests last passed", sourceSessionStopped: true)
    }
    private var noGit: GitSnapshot { GitSnapshot(available: false, note: "Synthetic fixture") }

    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256.hexDigest(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hexDigest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hexDigest(Data(repeating: 0x61, count: 1_000_000)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    func testDeepLinkRoundTripsUnicodeAndReservedCharacters() throws {
        let prompt = "Read café 🌙\nA+B & question? #100% = [done]"
        let path = "/Users/person/My project + café/#draft?"
        let url = try ClaudeLink.make(prompt: prompt, projectPath: path)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "claude")
        XCTAssertEqual(parts.host, "code")
        XCTAssertEqual(parts.path, "/new")
        XCTAssertEqual(parts.queryItems?.count, 2)
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "q" })?.value, prompt)
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "folder" })?.value, path)
        XCTAssertNil(parts.queryItems?.first(where: { $0.name == "file" }))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertFalse(url.absoluteString.contains(" "))
    }

    func testDeepLinkRefusesTruncationAndRelativePath() throws {
        XCTAssertNoThrow(try ClaudeLink.make(prompt: String(repeating: "x", count: 12_000), projectPath: "/tmp/project"))
        XCTAssertThrowsError(try ClaudeLink.make(prompt: String(repeating: "x", count: 12_001), projectPath: "/tmp/project"))
        XCTAssertThrowsError(try ClaudeLink.make(prompt: String(repeating: "🪄", count: 6_001), projectPath: "/tmp/project"))
        XCTAssertThrowsError(try ClaudeLink.make(prompt: "hello", projectPath: "relative/path"))
        XCTAssertThrowsError(try ClaudeLink.make(prompt: "", projectPath: "/tmp"))
    }

    func testArchivePreservesEveryByteIncludingInvalidUTF8() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A, 0x00, 0xFF, 0x20])
        let conversation = try ImportedConversation(fileName: "my transcript.txt", data: bytes)
        let prepared = try HandoffWriter.prepare(conversation: conversation, checkpoint: checkpoint,
                                                projectURL: root, outputParent: root, gitSnapshot: noGit)
        let archive = prepared.directory.appendingPathComponent(prepared.manifest.archiveRelativePath)
        XCTAssertEqual(try Data(contentsOf: archive), bytes)
        XCTAssertEqual(prepared.manifest.byteCount, bytes.count)
        XCTAssertEqual(prepared.manifest.sha256, SHA256.hexDigest(bytes))
        XCTAssertNil(prepared.manifest.utf8CharacterCount)
        XCTAssertFalse(prepared.manifest.nativeConversationImported)
        XCTAssertFalse(prepared.manifest.destinationReadVerified)
        let mode = try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let folderMode = try FileManager.default.attributesOfItem(atPath: prepared.directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(folderMode?.intValue, 0o700)
        let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: prepared.directory.appendingPathComponent("manifest.json"))) as? [String: Any]
        XCTAssertEqual(decoded?["byteCount"] as? Int, bytes.count)
    }

    func testJSONExportIsNotParsedNormalizedOrTruncated() throws {
        let text = "{\r\n  \"messages\": [ { \"text\": \"Hello 🌙\" } ], \"unknown\": 1.000\r\n}\n  "
        let original = Data(text.utf8)
        let source = try ImportedConversation(fileName: "export.json", data: original)
        let result = try HandoffWriter.prepare(conversation: source, checkpoint: checkpoint, projectURL: root, outputParent: root, gitSnapshot: noGit)
        XCTAssertEqual(try Data(contentsOf: result.directory.appendingPathComponent("transcript/original.json")), original)
        XCTAssertEqual(source.utf8CharacterCount, text.count)
        XCTAssertFalse(result.bootstrap.contains("unknown")) // Archive text is not silently stuffed into the URL.
    }

    func testNativeResponseArchiveKeepsPartialNotice() throws {
        let source = try ImportedConversation(fileName: "selected-session.jsonl", data: Data("{\"id\":1}\n".utf8),
                                              preservationNotice: "Exact selected API responses; not native storage.", isPartial: true)
        let result = try HandoffWriter.prepare(conversation: source, checkpoint: checkpoint, projectURL: root, outputParent: root, gitSnapshot: noGit)
        XCTAssertTrue(result.manifest.sourceIsPartial)
        XCTAssertTrue(result.bootstrap.contains("WARNING"))
        XCTAssertEqual(result.manifest.preservation, source.preservationNotice)
    }

    func testStoppedSourceAndPromptValidationPrecedeWrites() throws {
        let source = try ImportedConversation(fileName: "chat.md", data: Data("Synthetic history".utf8))
        var notStopped = checkpoint
        notStopped.sourceSessionStopped = false
        XCTAssertThrowsError(try HandoffWriter.prepare(conversation: source, checkpoint: notStopped, projectURL: root, outputParent: root, gitSnapshot: noGit))
        var tooLong = checkpoint
        tooLong.goal = String(repeating: "x", count: 13_000)
        XCTAssertThrowsError(try HandoffWriter.prepare(conversation: source, checkpoint: tooLong, projectURL: root, outputParent: root, gitSnapshot: noGit))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testRepeatedPreparationNeverOverwritesPackage() throws {
        let source = try ImportedConversation(fileName: "chat.txt", data: Data("Synthetic".utf8))
        let a = try HandoffWriter.prepare(conversation: source, checkpoint: checkpoint, projectURL: root, outputParent: root, gitSnapshot: noGit)
        let b = try HandoffWriter.prepare(conversation: source, checkpoint: checkpoint, projectURL: root, outputParent: root, gitSnapshot: noGit)
        XCTAssertNotEqual(a.directory, b.directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.directory.appendingPathComponent("manifest.json").path))
    }

    func testSelectedFileRejectsSymbolicLinkAndWrongExtension() throws {
        let real = root.appendingPathComponent("real.txt")
        try Data("Synthetic".utf8).write(to: real)
        let alias = root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        XCTAssertThrowsError(try ImportedConversation.readSelectedFile(alias))
        XCTAssertThrowsError(try ImportedConversation(fileName: "anything.db", data: Data([1])))
        XCTAssertThrowsError(try ImportedConversation(fileName: "empty.txt", data: Data()))
    }

    func testGitArgumentsNeverUseShellInterpolation() {
        let tricky = "/tmp/project with spaces;$(touch SHOULD_NOT_EXIST) & 'quoted'"
        let args = GitSnapshotReader.arguments(for: ["status", "--porcelain=v1", "--", "."], projectURL: URL(fileURLWithPath: tricky))
        XCTAssertTrue(args.contains(tricky))
        XCTAssertEqual(args[args.firstIndex(of: "-C")! + 1], tricky)
        XCTAssertFalse(args.contains("-lc"))
        XCTAssertTrue(args.contains("--no-optional-locks"))
        XCTAssertTrue(args.contains("core.fsmonitor=false"))
    }

    func testGitSnapshotIsMetadataOnlyAndReadOnly() throws {
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "Synthetic Test"])
        try git(["config", "user.email", "synthetic@example.invalid"])
        let selected = root.appendingPathComponent("selected project", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        let inside = selected.appendingPathComponent("inside.txt")
        let outside = root.appendingPathComponent("outside.txt")
        try Data("old inside\n".utf8).write(to: inside)
        try Data("old outside\n".utf8).write(to: outside)
        try git(["add", "."])
        try git(["commit", "-m", "Synthetic fixture"])
        try Data("new inside\n".utf8).write(to: inside)
        try Data("new outside\n".utf8).write(to: outside)
        try Data("untracked private body\n".utf8).write(to: selected.appendingPathComponent("untracked.txt"))
        let index = root.appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        let snapshot = GitSnapshotReader.capture(projectURL: selected, includeDiff: true)
        XCTAssertTrue(snapshot.available, snapshot.note)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertNil(snapshot.status)
        XCTAssertNil(snapshot.trackedDiff)
        XCTAssertTrue(snapshot.note.contains("Metadata only"))
        XCTAssertEqual(try Data(contentsOf: index), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/index.lock").path))
    }


    func testRepositoryCleanFiltersNeverExecute() throws {
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "Synthetic Test"])
        try git(["config", "user.email", "synthetic@example.invalid"])
        let file = root.appendingPathComponent("tracked.txt")
        try Data("first\n".utf8).write(to: file)
        try git(["add", "."])
        try git(["commit", "-m", "Synthetic fixture"])
        try Data("tracked.txt filter=unsafe\n".utf8).write(to: root.appendingPathComponent(".gitattributes"))
        try git(["config", "filter.unsafe.clean", "touch RELAY_FILTER_MUST_NOT_RUN; cat"])
        try Data("other\n".utf8).write(to: file)
        let result = GitSnapshotReader.capture(projectURL: root, includeDiff: true)
        XCTAssertTrue(result.available, result.note)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("RELAY_FILTER_MUST_NOT_RUN").path))
        XCTAssertNil(result.status)
        XCTAssertNil(result.trackedDiff)
    }

    @discardableResult private func git(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RelayError.processFailed("Synthetic fixture git failed") }
        return process.terminationStatus
    }
}
