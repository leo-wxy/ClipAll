import Foundation

private enum PluginVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

private struct RuntimeManifest: Decodable {
    struct Runtime: Decodable { let entry: String }
    struct Capability: Decodable { let id: String; let handler: String }

    let runtime: Runtime
    let capabilities: [Capability]
}

private struct Fixture: Decodable {
    struct Expectation: Decodable {
        let subtitle: String?
        let itemValues: [String: String]
    }

    let name: String
    let capabilityID: String
    let input: String
    let configuration: [String: PluginRuntimeConfigurationValue]
    let systemTimeZoneIdentifier: String?
    let expect: Expectation?
    let expectError: String?
}

@main
enum PluginRuntimeVerification {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw PluginVerificationError.failed("用法：plugin-runtime-verification <plugin> <runner>")
        }

        let pluginURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let runnerURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: false)
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(
            RuntimeManifest.self,
            from: Data(contentsOf: pluginURL.appendingPathComponent("plugin.json"))
        )
        let fixtures = try decoder.decode(
            [Fixture].self,
            from: Data(contentsOf: pluginURL.appendingPathComponent("Tests/cases.json"))
        )
        let script = try String(
            contentsOf: pluginURL.appendingPathComponent(manifest.runtime.entry),
            encoding: .utf8
        )
        let handlers = Dictionary(uniqueKeysWithValues: manifest.capabilities.map { ($0.id, $0.handler) })

        for fixture in fixtures {
            guard let handler = handlers[fixture.capabilityID] else {
                throw PluginVerificationError.failed("\(fixture.name)：找不到能力 handler")
            }
            let request = PluginRuntimeRequest(
                script: script,
                sourceName: manifest.runtime.entry,
                handler: handler,
                input: PluginRuntimeInput(
                    text: fixture.input,
                    configuration: fixture.configuration,
                    localeIdentifier: "zh-Hans-CN",
                    systemTimeZoneIdentifier: fixture.systemTimeZoneIdentifier ?? "UTC"
                ),
                capturesLogs: true
            )
            let response = try run(request, runnerURL: runnerURL)
            try verify(response, fixture: fixture)
        }

        print("Plugin runtime verification passed (\(fixtures.count) fixtures)")
    }

    private static func run(
        _ request: PluginRuntimeRequest,
        runnerURL: URL
    ) throws -> PluginRuntimeResponse {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = runnerURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(try JSONEncoder().encode(request))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PluginVerificationError.failed("runner 异常退出：\(process.terminationStatus)")
        }
        return try JSONDecoder().decode(PluginRuntimeResponse.self, from: data)
    }

    private static func verify(_ response: PluginRuntimeResponse, fixture: Fixture) throws {
        if let expectedError = fixture.expectError {
            guard response.status == .failure, response.error?.code == expectedError else {
                throw PluginVerificationError.failed(
                    "\(fixture.name)：期望错误 \(expectedError)，实际为 \(response.error?.code ?? "success")"
                )
            }
            return
        }

        guard response.status == .success,
              let output = response.output,
              let expectation = fixture.expect else {
            throw PluginVerificationError.failed(
                "\(fixture.name)：期望成功，实际为 \(response.error?.code ?? "invalid_response")"
            )
        }
        if let expectedSubtitle = expectation.subtitle, output.subtitle != expectedSubtitle {
            throw PluginVerificationError.failed(
                "\(fixture.name)：subtitle 不匹配，实际为 \(output.subtitle ?? "nil")"
            )
        }

        let values = Dictionary(uniqueKeysWithValues: output.items.map { ($0.id, $0.value) })
        for (id, expectedValue) in expectation.itemValues where values[id] != expectedValue {
            throw PluginVerificationError.failed(
                "\(fixture.name)：\(id) 期望 \(expectedValue)，实际为 \(values[id] ?? "nil")"
            )
        }
    }
}
