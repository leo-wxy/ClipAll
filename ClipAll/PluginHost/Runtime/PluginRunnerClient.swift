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

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = runnerURL
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let processIO = PluginProcessIO(
            stdin: stdin.fileHandleForWriting,
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            responseLimit: PluginRuntimeLimits.maximumResponseBytes
        )
        defer { processIO.finish() }

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            try process.run()
        } catch {
            closeUnusedPipeEnds(stdin: stdin, stdout: stdout, stderr: stderr)
            throw PluginRunnerClientError.launchFailed
        }
        closeUnusedPipeEnds(stdin: stdin, stdout: stdout, stderr: stderr)
        processIO.start(requestData: requestData)
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
        processIO.finish()
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw PluginRunnerClientError.invalidResponse
        }

        let responseData = processIO.responseData
        guard !processIO.responseExceededLimit else {
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

    private func closeUnusedPipeEnds(stdin: Pipe, stdout: Pipe, stderr: Pipe) {
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
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

private final class PluginProcessIO: @unchecked Sendable {
    private static let chunkSize = 32_768
    private static let pollIntervalMilliseconds: Int32 = 20
    private static let completionWindow = 0.15

    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let state: PluginProcessIOState
    private let workers = DispatchGroup()
    private let queue = DispatchQueue(
        label: "com.wxy.ClipAll.plugin-runner-io",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var finished = false

    init(stdin: FileHandle, stdout: FileHandle, stderr: FileHandle, responseLimit: Int) {
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        state = PluginProcessIOState(responseLimit: responseLimit)
        makeNonBlocking(stdin.fileDescriptor, suppressesSIGPIPE: true)
        makeNonBlocking(stdout.fileDescriptor)
        makeNonBlocking(stderr.fileDescriptor)
    }

    var responseData: Data { state.responseData }
    var responseExceededLimit: Bool { state.responseExceededLimit }

    func start(requestData: Data) {
        workers.enter()
        queue.async { [self] in
            defer {
                try? stdin.close()
                workers.leave()
            }
            write(requestData, to: stdin.fileDescriptor)
        }

        workers.enter()
        queue.async { [self] in
            defer {
                try? stdout.close()
                workers.leave()
            }
            drain(stdout.fileDescriptor, collectsResponse: true)
        }

        workers.enter()
        queue.async { [self] in
            defer {
                try? stderr.close()
                workers.leave()
            }
            drain(stderr.fileDescriptor, collectsResponse: false)
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true

        if workers.wait(timeout: .now() + Self.completionWindow) == .timedOut {
            state.requestStop()
            closeHandles()
            _ = workers.wait(timeout: .now() + Self.completionWindow)
        } else {
            closeHandles()
        }
    }

    private func write(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0

            while offset < bytes.count, !state.shouldStop {
                var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                let result = Darwin.poll(&event, 1, Self.pollIntervalMilliseconds)
                if result == 0 { continue }
                if result < 0 {
                    if errno == EINTR { continue }
                    return
                }
                if event.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                    return
                }
                guard event.revents & Int16(POLLOUT) != 0 else { continue }

                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno != EINTR, errno != EAGAIN, errno != EWOULDBLOCK {
                    return
                }
            }
        }
    }

    private func drain(_ descriptor: Int32, collectsResponse: Bool) {
        var buffer = [UInt8](repeating: 0, count: Self.chunkSize)

        while !state.shouldStop {
            var event = pollfd(
                fd: descriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let result = Darwin.poll(&event, 1, Self.pollIntervalMilliseconds)
            if result == 0 { continue }
            if result < 0 {
                if errno == EINTR { continue }
                return
            }
            if event.revents & Int16(POLLNVAL) != 0 { return }

            if event.revents & Int16(POLLIN | POLLHUP) != 0 {
                while true {
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                    }
                    if count > 0 {
                        if collectsResponse {
                            state.appendResponse(buffer, count: count)
                        }
                    } else if count == 0 {
                        return
                    } else if errno == EINTR {
                        continue
                    } else if errno == EAGAIN || errno == EWOULDBLOCK {
                        break
                    } else {
                        return
                    }
                }
            }
            if event.revents & Int16(POLLERR) != 0 { return }
        }
    }

    private func makeNonBlocking(_ descriptor: Int32, suppressesSIGPIPE: Bool = false) {
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }
        if suppressesSIGPIPE {
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        }
    }

    private func closeHandles() {
        try? stdin.close()
        try? stdout.close()
        try? stderr.close()
    }
}

private final class PluginProcessIOState: @unchecked Sendable {
    private let lock = NSLock()
    private let responseCapacity: Int
    private var response = Data()
    private var stopped = false

    init(responseLimit: Int) {
        responseCapacity = responseLimit + 1
    }

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    var responseData: Data {
        lock.lock()
        defer { lock.unlock() }
        return response
    }

    var responseExceededLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return response.count == responseCapacity
    }

    func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func appendResponse(_ buffer: [UInt8], count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let appendCount = min(count, responseCapacity - response.count)
        guard appendCount > 0 else { return }
        buffer.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            response.append(baseAddress, count: appendCount)
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
