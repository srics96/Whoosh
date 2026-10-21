import Foundation

public enum CodexSourceError: LocalizedError, Sendable {
    case consentRequired, notConnected, notListed, invalidExecutable, unsupportedCLI, responseTooLarge, timedOut, disconnected
    case invalidResponse(String)
    case remote(Int, String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .consentRequired: return "Choose Connect before Blink starts the selected Codex CLI."
        case .notConnected: return "Connect the Codex source first."
        case .notListed: return "Choose a conversation from the current Codex source list."
        case .invalidExecutable: return "Select a trusted, installed Codex CLI executable."
        case .unsupportedCLI: return "This Codex CLI does not advertise the required database-only thread listing. Update Codex, or use an explicit conversation export."
        case .responseTooLarge: return "The source response exceeded Blink's size limit. Request fewer items or use an explicit export."
        case .timedOut: return "The Codex source did not respond in time. Blink closed its own connection."
        case .disconnected: return "The Codex source connection closed."
        case .invalidResponse(let detail): return "Unsupported Codex response: \(detail)"
        case .remote(let code, let message): return "Codex source error \(code): \(String(message.prefix(300)))"
        case .launchFailed(let message): return "Could not start the selected Codex CLI: \(String(message.prefix(300)))"
        }
    }
}

public struct CodexSourceConnection: Sendable {
    public let cliVersion: String
    public let serverUserAgent: String?
    public let platformOS: String?
    public let databaseOnlyListingVerified: Bool
}

public struct CodexThreadActivity: Codable, Sendable {
    public let type: String
}

public struct CodexThreadSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let preview: String?
    public let cwd: String?
    public let modelProvider: String?
    /// Unix timestamp in seconds, as reported by app-server.
    public let updatedAt: Double?
    public let status: CodexThreadActivity?
    public var displayName: String { name?.isEmpty == false ? name! : (preview?.isEmpty == false ? String(preview!.prefix(90)) : "Untitled conversation") }
}

public struct CodexThreadPage: Sendable {
    public let threads: [CodexThreadSummary]
    public let nextCursor: String?
}

public struct CodexTranscriptMessage: Codable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let itemID: String
    public let turnID: String
    public let role: Role
    public let text: String
    public var id: String { "\(turnID)/\(itemID)" }
}

public struct CodexSelectedThread: Sendable {
    public let summary: CodexThreadSummary
    public let messages: [CodexTranscriptMessage]
    /// Exact response bytes received from app-server, including each JSONL delimiter.
    /// Contains API representations, potentially including tools/private content. Review before sharing.
    public let rawResponsesJSONL: Data
    public let isPartial: Bool
    public let nextCursor: String?
    public let preservationNotice: String
    public var renderedTranscript: String {
        messages.map { "[\($0.role.rawValue)]\n\($0.text)" }.joined(separator: "\n\n")
    }
}

public struct CodexRateLimitWindow: Codable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?
}

public struct CodexRateLimitBucket: Codable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
}

public struct CodexRateLimitsSnapshot: Sendable {
    public let capturedAt: Date
    public let buckets: [CodexRateLimitBucket]
    public let rawResponse: Data
}

/// JSON representation used by the deliberately read-only, injectable transport.
public enum CodexJSONValue: Codable, Equatable, Sendable {
    case object([String: CodexJSONValue]), array([CodexJSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(String.self) { self = .string(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else if let x = try? c.decode([String: Self].self) { self = .object(x) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> Self? { if case .object(let x) = self { return x[key] }; return nil }
    public var string: String? { if case .string(let x) = self { return x }; return nil }
    public var array: [Self]? { if case .array(let x) = self { return x }; return nil }
    public var int: Int? {
        if case .number(let x) = self, x.isFinite, x >= Double(Int.min), x < Double(Int.max), x.rounded() == x { return Int(x) }
        return nil
    }
    public func decoded<T: Decodable>(as type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}

public enum CodexReadMethod: String, Sendable {
    case initialize, threadList = "thread/list", threadRead = "thread/read"
    case threadItemsList = "thread/items/list", rateLimitsRead = "account/rateLimits/read"
}

public struct CodexRPCResponse: Sendable {
    public let result: CodexJSONValue
    public let rawLine: Data
    public init(result: CodexJSONValue, rawLine: Data) { self.result = result; self.rawLine = rawLine }
}

public protocol CodexReadOnlyRPCTransport: Sendable {
    /// Returns a CLI version string after verifying the database-only listing field in generated schemas.
    func connect(executableURL: URL) async throws -> String
    func request(_ method: CodexReadMethod, params: [String: CodexJSONValue]) async throws -> CodexRPCResponse
    func initialized() async throws
    func disconnect() async
}
