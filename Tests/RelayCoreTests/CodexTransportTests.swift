import XCTest
@testable import RelayCore

final class CodexTransportTests: XCTestCase {
    /// The only executable launched is this test-authored fixture. It never accesses native user state.
    func testSmallPersistentReplyAndFinalReplyBeforeEOF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Blink-Synthetic-Transport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("synthetic-codex")
        let script = #"""
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          printf '%s\n' 'codex synthetic-transport-fixture'
          exit 0
        fi
        if [ "$1" = "app-server" ] && [ "$2" = "generate-json-schema" ]; then
          printf '%s\n' '{"type":"object","properties":{"useStateDbOnly":{"type":"boolean"},"sourceKinds":{},"cursor":{},"limit":{}}}' > "$4/ThreadListParams.json"
          exit 0
        fi
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              # A short response while stdout REMAINS OPEN. Count-filling reads would time out.
              printf '%s\n' '{"id":1,"result":{"userAgent":"synthetic-test","platformOs":"synthetic"}}'
              ;;
            *'"method":"thread/list"'*|*'"method":"thread\/list"'*)
              # Deliberately split a JSON line, then exit immediately after its final bytes.
              printf '%s' '{"id":2,"result":'
              printf '%s\n' '{"data":[],"nextCursor":null}}'
              exit 0
              ;;
          esac
        done
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let transport = CodexStdioTransport(timeoutSeconds: 2)
        do {
            let version = try await transport.connect(executableURL: executable)
            XCTAssertEqual(version, "codex synthetic-transport-fixture")
            let initialized = try await transport.request(.initialize, params: [
                "clientInfo": .object(["name": .string("synthetic_test"), "version": .string("0")])
            ])
            XCTAssertEqual(initialized.result["userAgent"]?.string, "synthetic-test")
            try await transport.initialized()
            let lastReply = try await transport.request(.threadList, params: ["useStateDbOnly": .bool(true)])
            XCTAssertEqual(lastReply.result["data"], .array([]))
            XCTAssertEqual(lastReply.rawLine, Data("{\"id\":2,\"result\":{\"data\":[],\"nextCursor\":null}}\n".utf8))
            await transport.disconnect()
        } catch {
            await transport.disconnect()
            throw error
        }
    }
}
