import Foundation

public enum ClaudeLink {
    /// Conservative UTF-16 budget below the documented approximate 14k-character truncation point.
    public static let maximumPromptUnits = 12_000

    public static func make(prompt: String, projectPath: String) throws -> URL {
        guard (projectPath as NSString).isAbsolutePath,
              !projectPath.contains("\0"), !projectPath.isEmpty else {
            throw RelayError.invalidInput("Choose an absolute local project folder.")
        }
        guard prompt.utf16.count <= maximumPromptUnits else {
            throw RelayError.promptTooLong(prompt.utf16.count)
        }
        guard !prompt.isEmpty else { throw RelayError.invalidInput("The bootstrap cannot be empty.") }
        // Encode every parameter independently. In particular, encode &, #, +, ?, %, and slashes.
        // URLQueryItem alone leaves '+' intact, which some query decoders interpret as a space.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let q = prompt.addingPercentEncoding(withAllowedCharacters: allowed),
              let folder = projectPath.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "claude://code/new?q=\(q)&folder=\(folder)") else {
            throw RelayError.invalidInput("Could not encode this handoff link.")
        }
        return url
    }
}
