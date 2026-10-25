// Compile with RelayApp sources except RelayApp.swift, plus RelayCore. Never opens a destination.
import AppKit
import RelayCore

actor SyntheticTransport: CodexReadOnlyRPCTransport {
    var slow = false
    var blocked = false
    var listNames = ["synthetic"]
    var listDelay: UInt64 = 0
    var listFailure = false
    var listRequests = 0
    var historyRequests = 0
    func configureList(_ names: [String], delay: UInt64 = 0, fail: Bool = false) {
        listNames = names; listDelay = delay; listFailure = fail
    }
    func counts() -> (Int, Int) { (listRequests, historyRequests) }
    func configure(slow: Bool = false, blocked: Bool = false) { self.slow = slow; self.blocked = blocked }
    func connect(executableURL: URL) async throws -> String { "codex-synthetic" }
    func initialized() async throws {}
    func disconnect() async {}
    func request(_ method: CodexReadMethod, params: [String: CodexJSONValue]) async throws -> CodexRPCResponse {
        let text: String
        switch method {
        case .initialize: text = #"{"userAgent":"synthetic"}"#
        case .threadList:
            listRequests += 1
            if listDelay > 0 { try await Task.sleep(nanoseconds: listDelay) }
            if listFailure { throw RelayError.invalidInput("Synthetic list failure") }
            let data = try JSONSerialization.data(withJSONObject: ["data": listNames.map { ["id": $0, "name": $0] }, "nextCursor": NSNull()])
            text = String(decoding: data, as: UTF8.self)
        case .threadRead:
            historyRequests += 1
            text = #"{"thread":{"id":"synthetic","name":"Synthetic audit","status":{"type":"idle"}}}"#
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
        model.nativeNextCursor = "old-page"
        model.nativeSearch = "synthetic"
        model.highlightedID = "synthetic"
        await transport.configureList(["synthetic", "new-chat", "new-chat"], delay: 20_000_000)
        model.refreshForPresentation()
        model.refreshForPresentation() // coalesced while busy
        try await settle(model)
        let counts = await transport.counts()
        precondition(counts.0 == 2 && counts.1 == 0)
        precondition(model.nativeThreads.map(\.id) == ["synthetic", "new-chat"])
        precondition(model.nativeNextCursor == nil && model.nativeSearch == "synthetic" && model.highlightedID == "synthetic")
        await transport.configureList([], fail: true)
        model.refreshConversations()
        try await settle(model)
        precondition(model.nativeThreads.count == 2 && model.errorMessage?.contains("Cached") == true)
        await transport.configureList(["stale"], delay: 60_000_000_000)
        model.refreshConversations()
        try await Task.sleep(nanoseconds: 20_000_000)
        model.cancelSourceRead()
        try await settle(model)
        precondition(model.nativeThreads.count == 2 && model.nativeSearch == "synthetic")
        model.nativeConnected = true
        await transport.configureList(["stale"], delay: 20_000_000)
        model.refreshConversations()
        model.source = .claude
        model.source = .codex // returning to the same source must not accept an old generation
        try await settle(model)
        precondition(model.nativeThreads.isEmpty)
        model.source = .codex
        model.nativeConnected = true
        model.nativeThreads = [.init(id: "synthetic", title: "Synthetic audit", preview: "", directory: nil)]
        model.nativeSearch = ""
        await transport.configureList(["synthetic"])
        print("PASS reopen refresh lists new chats once, deduplicates, resets pagination, preserves query, handles error/cancel and ignores stale-source results")
        model.selectNativeThread("synthetic")
        try await settle(model)
        precondition(model.conversation != nil && !model.sensitiveContentBlocked && model.prepared == nil)
        precondition(model.projectURL == nil && !model.canPrepare)
        let selectedCounts = await transport.counts()
        model.refreshForPresentation()
        let unchangedCounts = await transport.counts()
        precondition(selectedCounts.0 == unchangedCounts.0 && model.conversation != nil)
        precondition(model.errorMessage?.contains("missing") == true)
        print("PASS missing Codex cwd blocks preparation without home fallback")
        model.nativeBusy = true; model.selectingThread = nil
        precondition(model.sourceProgressTitle.contains("Finding"))
        model.selectingThread = model.nativeThreads[0]
        precondition(model.sourceProgressTitle.contains("Reading"))
        model.nativeBusy = false
        precondition(model.destinationSurface == .desktop)
        model.destinationSurface = .terminal
        precondition(model.stage == .compose && model.prepared == nil)
        model.destinationSurface = .desktop
        print("PASS discovery/read phases distinguished; desktop default and explicit terminal selection")
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

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-audit/Whoosh-Model-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let terminal = RelayModel()
        terminal.destinationSurface = .terminal
        terminal.projectURL = root
        terminal.outputURL = root.appendingPathComponent("handoffs")
        terminal.conversation = try ImportedConversation(fileName: "synthetic.txt", data: Data("Fictional marker TERMINAL-42".utf8))
        terminal.goal = "Recover the fictional marker"
        terminal.nextStep = "Review the archive"
        terminal.sourceStopped = true
        var opened = false
        terminal.onDestinationOpened = { opened = true }
        for agent in RelayModel.AgentApp.allCases {
            terminal.destination = agent
            terminal.sourceStopped = true
            terminal.prepare(continueToDestination: true)
            try await settle(terminal)
            guard terminal.stage == .review && terminal.prepared != nil && !opened else { throw RelayError.invalidInput("Terminal preparation failed: " + (terminal.errorMessage ?? String(describing: terminal.stage))) }
            let archive = terminal.prepared!.directory.appendingPathComponent(terminal.prepared!.manifest.archiveRelativePath)
            let data = try Data(contentsOf: archive)
            precondition(SHA256.hexDigest(data) == terminal.prepared!.manifest.sha256)
            print("PASS \(agent.rawValue) terminal preparation preserves archive and never auto-launches/submits")
            terminal.invalidate()
        }
        let vanished = root.appendingPathComponent("vanished")
        terminal.projectURL = vanished
        terminal.prepare(continueToDestination: true)
        try await settle(terminal)
        precondition(terminal.stage == .compose && terminal.prepared == nil && terminal.errorMessage != nil)
        print("PASS disappearing project fails safely during preparation")
        await terminal.shutdown()
        let node = ProcessInfo.processInfo.environment["WHOOSH_TEST_NODE"] ?? "/opt/homebrew/bin/node"
        precondition(FileManager.default.isExecutableFile(atPath: node), "Supply an existing Node via WHOOSH_TEST_NODE")
        try JSONSerialization.data(withJSONObject: ["node": node]).write(to: root.appendingPathComponent("runtime.json"))
        let bridge = #"""
        import {readFileSync, writeFileSync} from 'node:fs';
        const mode = readFileSync(new URL('./mode', import.meta.url), 'utf8');
        const request = JSON.parse(process.argv[2]);
        const info = {sessionId:'11111111-1111-4111-8111-111111111111',summary:'Synthetic audit',lastModified:1};
        if(request.action === 'list') {
          if(mode === 'list-fail') throw Error('Synthetic list failure');
          const sessions = mode === 'new-list' ? [info, {...info,sessionId:'22222222-2222-4222-8222-222222222222',summary:'New desktop test'}] : [info];
          console.log(JSON.stringify({sessions}));
        }
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
        try "new-list".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        claude.nativeNextCursor = "50"
        claude.nativeSearch = "New desktop"
        claude.refreshForPresentation()
        try await settle(claude)
        precondition(claude.nativeThreads.count == 2 && claude.nativeNextCursor == nil && claude.nativeSearch == "New desktop")
        precondition(claude.conversation == nil)
        try "list-fail".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        claude.refreshConversations()
        try await settle(claude)
        precondition(claude.nativeThreads.count == 2 && claude.errorMessage?.contains("Cached") == true)
        try "fast".write(to: root.appendingPathComponent("mode"), atomically: false, encoding: .utf8)
        print("PASS Claude reopen refresh discovers new session metadata; failed refresh retains cached rows")
        claude.selectNativeThread("11111111-1111-4111-8111-111111111111")
        try await settle(claude)
        precondition(claude.conversation != nil && claude.prepared == nil)
        precondition(claude.projectURL == nil && !claude.canPrepare)
        precondition(claude.errorMessage?.contains("missing") == true)
        print("PASS missing Claude cwd blocks preparation without home fallback")
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
