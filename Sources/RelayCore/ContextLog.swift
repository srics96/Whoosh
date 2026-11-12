import Foundation

/// A recent, local log. Routine polling only reads filesystem attributes.
public struct ContextLog: Sendable {
    public let reading: ContextReading
    public let url: URL
    public let project: String?

    private static let metadataKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
    ]

    private static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(validatingUTF8: resolved)
    }

    private static func metadata(at url: URL, chat: ContextChat, active: Bool, now: Date) -> ContextReading? {
        guard canonicalPath(url.path) == url.path,
              let values = try? url.resourceValues(forKeys: metadataKeys),
              values.isRegularFile == true, values.isSymbolicLink == false,
              let bytes = values.fileSize, let modified = values.contentModificationDate,
              (0...ContextHealth.recent).contains(now.timeIntervalSince(modified)) else { return nil }
        return ContextReading(chat: chat, bytes: bytes, modifiedAt: modified, active: active)
    }

    public static func codex(_ thread: CodexThreadSummary, root: URL, now: Date) -> ContextLog? {
        guard let rootPath = canonicalPath(root.path), let rawPath = thread.path, rawPath.hasPrefix("/"),
              let id = UUID(uuidString: thread.id) else { return nil }
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        guard let prefix = [rootPath, root.standardizedFileURL.path].first(where: { path.hasPrefix($0 + "/") }) else { return nil }
        let url = URL(fileURLWithPath: rootPath + path.dropFirst(prefix.count))
        let name = url.lastPathComponent.lowercased()
        guard name.hasPrefix("rollout-"), name.hasSuffix("-" + id.uuidString.lowercased() + ".jsonl"),
              let reading = metadata(at: url, chat: ContextChat(agent: .codex, id: id),
                                     active: thread.status?.type == "active", now: now) else { return nil }
        return ContextLog(reading: reading, url: url, project: thread.cwd.map { URL(fileURLWithPath: $0).lastPathComponent })
    }

    /// Claude's picker uses the SDK for titles and capture; the watcher skips titles and
    /// only stats UUID-named JSONL files one directory below the standard projects root.
    public static func claude(root: URL, now: Date) throws -> [ContextLog] {
        guard let rootPath = canonicalPath(root.path),
              let entries = FileManager.default.enumerator(at: URL(fileURLWithPath: rootPath), includingPropertiesForKeys: Array(metadataKeys),
                                                            options: [.skipsHiddenFiles]) else { return [] }
        var recent: [ContextLog] = []
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            guard index < 12_000, let url = entry as? URL else { break }
            guard entries.level == 2 else { continue }
            entries.skipDescendants()
            guard url.pathExtension == "jsonl", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  (0...ContextHealth.recent).contains(now.timeIntervalSince(modified)),
                  let reading = metadata(at: url, chat: ContextChat(agent: .claude, id: id),
                                         active: false, now: now),
                  ContextHealth.level(reading) > 0 else { continue }
            recent.append(ContextLog(reading: reading, url: url, project: nil))
        }
        return Array(recent.sorted { $0.reading.modifiedAt > $1.reading.modifiedAt }.prefix(25))
    }

    /// Only called on an eligible chat immediately before delivery. One capped prefix
    /// per chat, no retained message content, no SDK capture. Unrecognized formats fall back.
    public func inspect() -> (bloat: ContextBloat?, project: String?)? {
        // O_NOFOLLOW + O_NONBLOCK avoids following a swapped final symlink or waiting on a FIFO.
        guard Self.canonicalPath(url.path) == url.path else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard unchanged(descriptor) else { return nil }
        let sample = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        guard unchanged(descriptor) else { return nil }
        return Self.classify(sample, totalBytes: reading.bytes, project: project)
    }

    public func isUnchanged() -> Bool {
        guard Self.canonicalPath(url.path) == url.path else { return false }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return false }
        defer { _ = close(descriptor) }
        return unchanged(descriptor)
    }

    private func unchanged(_ descriptor: Int32) -> Bool {
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_size == reading.bytes else { return false }
        #if os(macOS)
        let time = attributes.st_mtimespec
        #else
        let time = attributes.st_mtim
        #endif
        let seconds = Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
        return abs(seconds - reading.modifiedAt.timeIntervalSince1970) < 0.000_002
    }

    public static func classify(_ sample: Data, totalBytes: Int, project: String? = nil) -> (bloat: ContextBloat?, project: String?) {
        var project = project
        var bloat: ContextBloat?
        guard let end = sample.lastIndex(of: 10) else { return (nil, project) }
        for line in sample[..<end].split(separator: 10) {
            guard project == nil || line.count > totalBytes / 2,
                  let record = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            let payload = record["payload"] as? [String: Any] ?? [:]
            if project == nil, let cwd = (record["cwd"] ?? payload["cwd"]) as? String, cwd.hasPrefix("/") {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            guard line.count > totalBytes / 2 else { continue }
            let message = record["message"] as? [String: Any] ?? payload
            if let blocks = message["content"] as? [[String: Any]] {
                if blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                    let tool = record["toolUseResult"] as? [String: Any]
                    bloat = tool?["file"] != nil ? .fileRead : .toolOutput
                } else if (message["role"] ?? record["type"]) as? String == "user",
                          blocks.contains(where: { block in
                              ["text", "input_text"].contains(block["type"] as? String ?? "") &&
                                  isLargePaste(block["text"] as? String ?? "", minimumBytes: totalBytes / 4)
                          }) {
                    bloat = .paste
                }
            } else if ["function_call_output", "custom_tool_call_output"].contains(payload["type"] as? String ?? "") {
                bloat = .toolOutput
            } else if (message["role"] ?? record["type"]) as? String == "user",
                      isLargePaste(message["content"] as? String ?? "", minimumBytes: totalBytes / 4) {
                bloat = .paste
            }
        }
        return (bloat, project)
    }

    public static func isLargePaste(_ text: String, minimumBytes: Int) -> Bool {
        text.utf8.count >= max(16_384, minimumBytes) && text.utf8.lazy.filter { $0 == 10 }.prefix(100).count == 100
    }
}
