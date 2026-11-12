import Foundation
@testable import RelayCore

@main
enum ContextHealthSmoke {
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        if !condition() { fatalError(reason) }
    }

    static func main() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let claude = ContextChat(agent: .claude, id: UUID())
        let codex = ContextChat(agent: .codex, id: UUID())
        func reading(_ chat: ContextChat, _ percentage: Int, _ age: TimeInterval, active: Bool = false) -> ContextReading {
            ContextReading(chat: chat, bytes: chat.agent.contextBaseline * 4 * percentage / 100, modifiedAt: now - age, active: active)
        }
        let a = reading(claude, 60, 60), b = reading(codex, 70, -120)
        check(ContextHealth.level(reading(claude, 59, 100)) == 0, "Below threshold")
        check(ContextHealth.level(a) == 1, "Lower boundary")
        check(ContextHealth.level(reading(codex, 85, 60)) == 2, "Upper boundary")
        var policy = ContextNudgePolicy()
        check(policy.eligible([reading(claude, 90, 59), reading(codex, 90, 90, active: true)], now: now).isEmpty, "Mid-flow")
        check(policy.eligible([a], now: now).isEmpty, "Wait for grouping")
        check(policy.eligible([a, b], now: now + 180).isEmpty, "Second chat eligible in same window")
        check(policy.eligible([a, b], now: now + 299).isEmpty, "Do not deliver before window ends")
        let group = policy.eligible([a, b], now: now + 300)
        check(Set(group.map(\.chat)) == [claude, codex], "Group across agents")
        policy.delivered(group.map { ContextNudge(reading: $0, project: "Synthetic", advice: .freshSession) }, now: now + 300)
        policy = ContextNudgePolicy(data: policy.data)
        check(policy.eligible([a, b], now: now + 620).isEmpty, "Persistence prevents duplicates")
        for _ in 0..<4 { policy.snooze(now: now + 340) }
        check(!policy.hasSnoozeTip, "Four snoozes do not back off")
        policy.snooze(now: now + 340)
        let higher = reading(claude, 85, -300)
        check(policy.eligible([higher], now: now + 400).isEmpty, "Second threshold waits")
        check(policy.eligible([higher], now: now + 939).isEmpty, "Five snoozes double the wait")
        check(policy.eligible([higher], now: now + 940).map(\.chat) == [claude], "Higher threshold still eligible")
        policy.acted()
        check(!policy.hasSnoozeTip, "Action resets the streak")
        var resumed = ContextNudgePolicy()
        _ = resumed.eligible([a], now: now)
        check(resumed.eligible([reading(claude, 70, -295)], now: now + 300).isEmpty, "Resumed chat drops out")
        check(resumed.eligible([reading(claude, 70, -295)], now: now + 360).isEmpty, "New idle starts a fresh group")
        check(ContextHealth.advice(agent: .codex, codexUsage: 90, bloat: .paste) == .switchToClaude(percent: 90), "Codex quota wins")
        check(ContextHealth.advice(agent: .codex, codexUsage: nil, bloat: .paste) == .omit(.paste), "Unknown quota uses bloat")
        check(ContextHealth.advice(agent: .claude, codexUsage: 98, bloat: nil) == .freshSession, "Never infer Claude quota")
        let savings = ContextSavings(original: 120_000, bootstrap: "abcd", brief: "abcdefgh")
        check(savings.carried == 3 && savings.saved == 119_997, "Count brief and bootstrap only")
        check(ContextSavings(original: 1, bootstrap: "abcdefgh", brief: "").saved == 0, "No negative savings")
        try logChecks(now: now, claude: claude, codex: codex)
        try quotaChecks(now: now)
        print("Context policy: idle, grouping, thresholds, snooze, priority and estimates passed.")
    }

    static func quotaChecks(now: Date) throws {
        let buckets = try JSONDecoder().decode([CodexRateLimitBucket].self, from: Data("""
        [{"limitId":"other","primary":{"usedPercent":100,"resetsAt":12000}},
         {"limitId":"codex","primary":{"usedPercent":99,"resetsAt":9999},"secondary":{"usedPercent":90,"resetsAt":20000}}]
        """.utf8))
        let snapshot = CodexRateLimitsSnapshot(capturedAt: now, buckets: buckets, rawResponse: Data())
        check(ContextHealth.codexUsage(snapshot, now: now) == 90, "Ignore other buckets and expired windows")
        check(ContextHealth.codexUsage(snapshot, now: now + 301) == nil, "Stale quotas are unknown")
    }

    static func logChecks(now: Date, claude: ContextChat, codex: ContextChat) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Whoosh-Context-Test-" + UUID().uuidString).resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        let paste = String(repeating: "log line " + String(repeating: "x", count: 168) + "\n", count: 3_000)
        let message: [String: Any] = ["type":"user", "cwd":"/tmp/FixtureProject",
            "message": ["role":"user", "content":[["type":"text", "text":paste]]]]
        func line(_ record: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: record) + Data([10])
        }
        let pasteBytes = try line(message)
        let file = project.appendingPathComponent(claude.id.uuidString + ".jsonl")
        try pasteBytes.write(to: file)
        try fm.setAttributes([.modificationDate: now - 61], ofItemAtPath: file.path)
        let link = project.appendingPathComponent(UUID().uuidString + ".jsonl")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        let nested = project.appendingPathComponent("subagents")
        try fm.createDirectory(at: nested, withIntermediateDirectories: false)
        try pasteBytes.write(to: nested.appendingPathComponent(UUID().uuidString + ".jsonl"))
        let discovered = try ContextLog.claude(root: root, now: now)
        check(discovered.map { $0.reading.chat } == [claude], "Only top-level Claude session files")
        check(discovered.first?.inspect()?.bloat == .paste, "Detect large early paste from bounded sample")
        check(discovered.first?.inspect()?.project == "FixtureProject", "Derive label without retaining message text")
        check(ContextLog.classify(Data(pasteBytes.dropLast()), totalBytes: pasteBytes.count).bloat == nil, "Incomplete sample falls back")
        check(ContextLog.classify(pasteBytes, totalBytes: pasteBytes.count * 3).bloat == nil, "Large but not dominant")
        let toolBytes = try line(["type":"user", "message":["content":[["type":"tool_result","content":paste]]], "toolUseResult":["file":["content":paste]]])
        check(ContextLog.classify(toolBytes, totalBytes: toolBytes.count).bloat == .fileRead, "Claude file read advice")
        let rollout = project.appendingPathComponent("rollout-fixture-" + codex.id.uuidString.lowercased() + ".jsonl")
        let rolloutBytes = try line(["type":"response_item","payload":["type":"function_call_output","output":paste]])
        try rolloutBytes.write(to: rollout)
        try fm.setAttributes([.modificationDate: now - 61], ofItemAtPath: rollout.path)
        let thread = try JSONDecoder().decode(CodexThreadSummary.self, from:
            JSONSerialization.data(withJSONObject: ["id":codex.id.uuidString, "path":rollout.path, "status":["type":"idle"]]))
        let codexLog = ContextLog.codex(thread, root: root, now: now)
        check(codexLog?.inspect()?.bloat == .toolOutput, "Codex tool output advice")
        check(ContextLog.codex(thread, root: nested, now: now) == nil, "Reject rollout paths outside root")
        try (pasteBytes + Data([10])).write(to: file)
        check(discovered.first?.inspect() == nil, "Never act on a changed file")
        let digest = ResumeDigest(title: "Synthetic", messages: [
            ResumeMessage(role: "user", text: "Fix the build"),
            ResumeMessage(role: "assistant", text: "Decision: Keep the v1 file format."),
            ResumeMessage(role: "user", text: paste)
        ] + (1...8).map { ResumeMessage(role: "assistant", text: "Update \($0)") },
            omission: .paste, sourceBytes: pasteBytes.count)
        check(digest.brief.contains("Decision: Keep the v1 file format."), "Older decision remains visible for review")
        check(digest.brief.contains("skips one large paste") && !digest.brief.contains("log line"), "Omit dominant paste from compact brief")
        print("Context sources: read-only discovery, prefix bounds, stale files, paste/tool/file advice and old decisions passed.")
    }
}
