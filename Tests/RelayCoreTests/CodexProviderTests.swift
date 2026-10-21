import XCTest
@testable import RelayCore

final class CodexProviderTests: XCTestCase {
    func testConsentRequiredBeforeAnyLaunch() async throws {
        let transport = MockCodexTransport([])
        let provider = CodexNativeSourceProvider(transport: transport)
        do {
            _ = try await provider.connect(executableURL: executable, userApproved: false)
            XCTFail("Expected explicit consent guard")
        } catch CodexSourceError.consentRequired { }
        let launches = await transport.launchCount
        XCTAssertEqual(launches, 0)
    }

    func testThreadListUsesDatabaseOnlyAndExplicitHumanSources() async throws {
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList())])
        let provider = try await connected(transport)
        let page = try await provider.listThreads(limit: 500)
        XCTAssertEqual(page.threads.first?.displayName, "Synthetic conversation")
        let calls = await transport.calls
        let list = try XCTUnwrap(calls.last)
        XCTAssertEqual(list.method, .threadList)
        XCTAssertEqual(list.params["useStateDbOnly"], .bool(true))
        XCTAssertEqual(list.params["archived"], .bool(false))
        XCTAssertEqual(list.params["limit"], .number(100))
        XCTAssertEqual(list.params["sourceKinds"], .array([.string("cli"), .string("vscode"), .string("appServer"), .string("exec")]))
        await provider.disconnect()
    }

    func testUnknownSelectionDoesNotReadHistory() async throws {
        let transport = MockCodexTransport([.success(try initialization())])
        let provider = try await connected(transport)
        do {
            _ = try await provider.readThread(id: "not-in-picker")
            XCTFail("Unknown thread should not be read")
        } catch CodexSourceError.notListed { }
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.method), [.initialize])
        await provider.disconnect()
    }

    func testCapturePreservesExactAPIBytesButRendersOnlyConversationText() async throws {
        let metadata = try threadMetadata()
        let page = try response(#"{"data":[{"turnId":"turn-1","item":{"id":"u-1","type":"userMessage","content":[{"type":"text","text":"Hello"},{"type":"localImage","path":"synthetic-image.png"}]}},{"turnId":"turn-1","item":{"id":"r-1","type":"reasoning","content":["synthetic-private-item"]}},{"turnId":"turn-1","item":{"id":"tool-1","type":"commandExecution","aggregatedOutput":"synthetic-tool-output"}},{"turnId":"turn-1","item":{"id":"a-1","type":"agentMessage","text":"Hi there"}}],"nextCursor":null}"#, id: 44)
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList()), .success(metadata), .success(page)])
        let provider = try await connected(transport)
        _ = try await provider.listThreads()
        let capture = try await provider.readThread(id: "thread-1")
        XCTAssertEqual(capture.messages.map(\.text), ["Hello", "Hi there"])
        XCTAssertEqual(capture.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(capture.rawResponsesJSONL, metadata.rawLine + page.rawLine)
        XCTAssertFalse(capture.renderedTranscript.contains("synthetic-private-item"))
        XCTAssertFalse(capture.renderedTranscript.contains("synthetic-tool-output"))
        XCTAssertTrue(String(decoding: capture.rawResponsesJSONL, as: UTF8.self).contains("synthetic-private-item"))
        XCTAssertFalse(capture.isPartial)
        XCTAssertNil(capture.nextCursor)
        XCTAssertTrue(capture.preservationNotice.contains("not the original native"))
        let calls = await transport.calls
        XCTAssertEqual(calls[2].params["includeTurns"], .bool(false))
        XCTAssertEqual(calls[3].params["sortDirection"], .string("asc"))
        await provider.disconnect()
    }

    func testPageLimitRemainsExplicitlyPartial() async throws {
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList()),
            .success(try threadMetadata()), .success(try response(#"{"data":[],"nextCursor":"older-page"}"#))])
        let provider = try await connected(transport)
        _ = try await provider.listThreads()
        let capture = try await provider.readThread(id: "thread-1", maxPages: 1)
        XCTAssertTrue(capture.isPartial)
        XCTAssertEqual(capture.nextCursor, "older-page")
        XCTAssertTrue(capture.preservationNotice.contains("History is partial"))
        await provider.disconnect()
    }

    func testRepeatedCursorFailsRatherThanLooping() async throws {
        let page = try response(#"{"data":[],"nextCursor":"same-cursor"}"#)
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList()),
            .success(try threadMetadata()), .success(page), .success(page)])
        let provider = try await connected(transport)
        _ = try await provider.listThreads()
        do {
            _ = try await provider.readThread(id: "thread-1")
            XCTFail("Repeated cursor must fail")
        } catch CodexSourceError.invalidResponse(let detail) { XCTAssertEqual(detail, "repeated pagination cursor") }
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 5)
        await provider.disconnect()
    }

    func testUnsupportedItemPaginationDoesNotFallBackToResumeOrFullHistory() async throws {
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList()),
            .success(try threadMetadata()), .failure(.remote(-32601, "Synthetic unsupported method"))])
        let provider = try await connected(transport)
        _ = try await provider.listThreads()
        do {
            _ = try await provider.readThread(id: "thread-1")
            XCTFail("Unsupported pagination should surface")
        } catch CodexSourceError.remote(let code, _) { XCTAssertEqual(code, -32601) }
        let calls = await transport.calls
        XCTAssertEqual(calls.map(\.method), [.initialize, .threadList, .threadRead, .threadItemsList])
        await provider.disconnect()
    }

    func testMissingQuotaDoesNotBecomeZeroOrUnlimited() async throws {
        let transport = MockCodexTransport([.success(try initialization()),
            .success(try response(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":null},"secondary":null}}"#))])
        let provider = try await connected(transport)
        let quota = try await provider.readRateLimits()
        XCTAssertEqual(quota.buckets.count, 1)
        XCTAssertNil(quota.buckets.first?.primary?.usedPercent)
        XCTAssertNil(quota.buckets.first?.primary?.resetsAt)
        XCTAssertNil(quota.buckets.first?.secondary)
        await provider.disconnect()
    }

    func testDisconnectClearsConnectionAndSelection() async throws {
        let transport = MockCodexTransport([.success(try initialization()), .success(try threadList())])
        let provider = try await connected(transport)
        _ = try await provider.listThreads()
        await provider.disconnect()
        do {
            _ = try await provider.readThread(id: "thread-1")
            XCTFail("Disconnected source should not read")
        } catch CodexSourceError.notConnected { }
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testFramerPreservesSplitUTF8AndMultipleResponseLines() throws {
        let first = Data("{ \"id\" : 1, \"result\" : {\"text\":\"Hello 🦋\"} }\n".utf8)
        let second = Data("{\"id\":2,\"result\":{}}\r\n".utf8)
        let bytes = first + second
        var framer = CodexRPCLineFramer()
        var received: [Data] = []
        // One-byte fragments split both the UTF-8 sequence and JSON frame boundaries.
        for byte in bytes { received += try framer.append(Data([byte])) }
        XCTAssertEqual(received, [first, second])
        var combined = CodexRPCLineFramer()
        XCTAssertEqual(try combined.append(bytes), [first, second])
    }

    func testFramerRejectsOversizedUndelimitedAndCompleteFrames() throws {
        var incomplete = CodexRPCLineFramer(maximumLineBytes: 4)
        XCTAssertThrowsError(try incomplete.append(Data("12345".utf8)))
        var complete = CodexRPCLineFramer(maximumLineBytes: 4)
        XCTAssertThrowsError(try complete.append(Data("12345\n".utf8)))
    }

    private var executable: URL { URL(fileURLWithPath: "/synthetic-only/codex") }
    private func connected(_ transport: MockCodexTransport) async throws -> CodexNativeSourceProvider {
        let provider = CodexNativeSourceProvider(transport: transport)
        let info = try await provider.connect(executableURL: executable, userApproved: true)
        XCTAssertEqual(info.cliVersion, "codex-synthetic-test")
        XCTAssertTrue(info.databaseOnlyListingVerified)
        return provider
    }
    private func initialization() throws -> CodexRPCResponse { try response(#"{"userAgent":"synthetic-agent","platformOs":"macos"}"#) }
    private func threadList() throws -> CodexRPCResponse { try response(#"{"data":[{"id":"thread-1","name":"Synthetic conversation","cwd":"/synthetic-project"}],"nextCursor":null}"#) }
    private func threadMetadata() throws -> CodexRPCResponse { try response(#"{"thread":{"id":"thread-1","name":"Synthetic conversation"}}"#, id: 33) }
    private func response(_ json: String, id: Int = 1) throws -> CodexRPCResponse {
        let result = try JSONDecoder().decode(CodexJSONValue.self, from: Data(json.utf8))
        // Preserve deliberate spaces and the delimiter to detect decode/re-encode substitution.
        return CodexRPCResponse(result: result, rawLine: Data("{ \"id\" : \(id), \"result\" : \(json) }\n".utf8))
    }
}

private actor MockCodexTransport: CodexReadOnlyRPCTransport {
    enum Reply: Sendable { case success(CodexRPCResponse), failure(CodexSourceError) }
    struct Call: Sendable { let method: CodexReadMethod; let params: [String: CodexJSONValue] }
    private var replies: [Reply]
    private(set) var calls: [Call] = []
    private(set) var launchCount = 0
    init(_ replies: [Reply]) { self.replies = replies }
    func connect(executableURL: URL) async throws -> String { launchCount += 1; return "codex-synthetic-test" }
    func request(_ method: CodexReadMethod, params: [String: CodexJSONValue]) async throws -> CodexRPCResponse {
        calls.append(Call(method: method, params: params))
        guard !replies.isEmpty else { throw CodexSourceError.invalidResponse("synthetic replies exhausted") }
        switch replies.removeFirst() {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
    func initialized() async throws { }
    func disconnect() async { }
}
