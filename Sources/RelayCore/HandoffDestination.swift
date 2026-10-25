import Foundation

/// Source metadata must never silently broaden the destination's filesystem scope.
public enum ProjectFolder {
    public static func available(_ path: String?) -> URL? {
        guard let path, !path.isEmpty, !path.contains("\0"),
              (path as NSString).isAbsolutePath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return url
    }

    public static func require(_ url: URL) throws {
        guard url.isFileURL, available(url.path) != nil else {
            throw RelayError.invalidInput("The project folder is unavailable. Choose an existing folder before continuing.")
        }
    }
}

/// Assisted terminal handoff: launch an EMPTY interactive session, then paste the
/// separately reviewed bootstrap. Never pass transcript text as a shell command or startup prompt.
public enum TerminalHandoff {
    public enum Agent: String { case claude, codex }
    public static func launchCommand(agent: Agent, projectURL: URL) throws -> String {
        try ProjectFolder.require(projectURL)
        // Reject control characters so the clipboard command is a single reviewable line.
        guard !projectURL.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw RelayError.invalidInput("This folder name cannot be represented safely in a terminal command.")
        }
        let quoted = "'" + projectURL.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        return "cd -- " + quoted + " && command " + agent.rawValue
    }
}
