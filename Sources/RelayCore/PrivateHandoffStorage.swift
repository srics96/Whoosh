import Foundation

public enum PrivateHandoffStorage {
    public static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        // Reject redirected storage, including a symlink in any existing ancestor.
        var ancestor = url
        while ancestor.path != "/" {
            if let attrs = try? fm.attributesOfItem(atPath: ancestor.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                throw RelayError.invalidInput("Whoosh storage is redirected by a symbolic link. Choose a private local location before continuing.")
            }
            ancestor.deleteLastPathComponent()
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

/// Conservative local stop signal, not a guarantee that history is free of sensitive data.
public enum SensitiveContentScreen {
    // ICU avoids Swift Regex's per-scalar case-folding cost on multi-MiB archives.
    // Keep the complete input: chunking would miss tokens/whitespace crossing a boundary.
    private static let patterns = [
        #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
        #"\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})\b"#,
        #"(?i)(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[=:]\s*[\"']?[A-Za-z0-9_+/=-]{12,}"#,
        #"(?<!\d)(?:\d[ -]?){13,18}\d(?!\d)"#
    ]
    private static let expressions = patterns.map { try? NSRegularExpression(pattern: $0) }

    /// Nonthrowing callers fail closed, including when their task was cancelled.
    public static func requiresRedaction(_ data: Data) -> Bool {
        (try? scan(data)) ?? true
    }

    /// Cancellation is an error, never a negative screening result.
    public static func scan(_ data: Data) throws -> Bool {
        try Task.checkCancellation()
        let text = String(decoding: data, as: UTF8.self)
        let range = NSRange(text.startIndex..., in: text)
        for (index, expression) in expressions.enumerated() {
            try Task.checkCancellation()
            guard let expression else { return true }
            var found = false
            expression.enumerateMatches(in: text, options: [.reportProgress], range: range) { match, flags, stop in
                if Task.isCancelled { stop.pointee = true; return }
                if flags.contains(.internalError) { found = true; stop.pointee = true; return }
                guard let match else { return }
                if index < 3 { found = true; stop.pointee = true; return }
                guard let range = Range(match.range, in: text) else { found = true; stop.pointee = true; return }
                let digits = text[range].compactMap { $0.wholeNumberValue }
                guard (14...19).contains(digits.count), Set(digits).count > 1 else { return }
                let sum = digits.reversed().enumerated().reduce(0) { sum, pair in
                    let value = pair.offset % 2 == 1 ? pair.element * 2 : pair.element
                    return sum + (value > 9 ? value - 9 : value)
                }
                if sum % 10 == 0 { found = true; stop.pointee = true }
            }
            try Task.checkCancellation()
            if found { return true }
        }
        return false
    }
}
