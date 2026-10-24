import Foundation

public enum RelayError: LocalizedError, Equatable {
    case invalidInput(String)
    case processFailed(String)
    case promptTooLong(Int)
    case archiveMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let reason), .processFailed(let reason): return reason
        case .promptTooLong(let count): return "The bootstrap is \(count) UTF-16 units. Shorten the checkpoint to keep it below 12,000; Whoosh never silently truncates it."
        case .archiveMismatch: return "The saved transcript did not match the original bytes. No handoff was opened."
        }
    }
}

public struct Checkpoint: Codable, Equatable, Sendable {
    public var sourceName: String
    public var goal: String
    public var decisions: String
    public var nextStep: String
    public var verification: String
    public var sourceSessionStopped: Bool

    public init(sourceName: String, goal: String, decisions: String, nextStep: String,
                verification: String, sourceSessionStopped: Bool) {
        self.sourceName = sourceName; self.goal = goal; self.decisions = decisions
        self.nextStep = nextStep; self.verification = verification
        self.sourceSessionStopped = sourceSessionStopped
    }

    public func validate() throws {
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalidInput("Add a goal and an exact next step before preparing a handoff.")
        }
        guard sourceSessionStopped else {
            throw RelayError.invalidInput("Confirm that you stopped the source agent before creating this checkpoint.")
        }
    }
}

public struct ImportedConversation: Sendable {
    public static let maximumBytes = 256 * 1024 * 1024
    public let fileName: String
    public let data: Data
    public let sha256: String
    public let preservationNotice: String
    public let isPartial: Bool
    public var byteCount: Int { data.count }
    public var utf8CharacterCount: Int? { String(data: data, encoding: .utf8)?.count }
    public var preview: String {
        guard let text = String(data: data.prefix(32_768), encoding: .utf8) else {
            return "Preview unavailable for these bytes. The archive will still be preserved exactly."
        }
        return String(text.prefix(4_000))
    }

    public init(fileName: String, data: Data,
                preservationNotice: String = "Exact bytes of the user-selected export. Completeness of the original conversation is not verified.",
                isPartial: Bool = false) throws {
        guard ["txt", "md", "json", "jsonl"].contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()) else {
            throw RelayError.invalidInput("Choose an exported .txt, .md or .json conversation.")
        }
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw RelayError.invalidInput("Choose a nonempty conversation export smaller than 256 MiB.")
        }
        self.fileName = URL(fileURLWithPath: fileName).lastPathComponent
        self.data = data
        self.sha256 = try SHA256.hexDigestCheckingCancellation(data)
        self.preservationNotice = preservationNotice
        self.isPartial = isPartial
    }

    public static func readSelectedFile(_ url: URL) throws -> Self {
        guard ["txt", "md", "json"].contains(url.pathExtension.lowercased()) else {
            throw RelayError.invalidInput("Choose an exported .txt, .md or .json conversation.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw RelayError.invalidInput("Select a regular exported conversation file, not a link or folder, smaller than 256 MiB.")
        }
        return try Self(fileName: url.lastPathComponent, data: Data(contentsOf: url))
    }
}

public struct GitSnapshot: Codable, Equatable, Sendable {
    public var available: Bool
    public var branch: String?
    public var commit: String?
    public var repositoryRoot: String?
    public var status: String?
    public var trackedDiff: String?
    public var note: String
    public var capturedAt: Date

    public init(available: Bool, branch: String? = nil, commit: String? = nil,
                repositoryRoot: String? = nil, status: String? = nil, trackedDiff: String? = nil,
                note: String, capturedAt: Date = Date()) {
        self.available = available; self.branch = branch; self.commit = commit
        self.repositoryRoot = repositoryRoot; self.status = status; self.trackedDiff = trackedDiff
        self.note = note; self.capturedAt = capturedAt
    }
}

public struct ArchiveManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let source: String
    public let originalFileName: String
    public let archiveRelativePath: String
    public let byteCount: Int
    public let utf8CharacterCount: Int?
    public let sha256: String
    public let preservation: String
    public let sourceIsPartial: Bool
    public let projectPath: String
    public let checkpoint: Checkpoint
    public let gitSnapshot: GitSnapshot
    public let bootstrapUTF16Count: Int
    public let nativeConversationImported: Bool
    public let destinationReadVerified: Bool
    public let liveQuota: String
}

public struct PreparedHandoff: Sendable {
    public let directory: URL
    public let bootstrap: String
    public let deepLink: URL
    public let manifest: ArchiveManifest
}
