import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
}

public enum CommandRunner {
    public static func run(executable: URL, arguments: [String], environment: [String: String],
                           timeout: Duration = .seconds(12)) async throws -> CommandResult {
        let session = CapturedCommand()
        return try await withThrowingTaskGroup(of: CommandResult.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await session.run(executable: executable, arguments: arguments, environment: environment)
                } onCancel: {
                    Task { await session.cancel() }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LauncherError("设备扫描超时。请检查 ADB 与设备连接后重试。")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

// OS callbacks enter this actor before accessing the process or its continuation.
private actor CapturedCommand {
    private var process: Process?
    private var outputFile: FileHandle?
    private var outputURL: URL?
    private var continuation: CheckedContinuation<CommandResult, any Error>?
    private var cancelled = false

    func run(executable: URL, arguments: [String], environment: [String: String]) async throws -> CommandResult {
        guard !cancelled else { throw CancellationError() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scrcpy-scan-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        outputURL = url
        outputFile = handle
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        // A file avoids pipe backpressure even when a tool emits a large error message.
        child.standardOutput = handle
        child.standardError = handle
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { await self?.finish(status: status) }
        }
        process = child
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do { try child.run() }
            catch { complete(.failure(error)) }
        }
    }

    func cancel() {
        cancelled = true
        if let process, process.isRunning {
            // Only this short-lived scan child is killed; the shared ADB server is never stopped.
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finish(status: Int32) {
        if cancelled {
            complete(.failure(CancellationError()))
        } else {
            let data = outputURL.flatMap { try? Data(contentsOf: $0) } ?? Data()
            complete(.success(CommandResult(status: status, output: String(decoding: data.suffix(131_072), as: UTF8.self))))
        }
    }

    private func complete(_ result: Result<CommandResult, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        process?.terminationHandler = nil
        process = nil
        try? outputFile?.close()
        outputFile = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        continuation.resume(with: result)
    }
}
