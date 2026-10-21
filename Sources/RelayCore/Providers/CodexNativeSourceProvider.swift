import Foundation

/// An opt-in source adapter. It never resumes, starts, writes, or subscribes to a conversation.
/// There is no claim that a separately launched CLI can see every desktop/cloud conversation.
public actor CodexNativeSourceProvider {
    private let transport: any CodexReadOnlyRPCTransport
    private var connected = false
    private var generation = UUID()
    private var listedIDs = Set<String>()
    private let maximumArchiveBytes = 32 * 1024 * 1024

    public init(transport: any CodexReadOnlyRPCTransport = CodexStdioTransport()) { self.transport = transport }

    public func connect(executableURL: URL, userApproved: Bool) async throws -> CodexSourceConnection {
        guard userApproved else { throw CodexSourceError.consentRequired }
        await disconnect()
        let session = UUID()
        generation = session
        do {
            let version = try await transport.connect(executableURL: executableURL)
            try checkGeneration(session)
            let response = try await transport.request(.initialize, params: [
                "clientInfo": .object(["name": .string("blink_handoff"), "title": .string("Blink"), "version": .string("0.1.0")]),
                "capabilities": .object(["experimentalApi": .bool(false)])
            ])
            try checkGeneration(session)
            try await transport.initialized()
            try checkGeneration(session)
            connected = true
            return CodexSourceConnection(cliVersion: version, serverUserAgent: response.result["userAgent"]?.string,
                                         platformOS: response.result["platformOs"]?.string, databaseOnlyListingVerified: true)
        } catch {
            if generation == session { await disconnect() }
            throw error
        }
    }

    public func disconnect() async {
        generation = UUID()
        connected = false
        listedIDs.removeAll()
        await transport.disconnect()
    }

    public func listThreads(cursor: String? = nil, limit: Int = 25) async throws -> CodexThreadPage {
        let session = try requireConnection()
        var params: [String: CodexJSONValue] = [
            "limit": .number(Double(min(max(limit, 1), 100))),
            "sortKey": .string("updated_at"), "sortDirection": .string("desc"),
            "archived": .bool(false), "useStateDbOnly": .bool(true),
            // Omission would default to only CLI and VS Code. Do not guess a "desktop" source kind.
            "sourceKinds": .array(["cli", "vscode", "appServer", "exec"].map(CodexJSONValue.string))
        ]
        if let cursor { params["cursor"] = .string(cursor) }
        let response = try await transport.request(.threadList, params: params)
        try checkGeneration(session)
        guard let rows = response.result["data"]?.array else { throw CodexSourceError.invalidResponse("missing thread list") }
        let threads = try rows.map { try $0.decoded(as: CodexThreadSummary.self) }
        listedIDs.formUnion(threads.map(\.id))
        return CodexThreadPage(threads: threads, nextCursor: response.result["nextCursor"]?.string)
    }

    /// Reads only an ID explicitly returned by this connection's picker. Bounded, oldest-first pages.
    /// A partial result MUST remain visibly marked partial in the calling UI and archive manifest.
    public func readThread(id: String, maxPages: Int? = nil, pageSize: Int = 100, timeBudgetSeconds: Double = 60) async throws -> CodexSelectedThread {
        let session = try requireConnection()
        guard listedIDs.contains(id) else { throw CodexSourceError.notListed }
        let deadline = Date().addingTimeInterval(timeBudgetSeconds.isFinite ? max(0, min(timeBudgetSeconds, 60)) : 60)
        try Task.checkCancellation()
        let metadata = try await boundedRequest(.threadRead, deadline: deadline, params: ["threadId": .string(id), "includeTurns": .bool(false)])
        try checkGeneration(session)
        guard let thread = metadata.result["thread"] else { throw CodexSourceError.invalidResponse("missing thread metadata") }
        let summary = try thread.decoded(as: CodexThreadSummary.self)
        guard summary.id == id else { throw CodexSourceError.invalidResponse("thread ID did not match selection") }
        guard summary.status?.type != "active" else { throw CodexSourceError.invalidResponse("The selected source is active. Stop it before capturing history.") }
        // thread/items/list returns full persisted items across every turn when turnId is omitted.
        // Unlike thread/turns/list it has no default summary view. Follow every cursor or mark partial.
        var raw = metadata.rawLine
        var messages: [CodexTranscriptMessage] = []
        var nextCursor: String?
        var seenCursors = Set<String>()
        var seenItems = Set<String>()
        var pages = 0
        while true {
            try Task.checkCancellation()
            pages += 1
            var params: [String: CodexJSONValue] = [
                "threadId": .string(id), "sortDirection": .string("asc"), "limit": .number(Double(min(max(pageSize, 1), 100)))
            ]
            if let nextCursor { params["cursor"] = .string(nextCursor) }
            let response = try await boundedRequest(.threadItemsList, deadline: deadline, params: params)
            try checkGeneration(session)
            guard raw.count + response.rawLine.count <= maximumArchiveBytes else { throw CodexSourceError.responseTooLarge }
            raw.append(response.rawLine)
            guard let entries = response.result["data"]?.array else { throw CodexSourceError.invalidResponse("missing item page") }
            for entry in entries {
                guard let item = entry["item"], let itemID = item["id"]?.string,
                      let turnID = entry["turnId"]?.string, let kind = item["type"]?.string else { continue }
                let identity = "\(turnID)/\(itemID)"
                guard seenItems.insert(identity).inserted else { continue }
                if kind == "agentMessage", let text = item["text"]?.string {
                    messages.append(CodexTranscriptMessage(itemID: itemID, turnID: turnID, role: .assistant, text: text))
                } else if kind == "userMessage", let content = item["content"]?.array {
                    let text = content.compactMap { part -> String? in
                        guard part["type"]?.string == "text" else { return nil }
                        return part["text"]?.string
                    }.joined(separator: "\n")
                    if !text.isEmpty { messages.append(CodexTranscriptMessage(itemID: itemID, turnID: turnID, role: .user, text: text)) }
                }
            }
            nextCursor = response.result["nextCursor"]?.string
            guard let cursor = nextCursor else { break }
            guard seenCursors.insert(cursor).inserted else { throw CodexSourceError.invalidResponse("repeated pagination cursor") }
            if let maxPages, pages >= max(1, maxPages) { break }
        }
        return CodexSelectedThread(summary: summary, messages: messages, rawResponsesJSONL: raw,
                                   isPartial: nextCursor != nil, nextCursor: nextCursor,
                                   preservationNotice: "Exact bytes of the fetched Codex API responses, not the original native conversation store. The readable transcript includes user and assistant text only; attachments, tool records and internal native state may be omitted.\(nextCursor != nil ? " History is partial because the page limit was reached. Capture starts with the oldest items; newer conversation items may be missing." : "")")
    }

    private func boundedRequest(_ method: CodexReadMethod, deadline: Date, params: [String:CodexJSONValue]) async throws -> CodexRPCResponse {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw CodexSourceError.invalidResponse("Full history capture exceeded 60 seconds. No continuation was prepared. Try again when the source is idle or use a complete explicit export.") }
        let transport = self.transport
        return try await withThrowingTaskGroup(of: CodexRPCResponse.self) { group in
            group.addTask { try await transport.request(method, params: params) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                throw CodexSourceError.invalidResponse("Full history capture exceeded its time budget. No continuation was prepared. Reconnect and try again, or use a complete explicit export.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Call only from a user-requested usage refresh. No login, token extraction, reset, or billing action.
    public func readRateLimits() async throws -> CodexRateLimitsSnapshot {
        let session = try requireConnection()
        let response = try await transport.request(.rateLimitsRead, params: [:])
        try checkGeneration(session)
        var buckets: [CodexRateLimitBucket] = []
        if let allValue = response.result["rateLimitsByLimitId"], case .object(let all) = allValue {
            buckets = try all.keys.sorted().compactMap { try all[$0]?.decoded(as: CodexRateLimitBucket.self) }
        } else if let single = response.result["rateLimits"], single != .null {
            buckets = [try single.decoded(as: CodexRateLimitBucket.self)]
        }
        return CodexRateLimitsSnapshot(capturedAt: Date(), buckets: buckets, rawResponse: response.rawLine)
    }

    private func requireConnection() throws -> UUID {
        guard connected else { throw CodexSourceError.notConnected }
        return generation
    }
    private func checkGeneration(_ expected: UUID) throws {
        guard generation == expected else { throw CodexSourceError.disconnected }
    }
}
