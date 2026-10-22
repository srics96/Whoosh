import Foundation
import Security
import AppKit

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
        var candidates: [URL] = []
        if let saved = UserDefaults.standard.string(forKey: "blinkChosenCLI") {
            candidates.append(URL(fileURLWithPath: saved))
        }
        candidates += [
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".codex/packages/standalone/current/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        // The Codex / ChatGPT desktop app bundles the signed codex CLI, so Whoosh can read Codex
        // sources wherever that app is installed without any separate CLI install. Located, not executed.
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            candidates.append(app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        }
        return candidates.lazy.compactMap { verified($0) }.first
    }
}
