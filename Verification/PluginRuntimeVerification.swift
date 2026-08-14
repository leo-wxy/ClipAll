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

    let manifestVersion: Int
    let id: String
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

        try expect(manifest.manifestVersion == 2, "示例 manifest 必须使用 v2")
        try expect(
            manifest.id == "com.clipall.plugin.timestamp-tools",
            "时间工具必须保持稳定插件 ID"
        )

        for fixture in fixtures {
            guard let handler = handlers[fixture.capabilityID] else {
                throw PluginVerificationError.failed("\(fixture.name)：找不到能力 handler")
            }
            let request = PluginRuntimeRequest(
                script: script,
                sourceName: manifest.runtime.entry,
                handler: handler,
                input: PluginRuntimeInput(
                    pluginID: manifest.id,
                    text: fixture.input,
                    configuration: fixture.configuration
                ),
                capturesLogs: true
            )
            let response = try run(request, runnerURL: runnerURL)
            try verify(response, fixture: fixture)
        }

        try verifyRuntimeV2(runnerURL: runnerURL, pluginID: manifest.id)

        print("Plugin runtime verification passed (\(fixtures.count) fixtures)")
    }

    private static func verifyRuntimeV2(runnerURL: URL, pluginID: String) throws {
        let immutableAPI = #"""
        var ClipAllPlugin = {
          verify: function (text) {
            "use strict";
            var environment = App.getPluginEnv("\#(pluginID)");
            var descriptor = Object.getOwnPropertyDescriptor(globalThis, "App");
            try { environment.mode = "changed"; } catch (_) {}
            try { App.getPluginEnv = function () { return {}; }; } catch (_) {}
            if (typeof text !== "string" ||
                globalThis.__clipallRequest !== undefined ||
                !Object.isFrozen(environment) ||
                !Object.isFrozen(App) ||
                descriptor.writable !== false ||
                descriptor.configurable !== false ||
                environment.mode !== "compact" ||
                environment.enabled !== true) {
              var error = new Error("Runtime v2 隔离失败");
              error.code = "verification_failed";
              throw error;
            }
            return {
              title: "Runtime v2",
              subtitle: null,
              items: [{
                id: "result",
                label: "结果",
                value: text + "|" + environment.mode + "|" + environment.enabled,
                annotation: null,
                style: "body"
              }]
            };
          }
        };
        """#
        let valid = try run(
            request(
                script: immutableAPI,
                pluginID: pluginID,
                text: "selected",
                configuration: ["mode": .string("compact"), "enabled": .bool(true)]
            ),
            runnerURL: runnerURL
        )
        try expect(valid.status == .success, "Runtime v2 应接收字符串并读取自身配置")
        try expect(
            valid.output?.items.first?.value == "selected|compact|true",
            "handler 应只收到 text，且配置快照不可改写"
        )

        let emptyEnvironment = try run(
            request(
                script: environmentCountScript(pluginID: pluginID),
                pluginID: pluginID,
                configuration: [:]
            ),
            runnerURL: runnerURL
        )
        try expect(
            emptyEnvironment.output?.items.first?.value == "0",
            "无配置插件应获得空对象"
        )

        for invalidID in ["", "com.clipall.plugin.other"] {
            let response = try run(
                request(
                    script: environmentCountScript(pluginID: invalidID),
                    pluginID: pluginID,
                    configuration: [:]
                ),
                runnerURL: runnerURL
            )
            try expect(
                response.status == .failure && response.error?.code == "invalid_plugin_id",
                "空或跨插件 ID 必须被拒绝"
            )
        }

        let legacyRequest: [String: Any] = [
            "protocolVersion": 1,
            "script": "var ClipAllPlugin = {};",
            "sourceName": "legacy.js",
            "handler": "run",
            "input": [
                "text": "legacy",
                "configuration": [:],
                "localeIdentifier": "zh-Hans-CN",
                "systemTimeZoneIdentifier": "UTC",
            ],
            "capturesLogs": false,
        ]
        let legacyResponse = try run(
            JSONSerialization.data(withJSONObject: legacyRequest),
            runnerURL: runnerURL
        )
        try expect(
            legacyResponse.protocolVersion == 2 &&
                legacyResponse.status == .failure &&
                legacyResponse.error?.code == "unsupported_protocol",
            "真实 v1 JSON 必须在协议边界返回 unsupported_protocol"
        )
    }

    private static func request(
        script: String,
        pluginID: String,
        text: String = "test",
        configuration: [String: PluginRuntimeConfigurationValue]
    ) -> PluginRuntimeRequest {
        PluginRuntimeRequest(
            script: script,
            sourceName: "verification.js",
            handler: "verify",
            input: PluginRuntimeInput(
                pluginID: pluginID,
                text: text,
                configuration: configuration
            ),
            capturesLogs: true
        )
    }

    private static func environmentCountScript(pluginID: String) -> String {
        #"""
        var ClipAllPlugin = {
          verify: function (text) {
            return {
              title: "Environment",
              subtitle: null,
              items: [{
                id: "count",
                label: "Count",
                value: String(Object.keys(App.getPluginEnv("\#(pluginID)")).length),
                annotation: null,
                style: "body"
              }]
            };
          }
        };
        """#
    }

    private static func run(
        _ request: PluginRuntimeRequest,
        runnerURL: URL
    ) throws -> PluginRuntimeResponse {
        try run(try JSONEncoder().encode(request), runnerURL: runnerURL)
    }

    private static func run(
        _ requestData: Data,
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
        input.fileHandleForWriting.write(requestData)
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PluginVerificationError.failed("runner 异常退出：\(process.terminationStatus)")
        }
        return try JSONDecoder().decode(PluginRuntimeResponse.self, from: data)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw PluginVerificationError.failed(message) }
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
