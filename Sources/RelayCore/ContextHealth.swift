import Foundation

public enum ContextAgent: String, Codable, Sendable {
    case codex, claude

    // Conservative fixed baselines for v1; these are not per-model context limits.
    public var contextBaseline: Int { self == .codex ? 272_000 : 200_000 }
}

public struct ContextChat: Hashable, Codable, Sendable {
    public let agent: ContextAgent
    public let id: UUID
    public init(agent: ContextAgent, id: UUID) { self.agent = agent; self.id = id }
}

public enum ContextBloat: String, Codable, Sendable {
    case paste, fileRead, toolOutput

    public var label: String {
        switch self {
        case .paste: return "one large paste"
        case .fileRead: return "a large file read"
        case .toolOutput: return "a long tool output"
        }
    }
}

public enum ContextAdvice: Equatable, Codable, Sendable {
    case switchToClaude(percent: Int)
    case omit(ContextBloat)
    case freshSession

    public var omission: ContextBloat? {
        if case .omit(let bloat) = self { return bloat }
        return nil
    }

    public var message: String {
        switch self {
        case .switchToClaude(let percent):
            return "Codex quota: \(percent)% used. Try Claude (quota unknown)."
        case .omit(let bloat):
            return "Start fresh without \(bloat.label)."
        case .freshSession:
            return "Start fresh with a handoff."
        }
    }
}

public struct ContextReading: Sendable {
    public let chat: ContextChat
    public let bytes: Int
    public let modifiedAt: Date
    public let active: Bool

    public init(chat: ContextChat, bytes: Int, modifiedAt: Date, active: Bool = false) {
        self.chat = chat; self.bytes = bytes; self.modifiedAt = modifiedAt; self.active = active
    }
}

public enum ContextHealth {
    public static let idle: TimeInterval = 60
    public static let grouping: TimeInterval = 5 * 60
    public static let recent: TimeInterval = 30 * 60

    public static func estimatedTokens(bytes: Int) -> Int { max(0, bytes) / 4 }

    public static func level(_ reading: ContextReading) -> Int {
        let tokens = estimatedTokens(bytes: reading.bytes)
        let baseline = reading.chat.agent.contextBaseline
        if tokens >= baseline * 85 / 100 { return 2 }
        if tokens >= baseline * 60 / 100 { return 1 }
        return 0
    }

    public static func advice(agent: ContextAgent, codexUsage: Int?, bloat: ContextBloat?) -> ContextAdvice {
        if agent == .codex, let codexUsage, (90...100).contains(codexUsage) { return .switchToClaude(percent: codexUsage) }
        if let bloat { return .omit(bloat) }
        return .freshSession
    }

    public static func codexUsage(_ snapshot: CodexRateLimitsSnapshot, now: Date) -> Int? {
        let age = now.timeIntervalSince(snapshot.capturedAt)
        guard (0...300).contains(age) else { return nil }
        return snapshot.buckets.filter { $0.limitId?.lowercased() == "codex" ||
            ($0.limitId == nil && ($0.limitName == nil || $0.limitName?.lowercased() == "codex")) }
            .flatMap { [$0.primary, $0.secondary].compactMap { $0 } }
            .compactMap { window -> Int? in
                guard let used = window.usedPercent, (0...100).contains(used),
                      let reset = window.resetsAt, reset > now.timeIntervalSince1970 else { return nil }
                return Int(used.rounded(.down))
            }.max()
    }
}

public struct ContextNudge: Codable, Sendable {
    public let chat: ContextChat
    public let level: Int
    public let estimatedTokens: Int
    public let project: String
    public let advice: ContextAdvice

    public init(reading: ContextReading, project: String, advice: ContextAdvice) {
        chat = reading.chat; level = ContextHealth.level(reading)
        estimatedTokens = ContextHealth.estimatedTokens(bytes: reading.bytes)
        self.project = project; self.advice = advice
    }
}

/// Rebuild pending groups from current observations. A chat that resumes before delivery drops out.
public struct ContextNudgePolicy {
    private struct Pending {
        let bytes: Int
        let modifiedAt: Date
        let since: Date
    }
    private struct History: Codable {
        var delivered: [ContextChat: Int] = [:]
        var snoozes = 0
        var backOffUntil: Date?
    }
    private var history: History
    private var pending: [ContextChat: Pending] = [:]

    public init(data: Data? = nil) {
        history = data.flatMap { try? JSONDecoder().decode(History.self, from: $0) } ?? History()
    }

    public var data: Data? { try? JSONEncoder().encode(history) }
    public var hasSnoozeTip: Bool { history.snoozes >= 5 }

    public mutating func eligible(_ readings: [ContextReading], now: Date) -> [ContextReading] {
        var next: [ContextChat: Pending] = [:]
        var ready: [ContextReading] = []
        for reading in readings where next[reading.chat] == nil {
            let age = now.timeIntervalSince(reading.modifiedAt)
            guard !reading.active, (ContextHealth.idle...ContextHealth.recent).contains(age),
                  ContextHealth.level(reading) > (history.delivered[reading.chat] ?? 0) else { continue }
            let existing = pending[reading.chat]
            let same = existing?.bytes == reading.bytes && existing?.modifiedAt == reading.modifiedAt
            next[reading.chat] = same ? existing : Pending(bytes: reading.bytes, modifiedAt: reading.modifiedAt, since: now)
            ready.append(reading)
        }
        pending = next
        if let until = history.backOffUntil, now < until { return [] }
        guard let first = pending.values.map(\.since).min(), now.timeIntervalSince(first) >= ContextHealth.grouping else { return [] }
        let end = first.addingTimeInterval(ContextHealth.grouping)
        return ready.filter { (pending[$0.chat]?.since ?? now) <= end }
            .sorted { ($0.modifiedAt, $0.chat.id.uuidString) > ($1.modifiedAt, $1.chat.id.uuidString) }
    }

    public mutating func delivered(_ nudges: [ContextNudge], now: Date) {
        for nudge in nudges {
            let previous = history.delivered[nudge.chat] ?? 0
            history.delivered[nudge.chat] = max(previous, nudge.level)
            pending.removeValue(forKey: nudge.chat)
        }
        if hasSnoozeTip { history.backOffUntil = now.addingTimeInterval(2 * ContextHealth.grouping) }
    }

    /// Delivery already suppresses that threshold. A snooze also contributes to global back-off.
    public mutating func snooze(now: Date) {
        history.snoozes = min(history.snoozes + 1, 5)
        if hasSnoozeTip { history.backOffUntil = now.addingTimeInterval(2 * ContextHealth.grouping) }
    }

    public mutating func acted() {
        history.snoozes = 0
        history.backOffUntil = nil
    }

    public mutating func resetPending() { pending.removeAll() }
}

public struct ContextSavings: Sendable {
    public let carried: Int
    public let original: Int
    public var saved: Int { max(0, original - carried) }

    public init(original: Int, bootstrap: String, brief: String) {
        self.original = max(0, original)
        carried = ContextHealth.estimatedTokens(bytes: bootstrap.utf8.count + brief.utf8.count)
    }

    public var message: String {
        "Carried ~\(carried.formatted()) tokens instead of ~\(original.formatted()) (estimate)."
    }
}
