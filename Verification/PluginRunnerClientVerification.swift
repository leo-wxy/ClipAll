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
            printf '{"protocolVersion":1,"status":"failure","output":null,"error":{"code":"test","message":"test","sourceLocation":null},"logs":[]}'
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

        try await expectClientError(.requestTooLarge) {
            try await PluginRunnerClient(runnerURL: invalid).execute(
                request(script: String(repeating: "x", count: PluginRuntimeLimits.maximumRequestBytes))
            )
        }

        print("Plugin runner client verification passed")
    }

    private static func request(script: String = "var ClipAllPlugin = {};") -> PluginRuntimeRequest {
        PluginRuntimeRequest(
            script: script,
            sourceName: "verification.js",
            handler: "run",
            input: PluginRuntimeInput(
                text: "test",
                configuration: [:],
                localeIdentifier: "en_US",
                systemTimeZoneIdentifier: "UTC"
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
