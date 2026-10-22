import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Private stdio child only. No TCP listener, shell, installation discovery, or direct session-store access.
public actor CodexStdioTransport: CodexReadOnlyRPCTransport {
    private var process: Process?
    private var probeTask: Task<String, Error>?
    private var retiringChildren: [Process] = []
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var framer = CodexRPCLineFramer()
    private var readerTask: Task<Void, Never>?
    private var sequence = 0
    private var session = UUID()
    private var pending: [Int: Pending] = [:]
    private let timeoutNanoseconds: UInt64

    private struct Pending {
        let continuation: CheckedContinuation<CodexRPCResponse, Error>
        let timer: Task<Void, Never>
    }

    public init(timeoutSeconds: Double = 12) {
        let safeTimeout = timeoutSeconds.isFinite ? min(max(timeoutSeconds, 1), 60) : 12
        timeoutNanoseconds = UInt64(safeTimeout * 1_000_000_000)
    }

    public func connect(executableURL: URL) async throws -> String {
        await disconnect()
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw CodexSourceError.invalidExecutable }
        let connection = UUID()
        session = connection
        let probe = Task { try await CodexCLIProbe.verify(executableURL) }
        probeTask = probe
        let version: String
        do { version = try await probe.value }
        catch { if session == connection { probeTask = nil }; throw error }
        guard session == connection else { throw CodexSourceError.disconnected }
        probeTask = nil
        try Task.checkCancellation()
        let child = Process()
        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        child.executableURL = executableURL
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.environment = CodexCLIProbe.childEnvironment
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe
        process = child
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        errors = stderrPipe.fileHandleForReading
        let readHandle = stdoutPipe.fileHandleForReading
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(32)) { continuation in
            // One reader preserves pipe byte order; one consumer preserves chunk order.
            DispatchQueue.global(qos: .utility).async {
                do {
                    while true {
                        let data = try CodexPipeReader.readChunk(readHandle)
                        switch continuation.yield(data) {
                        case .enqueued: break
                        case .dropped:
                            continuation.finish(throwing: CodexSourceError.responseTooLarge)
                            return
                        case .terminated: return
                        @unknown default:
                            continuation.finish(throwing: CodexSourceError.disconnected)
                            return
                        }
                        if data.isEmpty { continuation.finish(); return }
                    }
                } catch { continuation.finish(throwing: error) }
            }
        }
        readerTask = Task { [weak self] in
            do {
                for try await data in stream { await self?.receive(data, connection: connection) }
            } catch { await self?.readerFailed(error, connection: connection) }
        }
        // Drain but never log or retain stderr, which may include private paths or account details.
        errors?.readabilityHandler = { handle in _ = handle.availableData }
        // Exit is observed via the ordered stdout EOF, after all buffered responses are parsed.
        child.terminationHandler = nil
        do {
            try child.run()
            try? stdinPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
        }
        catch { fail(CodexSourceError.launchFailed(error.localizedDescription)); throw CodexSourceError.launchFailed(error.localizedDescription) }
        return version
    }

    public func request(_ method: CodexReadMethod, params: [String: CodexJSONValue]) async throws -> CodexRPCResponse {
        try Task.checkCancellation()
        guard process?.isRunning == true else { throw CodexSourceError.notConnected }
        guard pending.isEmpty else { throw CodexSourceError.invalidResponse("another source request is still running") }
        sequence += 1
        let id = sequence
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let delay = timeoutNanoseconds
                let timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                    await self?.expire(id)
                }
                pending[id] = Pending(continuation: continuation, timer: timer)
                do {
                    try write(.object(["id": .number(Double(id)), "method": .string(method.rawValue), "params": .object(params)]))
                } catch { fail(error) }
            }
        }, onCancel: { [weak self] in Task { await self?.cancel(id) } })
    }

    public func initialized() async throws {
        guard process?.isRunning == true else { throw CodexSourceError.notConnected }
        try write(.object(["method": .string("initialized"), "params": .object([:])]))
    }

    public func disconnect() async {
        let probe = probeTask
        probeTask = nil
        probe?.cancel()
        fail(CodexSourceError.disconnected)
        let children = retiringChildren
        retiringChildren.removeAll()
        // Explicit disconnect (including application quit) waits for bounded owned-child cleanup.
        for child in children { await CodexOwnedChild.stopAndWait(child) }
        if let probe { _ = try? await probe.value }
    }

    private func write(_ value: CodexJSONValue) throws {
        guard let input else { throw CodexSourceError.notConnected }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(value)
        // Small fixed-method requests fit in the child pipe. Do not forward unbounded opaque cursors.
        guard data.count < 8_192 else { throw CodexSourceError.responseTooLarge }
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data, connection: UUID) {
        guard connection == session else { return }
        if data.isEmpty { fail(CodexSourceError.disconnected); return }
        do {
            for line in try framer.append(data) {
                let message = try JSONDecoder().decode(CodexJSONValue.self, from: line)
                if message["method"] != nil {
                    if message["id"] != nil {
                        // This adapter never authorizes tools, sign-in, credentials, or server-requested actions.
                        fail(CodexSourceError.invalidResponse("server requested an action; this source is read-only"))
                        return
                    }
                    continue // Notifications are neither archived nor treated as assistant messages.
                }
                guard let id = message["id"]?.int, let request = pending.removeValue(forKey: id) else { continue }
                request.timer.cancel()
                if let remote = message["error"] {
                    request.continuation.resume(throwing: CodexSourceError.remote(remote["code"]?.int ?? -1, remote["message"]?.string ?? "Unknown error"))
                } else if let result = message["result"] {
                    request.continuation.resume(returning: CodexRPCResponse(result: result, rawLine: line))
                } else {
                    request.continuation.resume(throwing: CodexSourceError.invalidResponse("missing result"))
                }
            }
        } catch let error as CodexSourceError { fail(error) }
        catch { fail(CodexSourceError.invalidResponse("malformed JSON")) }
    }

    private func readerFailed(_ error: Error, connection: UUID) {
        if connection == session { fail(error) }
    }

    private func expire(_ id: Int) { if pending[id] != nil { fail(CodexSourceError.timedOut) } }
    private func cancel(_ id: Int) { if pending[id] != nil { fail(CancellationError()) } }

    private func fail(_ error: Error) {
        session = UUID()
        let waiting = pending
        pending.removeAll()
        let child = process
        process = nil
        child?.terminationHandler = nil
        readerTask?.cancel()
        readerTask = nil
        errors?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        try? errors?.close()
        input = nil; output = nil; errors = nil
        framer = CodexRPCLineFramer()
        retiringChildren.removeAll { !$0.isRunning }
        if let child, child.isRunning {
            retiringChildren.append(child)
            CodexOwnedChild.stop(child)
        }
        for request in waiting.values { request.timer.cancel(); request.continuation.resume(throwing: error) }
    }
}

/// A single POSIX read returns currently available bytes, not a count-filling Foundation read.
enum CodexPipeReader {
    static func readChunk(_ handle: FileHandle) throws -> Data {
        var storage = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = storage.withUnsafeMutableBytes { bytes -> Int in
                #if canImport(Darwin)
                return Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
                #elseif canImport(Glibc)
                return Glibc.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
                #else
                return -1
                #endif
            }
            if count > 0 { return Data(storage.prefix(count)) }
            if count == 0 { return Data() }
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// Pure framing utility, exercised with synthetic split-byte streams in unit tests.
struct CodexRPCLineFramer: Sendable {
    private var buffer = Data()
    private let maximumLineBytes: Int
    init(maximumLineBytes: Int = 64 * 1024 * 1024) { self.maximumLineBytes = maximumLineBytes }
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let end = buffer.index(after: newline)
            let line = Data(buffer[..<end])
            buffer.removeSubrange(..<end)
            guard line.count <= maximumLineBytes else { throw CodexSourceError.responseTooLarge }
            lines.append(line)
        }
        guard buffer.count <= maximumLineBytes else { throw CodexSourceError.responseTooLarge }
        return lines
    }
}

private enum CodexCLIProbe {
    /// Preserve ordinary process context, not API keys, access tokens, or ad-hoc credential variables.
    static var childEnvironment: [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        return Dictionary(uniqueKeysWithValues: ["HOME", "PATH", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL"].compactMap {
            key in inherited[key].map { (key, $0) }
        })
    }

    static func verify(_ executable: URL) async throws -> String {
        let versionBytes = try await CodexProbeCommand.run(executable: executable, arguments: ["--version"])
        let version = String(decoding: versionBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.range(of: #"^codex(?:-cli)? [0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) != nil else { throw CodexSourceError.unsupportedCLI }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Whoosh-Codex-Probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await CodexProbeCommand.run(executable: executable, arguments: ["app-server", "generate-json-schema", "--out", directory.path])
        try Task.checkCancellation()
        // Inspect only files just generated in our temporary directory, never native app/auth/session paths.
        guard let enumerator = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw CodexSourceError.unsupportedCLI }
        var totalBytes = 0
        var files = 0
        var databaseOnly = false
        var fullItemPagination = false
        for case let file as URL in enumerator {
            files += 1
            guard files <= 4_096 else { throw CodexSourceError.responseTooLarge }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, file.pathExtension == "json" else { continue }
            let size = values.fileSize ?? 0
            totalBytes += size
            guard size <= 8 * 1024 * 1024, totalBytes <= 32 * 1024 * 1024 else { throw CodexSourceError.responseTooLarge }
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= 8 * 1024 * 1024 else { throw CodexSourceError.responseTooLarge }
            if let json = try? JSONDecoder().decode(CodexJSONValue.self, from: bytes) {
                databaseOnly = databaseOnly || advertisesDatabaseOnlyList(json)
                if file.lastPathComponent == "ThreadItemsListParams.json",
                   json["properties"]?["threadId"] != nil, json["properties"]?["turnId"] != nil {
                    fullItemPagination = true
                }
            }
        }
        if databaseOnly && fullItemPagination { return String(version.prefix(200)) }
        // Do not retry listing without useStateDbOnly: older defaults may scan and repair source metadata.
        throw CodexSourceError.unsupportedCLI
    }

    private static func advertisesDatabaseOnlyList(_ value: CodexJSONValue, depth: Int = 0) -> Bool {
        guard depth < 100 else { return false }
        switch value {
        case .object(let object):
            if let propertyValue = object["properties"], case .object(let properties) = propertyValue,
               properties["useStateDbOnly"] != nil, properties["sourceKinds"] != nil,
               properties["cursor"] != nil, properties["limit"] != nil { return true }
            return object.values.contains { advertisesDatabaseOnlyList($0, depth: depth + 1) }
        case .array(let array): return array.contains { advertisesDatabaseOnlyList($0, depth: depth + 1) }
        default: return false
        }
    }
}

/// Terminate only the Process instance this adapter launched, then bound a stalled shutdown.
private enum CodexOwnedChild {
    static func stopAndWait(_ process: Process) async {
        // A detached waiter remains effective even when the operation being disconnected was cancelled.
        await Task.detached(priority: .utility) {
            if process.isRunning { process.terminate() }
            for _ in 0..<20 {
                if !process.isRunning { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let pid = process.processIdentifier
            if pid > 0, process.isRunning {
                #if canImport(Darwin)
                _ = Darwin.kill(pid, SIGKILL)
                #elseif canImport(Glibc)
                _ = Glibc.kill(pid, SIGKILL)
                #endif
            }
            for _ in 0..<20 {
                if !process.isRunning { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }.value
    }

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            guard pid > 0, process.isRunning, process.processIdentifier == pid else { return }
            #if canImport(Darwin)
            _ = Darwin.kill(pid, SIGKILL)
            #elseif canImport(Glibc)
            _ = Glibc.kill(pid, SIGKILL)
            #endif
        }
    }
}

/// Short-lived, bounded CLI metadata commands. No shell is used; stdout is never logged.
private final class CodexProbeCommand: @unchecked Sendable {
    private let lock = NSLock()
    private let child = Process()
    private let pipe = Pipe()
    private var continuation: CheckedContinuation<Data, Error>?
    private var finished = false
    private var stdout = Data()
    private var stdoutClosed = false
    private var exitStatus: Int32?
    private let maximumBytes = 1_048_576

    static func run(executable: URL, arguments: [String]) async throws -> Data {
        let operation = CodexProbeCommand()
        do {
            let result: Data = try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { operation.start(executable: executable, arguments: arguments, continuation: $0) }
            }, onCancel: { operation.finish(.failure(CancellationError())) })
            await CodexOwnedChild.stopAndWait(operation.child)
            return result
        } catch {
            await CodexOwnedChild.stopAndWait(operation.child)
            throw error
        }
    }

    private func start(executable: URL, arguments: [String], continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        child.environment = CodexCLIProbe.childEnvironment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] process in self?.didExit(process.terminationStatus) }
        do {
            try child.run()
            // The parent must not keep an extra writer alive: EOF belongs to the launched child.
            try? pipe.fileHandleForWriting.close()
            lock.unlock()
        } catch { lock.unlock(); finish(.failure(CodexSourceError.launchFailed(error.localizedDescription))); return }
        DispatchQueue.global(qos: .utility).async {
            do {
                while !self.isFinished {
                    let data = try CodexPipeReader.readChunk(self.pipe.fileHandleForReading)
                    self.consume(data)
                    if data.isEmpty { return }
                }
            } catch { self.finish(.failure(error)) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in self?.finish(.failure(CodexSourceError.timedOut)) }
    }

    private var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    private func consume(_ data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        if data.isEmpty { stdoutClosed = true }
        else {
            guard stdout.count + data.count <= maximumBytes else {
                lock.unlock(); finish(.failure(CodexSourceError.responseTooLarge)); return
            }
            stdout.append(data)
        }
        let result = completedResult()
        lock.unlock()
        if let result { finish(result) }
    }

    private func didExit(_ status: Int32) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        exitStatus = status
        let result = completedResult()
        lock.unlock()
        if let result { finish(result) }
    }

    /// Caller holds the lock. Successful completion waits for both process exit and drained stdout.
    private func completedResult() -> Result<Data, Error>? {
        guard let status = exitStatus else { return nil }
        if status != 0 { return .failure(CodexSourceError.unsupportedCLI) }
        guard stdoutClosed else { return nil }
        return .success(stdout)
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let callback = continuation
        continuation = nil
        stdout.removeAll(keepingCapacity: false)
        lock.unlock()
        child.terminationHandler = nil
        CodexOwnedChild.stop(child)
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        callback?.resume(with: result)
    }
}
