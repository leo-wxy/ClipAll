import ClipAllPluginProtocol
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let response: PluginRuntimeResponse

if input.count > PluginRuntimeLimits.maximumRequestBytes {
    response = .failure(.init(code: "request_too_large", message: "插件请求超过运行上限"))
} else if let request = try? JSONDecoder().decode(PluginRuntimeRequest.self, from: input) {
    response = JavaScriptPluginRuntime().execute(request)
} else {
    response = .failure(.init(code: "invalid_request", message: "无法读取插件运行请求"))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = (try? encoder.encode(response)) ?? Data(
    #"{"protocolVersion":1,"status":"failure","error":{"code":"encoding_failure","message":"无法编码插件结果"},"logs":[]}"#.utf8
)
FileHandle.standardOutput.write(data)
