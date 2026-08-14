import ClipAllPluginProtocol
import Foundation

@MainActor
final class ExternalPluginExecutor: CapabilityExecuting {
    let descriptor: CapabilityDescriptor

    private let handler: String
    private let script: String
    private let sourceName: String
    private let configurationStore: PluginConfigurationStore
    private let runnerClient: PluginRunnerClient

    init(
        definition: ExternalCapabilityDefinition,
        script: String,
        sourceName: String,
        configurationStore: PluginConfigurationStore,
        runnerClient: PluginRunnerClient
    ) {
        descriptor = definition.descriptor
        handler = definition.handler
        self.script = script
        self.sourceName = sourceName
        self.configurationStore = configurationStore
        self.runnerClient = runnerClient
    }

    func availability(for context: SelectionContext) -> CapabilityAvailability {
        guard !context.normalizedText.isEmpty else {
            return .unavailable(reason: "当前没有可处理的文字")
        }
        guard context.normalizedText.utf8.count <= CapabilityInputLimits.maximumTextBytes else {
            return .unavailable(reason: "所选文字超过插件处理上限")
        }
        return .available
    }

    func execute(in context: SelectionContext) async throws -> CapabilityOutput {
        guard case .available = availability(for: context) else {
            throw CapabilityError.unsupportedInput("当前文字无法交给该插件处理")
        }

        let request = PluginRuntimeRequest(
            script: script,
            sourceName: sourceName,
            handler: handler,
            input: PluginRuntimeInput(
                pluginID: descriptor.pluginID.rawValue,
                text: context.normalizedText,
                configuration: runtimeConfiguration()
            ),
            capturesLogs: false
        )
        let execution: PluginRunnerExecution
        do {
            execution = try await runnerClient.execute(request)
        } catch let error as PluginRunnerClientError {
            throw CapabilityError.unavailable(error.localizedDescription)
        }

        switch execution.response.status {
        case .success:
            guard let result = execution.response.output else {
                throw CapabilityError.unavailable("插件没有返回结果")
            }
            return .result(map(result))
        case .failure:
            let error = execution.response.error ?? PluginRuntimeErrorPayload(
                code: "runtime_failure",
                message: "插件执行失败"
            )
            switch error.code {
            case "invalid_input", "out_of_range":
                throw CapabilityError.invalidInput(error.message)
            case "invalid_configuration":
                throw CapabilityError.unavailable(error.message)
            default:
                throw CapabilityError.unavailable("插件执行失败：\(error.message)")
            }
        }
    }

    private func runtimeConfiguration() -> [String: PluginRuntimeConfigurationValue] {
        configurationStore.resolvedValues(pluginID: descriptor.pluginID).reduce(into: [:]) { result, pair in
            switch pair.value {
            case let .string(value):
                result[pair.key] = .string(value)
            case let .bool(value):
                result[pair.key] = .bool(value)
            }
        }
    }

    private func map(_ result: PluginRuntimeResult) -> CapabilityResult {
        CapabilityResult(
            title: result.title,
            subtitle: result.subtitle,
            items: result.items.map { item in
                CapabilityResultItem(
                    id: item.id,
                    label: item.label,
                    value: item.value,
                    annotation: item.annotation,
                    style: item.style == .monospaced ? .monospaced : .body
                )
            }
        )
    }
}
