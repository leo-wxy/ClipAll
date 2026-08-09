import ClipAllPluginProtocol
import Darwin
import Foundation

struct PluginRunnerExecution: Sendable {
    let response: PluginRuntimeResponse
    let duration: Duration
}

enum PluginRunnerClientError: Error, LocalizedError, Equatable, Sendable {
    case runnerMissing
    case requestTooLarge
    case launchFailed
    case timedOut
    case responseTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .runnerMissing:
            "插件运行器不可用"
        case .requestTooLarge:
            "插件请求超过运行上限"
        case .launchFailed:
            "无法启动插件运行器"
        case .timedOut:
            "插件执行超时"
        case .responseTooLarge:
            "插件结果超过运行上限"
        case .invalidResponse:
            "插件运行器返回了无效结果"
        }
    }
}

struct PluginRunnerClient: Sendable {
    let runnerURL: URL
    let timeout: Duration

    init(runnerURL: URL, timeout: Duration = .milliseconds(750)) {
        self.runnerURL = runnerURL
        self.timeout = timeout
    }

    func execute(_ request: PluginRuntimeRequest) async throws -> PluginRunnerExecution {
        let cancellation = PluginProcessCancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try executeSynchronously(request, cancellation: cancellation)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func executeSynchronously(
        _ request: PluginRuntimeRequest,
        cancellation: PluginProcessCancellation
    ) throws -> PluginRunnerExecution {
        guard FileManager.default.isExecutableFile(atPath: runnerURL.path) else {
            throw PluginRunnerClientError.runnerMissing
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        guard requestData.count <= PluginRuntimeLimits.maximumRequestBytes else {
            throw PluginRunnerClientError.requestTooLarge
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipAllPluginRunner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let stdinURL = temporaryDirectory.appendingPathComponent("stdin.json")
        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout.json")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr.log")
        try requestData.write(to: stdinURL, options: .atomic)
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdin = try FileHandle(forReadingFrom: stdinURL)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdin.close()
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = runnerURL
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            try process.run()
        } catch {
            throw PluginRunnerClientError.launchFailed
        }
        guard cancellation.attach(process) else {
            terminate(process)
            throw CancellationError()
        }
        defer { cancellation.detach(process) }

        let timeoutSeconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1_000_000_000_000_000_000
        if termination.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            terminate(process)
            _ = termination.wait(timeout: .now() + 0.15)
            throw PluginRunnerClientError.timedOut
        }
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw PluginRunnerClientError.invalidResponse
        }

        try stdout.synchronize()
        let responseData = try Data(contentsOf: stdoutURL, options: .mappedIfSafe)
        guard responseData.count <= PluginRuntimeLimits.maximumResponseBytes else {
            throw PluginRunnerClientError.responseTooLarge
        }
        guard !responseData.isEmpty,
              let response = try? JSONDecoder().decode(PluginRuntimeResponse.self, from: responseData),
              response.protocolVersion == PluginRuntimeLimits.protocolVersion,
              isStructurallyValid(response) else {
            throw PluginRunnerClientError.invalidResponse
        }

        return PluginRunnerExecution(response: response, duration: startedAt.duration(to: clock.now))
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func isStructurallyValid(_ response: PluginRuntimeResponse) -> Bool {
        switch response.status {
        case .success:
            response.output != nil && response.error == nil
        case .failure:
            response.output == nil && response.error != nil
        }
    }
}

private final class PluginProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func detach(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if self.process === process {
            self.process = nil
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
