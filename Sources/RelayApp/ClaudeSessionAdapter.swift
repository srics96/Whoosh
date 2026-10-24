import Foundation
import RelayCore

struct ClaudeSessionInfo: Decodable, Sendable {
    let sessionId: String
    let summary: String
    let cwd: String?
    let lastModified: Double
    let fileSize: Double?
}
struct ClaudeDigestMessage: Decodable, Sendable { let role: String; let text: String }
struct ClaudeAdapterResponse: Decodable, Sendable {
    let sessions: [ClaudeSessionInfo]?
    let nextOffset: Int?
    let info: ClaudeSessionInfo?
    let archive: String?
    let partial: Bool?
    let notice: String?
    let digest: [ClaudeDigestMessage]?
}
struct ClaudeSessionAdapter: Sendable {
    // Injectable only for local synthetic tests; production always uses bundled resources.
    var resourceDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("ClaudeAdapter")
    var available: Bool {
        guard let resourceDirectory else { return false }
        return FileManager.default.fileExists(atPath: resourceDirectory.appendingPathComponent("runtime.json").path)
    }
    func call(action: String, id: String? = nil, dir: String? = nil, offset: Int = 0) async throws -> ClaudeAdapterResponse {
        guard let resourceDirectory else {
            throw RelayError.invalidInput("Local Claude Code connection is not installed in this build.")
        }
        let resource = resourceDirectory.appendingPathComponent("adapter.mjs")
        let configURL = resourceDirectory.appendingPathComponent("runtime.json")
        guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String:String],
              let configuredNode = config["node"]
        else { throw NSError(domain: "Whoosh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local Claude Code connection is not installed in this build."]) }
        // An absolute path is a developer machine's own Node; a relative path is a Node runtime bundled
        // inside the app, resolved against the ClaudeAdapter resource directory so it works once installed anywhere.
        let node = configuredNode.hasPrefix("/") ? configuredNode
            : configURL.deletingLastPathComponent().appendingPathComponent(configuredNode).standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: node) else {
            throw NSError(domain: "Whoosh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local Claude Code connection is not installed in this build."])
        }
        var request: [String:Any] = ["action":action,"offset":offset]
        request["id"] = id; request["dir"] = dir
        let input = try JSONSerialization.data(withJSONObject: request)
        return try await CancellableWork.run {
            let process = Process()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh-Claude-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("response.json")
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = [resource.path, String(decoding: input, as: UTF8.self)]
            process.environment = ["HOME": NSHomeDirectory(), "PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            let diagnostic = directory.appendingPathComponent("phase.txt")
            FileManager.default.createFile(atPath: diagnostic.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let diagnosticHandle = try FileHandle(forWritingTo: diagnostic)
            defer { try? diagnosticHandle.close() }
            process.standardError = diagnosticHandle
            try process.run()
            do { try await OwnedProcess.waitForExit(process, timeout: 180) }
            catch is CancellationError { throw CancellationError() }
            catch {
                let phase = ((try? String(contentsOf: diagnostic, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { ["BLINK:started", "BLINK:config-loaded", "BLINK:sdk-loaded", "BLINK:read-complete"].contains($0) }.last ?? "before helper startup"
                throw NSError(domain:"Whoosh",code:3,userInfo:[NSLocalizedDescriptionKey:"Claude connection timed out after 180 seconds (\(phase)). No agent was started."])
            }
            guard process.terminationStatus == 0 else {
                let allowed = ["Session identity mismatch", "Project mismatch", "Source changed; stop it and select again", "No readable messages", "Unstable pagination", "History exceeds safe capture size", "Invalid session", "Unsupported operation", "Reader unavailable"]
                let diagnosticText = (try? String(contentsOf: diagnostic, encoding: .utf8)) ?? ""
                let reason = allowed.first { diagnosticText.contains("BLINK:error:" + $0) } ?? "Reader unavailable"
                throw NSError(domain:"Whoosh",code:2,userInfo:[NSLocalizedDescriptionKey:"Claude Code: \(reason). No agent was started."])
            }
            let size = try output.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size <= 256*1024*1024 else { throw NSError(domain:"Whoosh",code:4,userInfo:[NSLocalizedDescriptionKey:"Claude history exceeds the capture limit."]) }
            try Task.checkCancellation()
            let data = try Data(contentsOf: output)
            return try JSONDecoder().decode(ClaudeAdapterResponse.self, from: data)
        }
    }
}
