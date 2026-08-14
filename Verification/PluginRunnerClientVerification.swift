import ClipAllPluginProtocol
import Foundation

private enum RunnerClientVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
enum PluginRunnerClientVerification {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ClipAll-RunnerClient-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        try await expectClientError(.runnerMissing) {
            try await PluginRunnerClient(
                runnerURL: root.appendingPathComponent("missing")
            ).execute(request())
        }

        let success = try executable(
            in: root,
            name: "success.sh",
            contents: successScript()
        )
        let successExecution = try await PluginRunnerClient(
            runnerURL: success,
            timeout: .seconds(1)
        ).execute(request())
        try expect(
            successExecution.response.output?.title == "Verification",
            "关闭 stdin 写端后 runner 应收到 EOF 并返回合法结果"
        )

        let baselineDirectories = try runnerTransportDirectories()
        let noTemporaryFilesReady = root.appendingPathComponent("no-temporary-files.ready")
        let noTemporaryFiles = try executable(
            in: root,
            name: "no-temporary-files.sh",
            contents: successScript(
                preamble: """
                : > '\(noTemporaryFilesReady.path)'
                /bin/sleep 0.2
                """
            )
        )
        let noTemporaryFilesTask = Task {
            try await PluginRunnerClient(
                runnerURL: noTemporaryFiles,
                timeout: .seconds(1)
            ).execute(request())
        }
        let readyClock = ContinuousClock()
        let readyDeadline = readyClock.now.advanced(by: .seconds(1))
        while !FileManager.default.fileExists(atPath: noTemporaryFilesReady.path) {
            if readyClock.now >= readyDeadline {
                noTemporaryFilesTask.cancel()
                throw RunnerClientVerificationError.failed("runner 未进入无落盘检查窗口")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let observedTransportDirectories = try runnerTransportDirectories()
            .subtracting(baselineDirectories)
        let noTemporaryFilesExecution = try await noTemporaryFilesTask.value
        try expect(
            noTemporaryFilesExecution.response.output?.title == "Verification",
            "无落盘 runner 应正常返回结果"
        )
        try expect(
            observedTransportDirectories.isEmpty,
            "runner 执行期间不应创建传输临时目录：\(observedTransportDirectories)"
        )

        let invalid = try executable(
            in: root,
            name: "invalid-response.sh",
            contents: "#!/bin/sh\nprintf 'not-json'\n"
        )
        try await expectClientError(.invalidResponse) {
            try await PluginRunnerClient(runnerURL: invalid).execute(request())
        }

        let nonzero = try executable(
            in: root,
            name: "nonzero.sh",
            contents: """
            #!/bin/sh
            printf '{"protocolVersion":2,"status":"failure","output":null,"error":{"code":"test","message":"test","sourceLocation":null},"logs":[]}'
            exit 1
            """
        )
        try await expectClientError(.invalidResponse) {
            try await PluginRunnerClient(runnerURL: nonzero).execute(request())
        }

        let oversized = try executable(
            in: root,
            name: "oversized-response.sh",
            contents: "#!/bin/sh\nexec /usr/bin/head -c 300000 /dev/zero\n"
        )
        try await expectClientError(.responseTooLarge) {
            try await PluginRunnerClient(runnerURL: oversized).execute(request())
        }

        let pressuredOutput = try executable(
            in: root,
            name: "pressured-output.sh",
            contents: """
            #!/bin/sh
            cat >/dev/null
            /usr/bin/head -c 300000 /dev/zero >&2 &
            stderr_pid=$!
            /usr/bin/head -c 300000 /dev/zero
            wait "$stderr_pid"
            """
        )
        try await expectClientError(.responseTooLarge) {
            try await PluginRunnerClient(
                runnerURL: pressuredOutput,
                timeout: .seconds(2)
            ).execute(request())
        }

        let sleeper = try executable(
            in: root,
            name: "sleep.sh",
            contents: "#!/bin/sh\nexec /bin/sleep 2\n"
        )
        try await expectClientError(.timedOut) {
            try await PluginRunnerClient(
                runnerURL: sleeper,
                timeout: .milliseconds(25)
            ).execute(request())
        }

        let clock = ContinuousClock()
        let started = clock.now
        let cancellationTask = Task {
            try await PluginRunnerClient(
                runnerURL: sleeper,
                timeout: .seconds(3)
            ).execute(request())
        }
        try await Task.sleep(for: .milliseconds(40))
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            throw RunnerClientVerificationError.failed("取消后不应返回 runner 结果")
        } catch is CancellationError {
            // Expected.
        }
        try expect(
            started.duration(to: clock.now) < .seconds(1),
            "取消应立即终止 runner，而不是等待超时"
        )

        let pressuredSleeper = try executable(
            in: root,
            name: "pressured-sleep.sh",
            contents: """
            #!/bin/sh
            cat >/dev/null
            /usr/bin/head -c 5000000 /dev/zero >&2 &
            /usr/bin/head -c 5000000 /dev/zero
            wait
            /bin/sleep 2
            """
        )
        let pressureCancellationStarted = clock.now
        let pressureCancellationTask = Task {
            try await PluginRunnerClient(
                runnerURL: pressuredSleeper,
                timeout: .seconds(3)
            ).execute(request())
        }
        try await Task.sleep(for: .milliseconds(20))
        pressureCancellationTask.cancel()
        do {
            _ = try await pressureCancellationTask.value
            throw RunnerClientVerificationError.failed("输出压力下取消后不应返回 runner 结果")
        } catch is CancellationError {
            // Expected.
        }
        try expect(
            pressureCancellationStarted.duration(to: clock.now) < .seconds(1),
            "输出压力下取消也应立即终止并回收 runner I/O"
        )

        try await expectClientError(.requestTooLarge) {
            try await PluginRunnerClient(runnerURL: invalid).execute(
                request(script: String(repeating: "x", count: PluginRuntimeLimits.maximumRequestBytes))
            )
        }

        print("Plugin runner client verification passed")
    }

    private static let successResponse = """
    {"protocolVersion":2,"status":"success","output":{"title":"Verification","subtitle":null,"items":[{"id":"result","label":"结果","value":"ok","annotation":null,"style":"body"}]},"error":null,"logs":[]}
    """

    private static func successScript(preamble: String? = nil) -> String {
        """
        #!/bin/sh
        cat >/dev/null
        \(preamble ?? "")
        printf '%s' '\(successResponse)'
        """
    }

    private static func runnerTransportDirectories() throws -> Set<URL> {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let contents = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )
        return Set(contents.filter { $0.lastPathComponent.hasPrefix("ClipAllPluginRunner-") })
    }

    private static func request(script: String = "var ClipAllPlugin = {};") -> PluginRuntimeRequest {
        PluginRuntimeRequest(
            script: script,
            sourceName: "verification.js",
            handler: "run",
            input: PluginRuntimeInput(
                pluginID: "com.clipall.verification",
                text: "test",
                configuration: [:]
            ),
            capturesLogs: false
        )
    }

    private static func executable(
        in directory: URL,
        name: String,
        contents: String
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private static func expectClientError(
        _ expected: PluginRunnerClientError,
        operation: @Sendable () async throws -> PluginRunnerExecution
    ) async throws {
        do {
            _ = try await operation()
            throw RunnerClientVerificationError.failed("期望错误 \(expected)，但执行成功")
        } catch let error as PluginRunnerClientError {
            try expect(error == expected, "期望 \(expected)，实际 \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RunnerClientVerificationError.failed(message) }
    }
}
