import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Detached CPU/file work must inherit cancellation explicitly, and finish cleanup before returning.
public enum CancellableWork {
    public static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await withTaskCancellationHandler(operation: {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        }, onCancel: { worker.cancel() })
    }
}

/// Only pass a Process launched and owned by this operation. Never discover or stop other sessions.
public enum OwnedProcess {
    public static func waitForExit(_ process: Process, timeout: TimeInterval) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        do {
            try Task.checkCancellation()
            while process.isRunning {
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    throw RelayError.processFailed("Owned helper exceeded its read timeout")
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try Task.checkCancellation()
        } catch {
            // Cleanup must run even though the caller is cancelled.
            await Task.detached { stopAndWait(process) }.value
            throw error
        }
    }

    static func stopAndWait(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            let pid = process.processIdentifier
            if pid > 0 {
                #if canImport(Darwin) || canImport(Glibc)
                _ = kill(pid, SIGKILL)
                #endif
            }
            // Reap this child before its output files are removed or the operation completes.
            process.waitUntilExit()
        }
    }
}
