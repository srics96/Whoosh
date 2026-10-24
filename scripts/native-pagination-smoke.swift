import Foundation
import RelayCore
actor Fixture: CodexReadOnlyRPCTransport {
 var replies: [CodexRPCResponse]
 var delay: UInt64 = 0
 func setDelay(_ value: UInt64) { delay = value }
 var calls: [(CodexReadMethod, [String:CodexJSONValue])] = []
 init(_ values: [String]) throws { replies = try values.enumerated().map { index,json in CodexRPCResponse(result: try JSONDecoder().decode(CodexJSONValue.self, from: Data(json.utf8)), rawLine: Data("{\"id\":\(index),\"result\":\(json)}\n".utf8)) } }
 func connect(executableURL: URL) async throws -> String { "codex-synthetic" }
 func initialized() async throws {}
 func disconnect() async {}
 func request(_ method: CodexReadMethod, params: [String:CodexJSONValue]) async throws -> CodexRPCResponse { calls.append((method,params)); if method == .threadItemsList && delay > 0 { try await Task.sleep(nanoseconds: delay) }; guard !replies.isEmpty else {throw CodexSourceError.invalidResponse("fixture exhausted")};return replies.removeFirst() }
}
@main struct PaginationSmoke {
 static func main() async throws {
 let prefix = [#"{"userAgent":"synthetic"}"#, #"{"data":[{"id":"synthetic","name":"Synthetic"}],"nextCursor":null}"#, #"{"thread":{"id":"synthetic","name":"Synthetic"}}"#]
 let page1 = #"{"data":[{"turnId":"t1","item":{"id":"u1","type":"userMessage","content":[{"type":"text","text":"first"}]}},{"turnId":"t1","item":{"id":"tool1","type":"commandExecution","aggregatedOutput":"FULL-TOOL-MARKER"}}],"nextCursor":"page2"}"#
 let page2 = #"{"data":[{"turnId":"t2","item":{"id":"a2","type":"agentMessage","text":"LAST-PAGE-MARKER"}}],"nextCursor":null}"#
 let mock = try Fixture(prefix + [page1,page2]);let p = CodexNativeSourceProvider(transport: mock)
 _ = try await p.connect(executableURL: URL(fileURLWithPath:"/synthetic"), userApproved:true);_ = try await p.listThreads()
 let capture = try await p.readThread(id:"synthetic",maxPages:2,pageSize:1)
 assert(capture.messages.map(\.text) == ["first","LAST-PAGE-MARKER"] && !capture.isPartial)
 let raw = String(decoding:capture.rawResponsesJSONL,as:UTF8.self)
 assert(raw.contains("FULL-TOOL-MARKER") && raw.contains("LAST-PAGE-MARKER"))
 let calls = await mock.calls
 assert(calls[3].0 == .threadItemsList && calls[4].1["cursor"] == .string("page2") && calls[3].1["turnId"] == nil && calls[3].1["sortDirection"] == .string("asc"))
 print("PASS: full item pages across turns preserve order, final page, tool bytes, and cursor")
 let partialMock = try Fixture(prefix + [page1]);let partialProvider = CodexNativeSourceProvider(transport:partialMock)
 _ = try await partialProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true);_ = try await partialProvider.listThreads()
 let partial = try await partialProvider.readThread(id:"synthetic",maxPages:1)
 assert(partial.isPartial && partial.nextCursor == "page2")
 print("PASS: bounded export is explicitly partial")
 let repeatedMock = try Fixture(prefix + [page1,page1]);let repeatedProvider = CodexNativeSourceProvider(transport:repeatedMock)
 _ = try await repeatedProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true);_ = try await repeatedProvider.listThreads()
 var rejected = false
 do {_ = try await repeatedProvider.readThread(id:"synthetic",maxPages:3)} catch CodexSourceError.invalidResponse {rejected=true}
 assert(rejected);print("PASS: repeated cursor fails closed")

 let longPages = (0..<12).map { page -> String in
   let entries = (0..<100).map { item in "{\"turnId\":\"t\(page)\",\"item\":{\"id\":\"i\(item)\",\"type\":\"agentMessage\",\"text\":\"message-\(page * 100 + item)\"}}" }.joined(separator:",")
   let cursor = page == 11 ? "null" : "\"p\(page+1)\""
   return "{\"data\":[\(entries)],\"nextCursor\":\(cursor)}"
 }
 let longMock = try Fixture(prefix + longPages); let longProvider = CodexNativeSourceProvider(transport:longMock)
 _ = try await longProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true); _ = try await longProvider.listThreads()
 let full = try await longProvider.readThread(id:"synthetic")
 assert(full.messages.count == 1200 && full.messages.last?.text == "message-1199" && !full.isPartial)
 print("PASS: normal capture drains 12 pages / 1200 items including newest context")
 let slow = try Fixture(prefix + [page1]); await slow.setDelay(2_000_000_000)
 let timed = CodexNativeSourceProvider(transport:slow)
 _ = try await timed.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true); _ = try await timed.listThreads()
 var timedOut = false
 do { _ = try await timed.readThread(id:"synthetic",timeBudgetSeconds:0.02) } catch { timedOut = true }
 assert(timedOut); print("PASS: deadline throws rather than returning an old prefix")
 let slowCancel = try Fixture(prefix + [page1]); await slowCancel.setDelay(2_000_000_000)
 let cancelProvider = CodexNativeSourceProvider(transport:slowCancel)
 _ = try await cancelProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true); _ = try await cancelProvider.listThreads()
 let cancelStarted = Date()
 let work = Task { try await cancelProvider.readThread(id:"synthetic") }
 try await Task.sleep(nanoseconds:20_000_000); work.cancel()
 var cancelled = false
 do { _ = try await work.value } catch is CancellationError { cancelled = true }
 assert(cancelled && Date().timeIntervalSince(cancelStarted) < 1); print("PASS: cancellation interrupts an in-flight page read")

 let oversizedPage = "{\"data\":[],\"padding\":\"" + String(repeating:"x",count:241*1024*1024) + "\",\"nextCursor\":null}"
 let largeMock = try Fixture(prefix + [oversizedPage]);let largeProvider = CodexNativeSourceProvider(transport:largeMock)
 _ = try await largeProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true);_ = try await largeProvider.listThreads()
 var tooLarge = false
 do { _ = try await largeProvider.readThread(id:"synthetic") } catch CodexSourceError.responseTooLarge { tooLarge = true }
 assert(tooLarge);print("PASS: byte budget blocks capture without returning a prefix")
 let activeMock = try Fixture(Array(prefix.prefix(2)) + [#"{"thread":{"id":"synthetic","status":{"type":"active"}}}"#]);let activeProvider = CodexNativeSourceProvider(transport:activeMock)
 _ = try await activeProvider.connect(executableURL:URL(fileURLWithPath:"/synthetic"),userApproved:true);_ = try await activeProvider.listThreads()
 var activeRejected = false
 do { _ = try await activeProvider.readThread(id:"synthetic") } catch CodexSourceError.invalidResponse { activeRejected = true }
 assert(activeRejected);print("PASS: active source rejected before reading history pages")
 }
}
