import Foundation
import Security

/// Read-only discovery. No PATH search and no candidate is executed during detection.
enum CodexInstallation {
    static func verified(_ candidate: URL) -> URL? {
        let url = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\" and identifier \"codex\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code, let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
        return url
    }
    static func detect() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [home.appendingPathComponent(".local/bin/codex"),
                          home.appendingPathComponent(".codex/packages/standalone/current/bin/codex")]
        if let saved = UserDefaults.standard.string(forKey: "blinkChosenCLI") {
            candidates.insert(URL(fileURLWithPath: saved), at: 0)
        }
        return candidates.lazy.compactMap { verified($0) }.first
    }
}
