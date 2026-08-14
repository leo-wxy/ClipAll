import ClipAllPluginProtocol
import Foundation

private struct PluginRuntimeEnvelope: Decodable {
    let protocolVersion: Int
}

let input = FileHandle.standardInput.readDataToEndOfFile()
let response: PluginRuntimeResponse

if input.count > PluginRuntimeLimits.maximumRequestBytes {
    response = .failure(.init(code: "request_too_large", message: "插件请求超过运行上限"))
} else if let envelope = try? JSONDecoder().decode(PluginRuntimeEnvelope.self, from: input),
          envelope.protocolVersion != PluginRuntimeLimits.protocolVersion {
    response = .failure(.init(code: "unsupported_protocol", message: "插件运行协议版本不受支持"))
} else if let request = try? JSONDecoder().decode(PluginRuntimeRequest.self, from: input) {
    response = JavaScriptPluginRuntime().execute(request)
} else {
    response = .failure(.init(code: "invalid_request", message: "无法读取插件运行请求"))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = (try? encoder.encode(response)) ?? Data(
    #"{"protocolVersion":2,"status":"failure","error":{"code":"encoding_failure","message":"无法编码插件结果"},"logs":[]}"#.utf8
)
FileHandle.standardOutput.write(data)
