// Compile with RelayApp sources except RelayApp.swift, plus RelayCore. Never opens a destination.
import AppKit
import RelayCore

actor SyntheticTransport: CodexReadOnlyRPCTransport {
    var slow = false
    var blocked = false
    func configure(slow: Bool = false, blocked: Bool = false) { self.slow = slow; self.blocked = blocked }
    func connect(executableURL: URL) async throws -> String { "codex-synthetic" }
    func initialized() async throws {}
    func disconnect() async {}
    func request(_ method: CodexReadMethod, params: [String: CodexJSONValue]) async throws -> CodexRPCResponse {
        let text: String
        switch method {
        case .initialize: text = #"{"userAgent":"synthetic"}"#
        case .threadList: text = #"{"data":[{"id":"synthetic","name":"Synthetic audit"}],"nextCursor":null}"#
        case .threadRead: text = #"{"thread":{"id":"synthetic","name":"Synthetic audit","status":{"type":"idle"}}}"#
        case .threadItemsList:
            if slow { try await Task.sleep(nanoseconds: 60_000_000_000) }
            text = "{\"data\":[{\"turnId\":\"t\",\"item\":{\"id\":\"u\",\"type\":\"userMessage\",\"content\":[{\"type\":\"text\",\"text\":\"\(blocked ? "password=abcdefghijkl" : "Synthetic audit request")\"}]}}],\"nextCursor\":null}"
        default: throw RelayError.invalidInput("Unexpected synthetic request")
        }
        let data = Data(text.utf8)
        return CodexRPCResponse(result: try JSONDecoder().decode(CodexJSONValue.self, from: data), rawLine: data)
    }
}

@main struct ModelSmoke {
    @MainActor static func settle(_ model: RelayModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.isBusy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(!model.isBusy, "Model failed to settle")
    }
    @MainActor static func main() async throws {
        // In-memory registration only: no persisted preferences, account access, or actual CLI discovery.
        UserDefaults.standard.register(defaults: ["blinkDesignPreview": true])
        let transport = SyntheticTransport()
        let provider = CodexNativeSourceProvider(transport: transport)
        _ = try await provider.connect(executableURL: URL(fileURLWithPath: "/synthetic"), userApproved: true)
        _ = try await provider.listThreads()
        let model = RelayModel(nativeProvider: provider)
        model.nativeConnected = true
        model.nativeThreads = [.init(id: "synthetic", title: "Synthetic audit", preview: "", directory: nil)]
        model.selectNativeThread("synthetic")
        try await settle(model)
        precondition(model.conversation != nil && !model.sensitiveContentBlocked && model.prepared == nil)
        print("PASS synthetic Codex read publishes screened context without opening/submitting a draft")

        await transport.configure(blocked: true)
        model.selectNativeThread("synthetic")
        try await settle(model)
        precondition(model.sensitiveContentBlocked && !model.canPrepare)
        model.prepare()
        precondition(model.stage == .compose && model.prepared == nil)
        print("PASS detected sensitive history cannot prepare a handoff")

        await transport.configure(slow: true)
        model.selectNativeThread("synthetic")
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(model.canCancelSourceRead)
        model.cancelSourceRead()
        try await settle(model)
        precondition(model.conversation == nil && model.prepared == nil)
        print("PASS cancelling a Codex read clears busy state and does not publish a draft")

        model.chooseSource(.claude)
        precondition(model.destination == .claude)
        model.swapApps()
        precondition(model.source == .claude && model.destination == .codex)
        model.chooseSource(.codex)
        precondition(model.destination == .codex)
        model.swapApps()
        precondition(model.source == .codex && model.destination == .claude)
        print("PASS both directions toggle destination; changing source resets same-agent default")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh-Model-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let node = ProcessInfo.processInfo.environment["WHOOSH_TEST_NODE"] ?? "/opt/homebrew/bin/node"
        precondition(FileManager.default.isExecutableFile(atPath: node), "Supply an existing Node via WHOOSH_TEST_NODE")
        try JSONSerialization.data(withJSONObject: ["node": node]).write(to: root.appendingPathComponent("runtime.json"))
        let bridge = #"""
        import {readFileSync, writeFileSync} from 'node:fs';
        const mode = readFileSync(new URL('./mode', import.meta.url), 'utf8');
        const request = JSON.parse(process.argv[2]);
        const info = {sessionId:'11111111-1111-4111-8111-111111111111',summary:'Synthetic audit',lastModified:1};
        if(request.action === 'list') console.log(JSON.stringify({sessions:[info]}));
        else if(mode === 'slow') {
          writeFileSync(new URL('./pid', import.meta.url), String(process.pid));
          setTimeout(()=>{}, 60000);
        } else console.log(JSON.stringify({info,archive:'Synthetic conversation only',notice:'Synthetic test',digest:[{role:'user',text:'Verify draft preparation'}]}));
        """#
        try bridge.write(to: root.appendingPathComponent("adapter.mjs"), atomically: false, encoding: .utf8)
        try "fast".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        let claude = RelayModel(claudeAdapter: ClaudeSessionAdapter(resourceDirectory: root))
        claude.chooseSource(.claude)
        claude.reconnectNativeCodex()
        try await settle(claude)
        precondition(claude.nativeConnected && claude.nativeThreads.count == 1)
        claude.selectNativeThread("11111111-1111-4111-8111-111111111111")
        try await settle(claude)
        precondition(claude.conversation != nil && claude.prepared == nil)
        print("PASS synthetic Claude list/read with tracked subprocess and screened context")

        try "slow".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        claude.selectNativeThread("11111111-1111-4111-8111-111111111111")
        let pidFile = root.appendingPathComponent("pid")
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: pidFile.path) && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
        precondition(claude.canCancelSourceRead)
        claude.cancelSourceRead()
        try await settle(claude)
        precondition(claude.conversation == nil && claude.prepared == nil && kill(pid, 0) == -1)
        try "fast".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        claude.selectNativeThread("11111111-1111-4111-8111-111111111111")
        try await settle(claude)
        precondition(claude.conversation != nil)
        await claude.shutdown()
        await model.shutdown()
        print("PASS Claude cancellation reaps owned helper; subsequent selection works")
    }
}
