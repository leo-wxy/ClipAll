import ClipAllPluginProtocol
import Foundation
import JavaScriptCore

struct JavaScriptPluginRuntime {
    func execute(_ request: PluginRuntimeRequest) -> PluginRuntimeResponse {
        guard request.protocolVersion == PluginRuntimeLimits.protocolVersion else {
            return .failure(.init(
                code: "unsupported_protocol",
                message: "插件运行协议版本不受支持"
            ))
        }

        guard request.input.text.utf8.count <= PluginRuntimeLimits.maximumSelectionBytes else {
            return .failure(.init(code: "input_too_large", message: "所选文字超过插件处理上限"))
        }

        guard let context = JSContext() else {
            return .failure(.init(code: "runtime_unavailable", message: "无法创建插件运行环境"))
        }

        var capturedException: JSValue?
        context.exceptionHandler = { _, exception in
            capturedException = exception
        }

        guard let inputObject = makeJSONObject(request.input),
              let inputValue = JSValue(object: inputObject, in: context) else {
            return .failure(.init(code: "invalid_request", message: "无法准备插件输入"))
        }
        context.setObject(inputValue, forKeyedSubscript: "__clipallRequest" as NSString)

        context.evaluateScript(Self.bootstrapScript)
        if let exception = takeException(&capturedException) {
            return .failure(errorPayload(from: exception, includesDetails: request.capturesLogs))
        }

        let sourceURL = URL(fileURLWithPath: "/virtual/(sanitizedSourceName(request.sourceName))")
        context.evaluateScript(request.script, withSourceURL: sourceURL)
        if let exception = takeException(&capturedException) {
            return .failure(
                errorPayload(from: exception, includesDetails: request.capturesLogs),
                logs: logs(from: context, enabled: request.capturesLogs)
            )
        }

        guard let plugin = context.objectForKeyedSubscript("ClipAllPlugin"),
              !plugin.isUndefined,
              !plugin.isNull,
              let handler = plugin.objectForKeyedSubscript(request.handler),
              !handler.isUndefined,
              handler.isObject else {
            return .failure(
                .init(code: "missing_handler", message: "插件没有声明对应的执行函数"),
                logs: logs(from: context, enabled: request.capturesLogs)
            )
        }

        let value = handler.call(withArguments: [inputValue])
        if let exception = takeException(&capturedException) {
            return .failure(
                errorPayload(from: exception, includesDetails: request.capturesLogs),
                logs: logs(from: context, enabled: request.capturesLogs)
            )
        }

        guard let object = value?.toObject(),
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              data.count <= PluginRuntimeLimits.maximumResponseBytes,
              let output = try? JSONDecoder().decode(PluginRuntimeResult.self, from: data) else {
            return .failure(
                .init(code: "invalid_output", message: "插件返回了无效结果"),
                logs: logs(from: context, enabled: request.capturesLogs)
            )
        }

        if let validationError = validate(output) {
            return .failure(validationError, logs: logs(from: context, enabled: request.capturesLogs))
        }

        return .success(output, logs: logs(from: context, enabled: request.capturesLogs))
    }

    private func makeJSONObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func takeException(_ exception: inout JSValue?) -> JSValue? {
        defer { exception = nil }
        return exception
    }

    private func errorPayload(
        from exception: JSValue,
        includesDetails: Bool
    ) -> PluginRuntimeErrorPayload {
        let codeValue = exception.objectForKeyedSubscript("code")
        let messageValue = exception.objectForKeyedSubscript("message")
        let code = codeValue?.isString == true ? codeValue?.toString() : nil
        let message = messageValue?.isString == true ? messageValue?.toString() : nil
        let safeCode = code?.range(of: #"^[a-z][a-z0-9_]{0,63}$"#, options: .regularExpression) != nil
            ? code!
            : "runtime_exception"

        return PluginRuntimeErrorPayload(
            code: safeCode,
            message: clipped(message ?? "插件执行失败", maximum: 500),
            sourceLocation: includesDetails
                ? clipped(exception.toString() ?? "", maximum: 500)
                : nil
        )
    }

    private func logs(from context: JSContext, enabled: Bool) -> [String] {
        guard enabled,
              let value = context.evaluateScript("__clipallTakeLogs()"),
              let rawLogs = value.toArray() as? [String] else {
            return []
        }
        return rawLogs.prefix(PluginRuntimeLimits.maximumLogEntries).map {
            clipped($0, maximum: PluginRuntimeLimits.maximumLogEntryCharacters)
        }
    }

    private func validate(_ result: PluginRuntimeResult) -> PluginRuntimeErrorPayload? {
        guard !result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.title.count <= 120,
              (result.subtitle?.count ?? 0) <= 500,
              !result.items.isEmpty,
              result.items.count <= PluginRuntimeLimits.maximumResultItems else {
            return .init(code: "invalid_output", message: "插件结果结构不符合要求")
        }

        var ids: Set<String> = []
        for item in result.items {
            guard item.id.range(of: #"^[A-Za-z][A-Za-z0-9._-]{0,79}$"#, options: .regularExpression) != nil,
                  ids.insert(item.id).inserted,
                  !item.label.isEmpty,
                  item.label.count <= 80,
                  item.value.count <= PluginRuntimeLimits.maximumResultStringCharacters,
                  (item.annotation?.count ?? 0) <= 240 else {
                return .init(code: "invalid_output", message: "插件结果项目不符合要求")
            }
        }
        return nil
    }

    private func sanitizedSourceName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(sanitized.prefix(120))
    }

    private func clipped(_ value: String, maximum: Int) -> String {
        String(value.prefix(maximum))
    }

    private static let bootstrapScript = #"""
    (function (global) {
      "use strict";
      var logs = [];
      function append(level, values) {
        var text = Array.prototype.map.call(values, function (value) {
          try {
            return typeof value === "string" ? value : JSON.stringify(value);
          } catch (_) {
            return String(value);
          }
        }).join(" ");
        logs.push(level + ": " + text);
      }
      var memoryConsole = Object.freeze({
        log: function () { append("log", arguments); },
        warn: function () { append("warn", arguments); },
        error: function () { append("error", arguments); }
      });
      Object.defineProperty(global, "console", {
        value: memoryConsole,
        configurable: false,
        enumerable: true,
        writable: false
      });
      Object.defineProperty(global, "__clipallTakeLogs", {
        value: function () { return logs.slice(); },
        configurable: false,
        enumerable: false,
        writable: false
      });
      if (__clipallRequest.configuration) Object.freeze(__clipallRequest.configuration);
      Object.freeze(__clipallRequest);
    })(globalThis);
    """#
}
