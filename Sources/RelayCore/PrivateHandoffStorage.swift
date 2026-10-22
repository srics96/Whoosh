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
    public static func requiresRedaction(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            #"\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16})\b"#,
            #"(?i)(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[=:]\s*[\"']?[A-Za-z0-9_+/=-]{12,}"#
        ]
        if patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { return true }
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ -]?){13,18}\d(?!\d)"#) else { return true }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let digits = text[range].compactMap { $0.wholeNumberValue }
            guard (14...19).contains(digits.count), Set(digits).count > 1 else { continue }
            let sum = digits.reversed().enumerated().reduce(0) { sum, pair in
                let value = pair.offset % 2 == 1 ? pair.element * 2 : pair.element
                return sum + (value > 9 ? value - 9 : value)
            }
            if sum % 10 == 0 { return true }
        }
        return false
    }
}
