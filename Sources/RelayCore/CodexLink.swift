import Foundation

public enum CodexLink {
    /// Official desktop composer route. Never submits a turn.
    public static func make(prompt: String, projectPath: String) throws -> URL {
        let encoded = try ClaudeLink.make(prompt: prompt, projectPath: projectPath)
        guard let parts = URLComponents(url: encoded, resolvingAgainstBaseURL: false),
              let q = parts.percentEncodedQuery?.components(separatedBy: "&folder=").first?.dropFirst(2),
              let folder = parts.percentEncodedQuery?.components(separatedBy: "&folder=").last,
              let url = URL(string: "codex://threads/new?prompt=\(q)&path=\(folder)") else {
            throw RelayError.invalidInput("Could not encode Codex draft link.")
        }
        return url
    }
}
