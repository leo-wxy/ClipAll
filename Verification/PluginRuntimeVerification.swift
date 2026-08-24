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
        try verifyBoundedLogs(runnerURL: runnerURL, pluginID: manifest.id)
        try verifyResponseBudget(runnerURL: runnerURL, pluginID: manifest.id)

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
        configuration: [String: PluginRuntimeConfigurationValue],
        capturesLogs: Bool = true
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
            capturesLogs: capturesLogs
        )
    }

    private static func verifyBoundedLogs(runnerURL: URL, pluginID: String) throws {
        let script = #"""
        var ClipAllPlugin = {
          verify: function (text) {
            var payload = Array(601).join("x");
            var serializedValues = 0;
            var loggedValue = {
              toJSON: function () {
                serializedValues += 1;
                return payload;
              }
            };
            for (var index = 0; index < 1000; index += 1) {
              if (index % 3 === 0) console.log("entry-" + index, loggedValue);
              else if (index % 3 === 1) console.warn("entry-" + index, loggedValue);
              else console.error("entry-" + index, loggedValue);
            }
            return {
              title: "Logs",
              subtitle: null,
              items: [{
                id: "result",
                label: "Result",
                value: String(serializedValues),
                annotation: null,
                style: "body"
              }]
            };
          }
        };
        """#
        let captured = try run(
            request(
                script: script,
                pluginID: pluginID,
                configuration: [:]
            ),
            runnerURL: runnerURL
        )
        try expect(captured.status == .success, "大量日志不应影响插件执行")
        try expect(
            captured.logs.count == PluginRuntimeLimits.maximumLogEntries,
            "Runner 只应保留前 \(PluginRuntimeLimits.maximumLogEntries) 条日志"
        )
        try expect(
            captured.output?.items.first?.value
                == String(PluginRuntimeLimits.maximumLogEntries),
            "达到日志上限后不应继续序列化日志参数"
        )
        try expect(captured.logs[0].hasPrefix("log: entry-0 "), "首条日志顺序或 level 错误")
        try expect(captured.logs[1].hasPrefix("warn: entry-1 "), "第二条日志顺序或 level 错误")
        try expect(captured.logs[2].hasPrefix("error: entry-2 "), "第三条日志顺序或 level 错误")
        try expect(
            captured.logs.allSatisfy {
                $0.count <= PluginRuntimeLimits.maximumLogEntryCharacters
            },
            "每条日志必须在写入时限制长度"
        )

        let disabled = try run(
            request(
                script: script,
                pluginID: pluginID,
                configuration: [:],
                capturesLogs: false
            ),
            runnerURL: runnerURL
        )
        try expect(disabled.status == .success, "关闭日志捕获不应影响插件执行")
        try expect(disabled.logs.isEmpty, "关闭日志捕获时不应保存日志")
        try expect(
            disabled.output?.items.first?.value == "0",
            "关闭日志捕获时不应序列化日志参数"
        )
    }

    private static func verifyResponseBudget(runnerURL: URL, pluginID: String) throws {
        let pressuredScript = #"""
        var ClipAllPlugin = {
          verify: function (_) {
            var payload = Array(20501).join("x");
            var items = [];
            for (var index = 0; index < 12; index += 1) {
              console.log("entry-" + index, payload);
              items.push({
                id: "item" + index,
                label: "Item",
                value: payload,
                annotation: null,
                style: "body"
              });
            }
            for (var logIndex = 12; logIndex < 100; logIndex += 1) {
              console.log("entry-" + logIndex, payload);
            }
            return { title: "Budget", subtitle: null, items: items };
          }
        };
        """#
        let pressured = try runWithData(
            request(
                script: pressuredScript,
                pluginID: pluginID,
                configuration: [:]
            ),
            runnerURL: runnerURL
        )
        try expect(pressured.response.status == .success, "响应预算压力下仍应成功")
        guard let output = pressured.response.output else {
            throw PluginVerificationError.failed("响应预算不得丢失合法 output")
        }
        try expect(
            output.title == "Budget"
                && output.items.count == 12
                && output.items.enumerated().allSatisfy { index, item in
                    item.id == "item\(index)" && item.value.count == 20_500
                },
            "日志预算裁剪不得修改 output items"
        )
        try expect(
            pressured.data.count <= PluginRuntimeLimits.maximumResponseBytes,
            "真实 Runner stdout 响应不得超过完整 JSON 预算"
        )
        try expect(
            !pressured.response.logs.isEmpty
                && pressured.response.logs.count < PluginRuntimeLimits.maximumLogEntries,
            "结果占用预算后应只裁剪尾部日志"
        )
        try expect(
            pressured.response.logs.enumerated().allSatisfy { index, log in
                log.hasPrefix("log: entry-\(index) ")
                    && log.count <= PluginRuntimeLimits.maximumLogEntryCharacters
            },
            "预算裁剪必须保留日志顺序、level 与单条限制"
        )

        let oversizedWithoutLogsScript = #"""
        var ClipAllPlugin = {
          verify: function (_) {
            var payload = Array(32769).join("x");
            var items = [];
            for (var index = 0; index < 12; index += 1) {
              items.push({
                id: "item" + index,
                label: "Item",
                value: payload,
                annotation: null,
                style: "body"
              });
            }
            return { title: "Too Large", subtitle: null, items: items };
          }
        };
        """#
        let oversized = try runWithData(
            request(
                script: oversizedWithoutLogsScript,
                pluginID: pluginID,
                configuration: [:],
                capturesLogs: false
            ),
            runnerURL: runnerURL
        )
        try expect(
            oversized.data.count <= PluginRuntimeLimits.maximumResponseBytes,
            "无日志结果超限时也必须返回受预算保护的响应"
        )
        try expect(
            oversized.response.status == .failure
                && oversized.response.output == nil
                && oversized.response.logs.isEmpty
                && oversized.response.error?.code == "invalid_output",
            "无日志结果仍超限时应返回 invalid_output"
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
        try runWithData(requestData, runnerURL: runnerURL).response
    }

    private static func runWithData(
        _ request: PluginRuntimeRequest,
        runnerURL: URL
    ) throws -> (response: PluginRuntimeResponse, data: Data) {
        try runWithData(try JSONEncoder().encode(request), runnerURL: runnerURL)
    }

    private static func runWithData(
        _ requestData: Data,
        runnerURL: URL
    ) throws -> (response: PluginRuntimeResponse, data: Data) {
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
        return (
            try JSONDecoder().decode(PluginRuntimeResponse.self, from: data),
            data
        )
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
