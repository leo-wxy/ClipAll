import ClipAllPluginProtocol
import Combine
import Foundation

struct PluginDebugFixture: Decodable, Identifiable, Sendable {
    struct Expectation: Decodable, Sendable {
        let subtitle: String?
        let itemValues: [String: String]
    }

    var id: String { name }
    let name: String
    let capabilityID: CapabilityID
    let input: String
    let configuration: [String: PluginRuntimeConfigurationValue]
    let systemTimeZoneIdentifier: String?
    let expect: Expectation?
    let expectError: String?
}

struct PluginDebugFixtureResult: Identifiable, Sendable {
    let id: String
    let passed: Bool
    let detail: String
}

@MainActor
final class PluginDebugSession: ObservableObject {
    @Published var input: String
    @Published var selectedCapabilityID: CapabilityID
    @Published private(set) var features: ContentFeatures?
    @Published private(set) var matches: [CapabilityMatch] = []
    @Published private(set) var output: PluginRuntimeResult?
    @Published private(set) var runtimeError: PluginRuntimeErrorPayload?
    @Published private(set) var logs: [String] = []
    @Published private(set) var durationMilliseconds: Double?
    @Published private(set) var fixtureResults: [PluginDebugFixtureResult] = []
    @Published private(set) var isRunning = false

    let package: ValidatedExternalPluginPackage

    private let configurationStore: PluginConfigurationStore
    private let runnerClient: PluginRunnerClient
    private let featureExtractor = ContentFeatureExtractor()
    private let router = CapabilityRouter()

    init(
        package: ValidatedExternalPluginPackage,
        configurationStore: PluginConfigurationStore,
        runnerClient: PluginRunnerClient
    ) {
        precondition(!package.definition.capabilities.isEmpty)
        self.package = package
        self.configurationStore = configurationStore
        self.runnerClient = runnerClient
        selectedCapabilityID = package.definition.capabilities[0].descriptor.id
        input = package.definition.capabilities[0].descriptor.examples.first ?? ""
        analyze()
    }

    var capabilities: [ExternalCapabilityDefinition] {
        package.definition.capabilities
    }

    func analyze(targetLanguageIdentifier: String = "zh") {
        let extracted = featureExtractor.extract(
            from: input,
            targetLanguageIdentifier: targetLanguageIdentifier
        )
        features = extracted
        matches = router.route(
            descriptors: package.definition.capabilities.map(\.descriptor),
            features: extracted,
            sourceText: input,
            pinnedCapabilityIDs: []
        ).rankedMatches
    }

    func executeSelected() async {
        guard !isRunning else { return }
        guard let capability = package.definition.capabilities.first(where: {
            $0.descriptor.id == selectedCapabilityID
        }) else { return }

        isRunning = true
        defer { isRunning = false }
        output = nil
        runtimeError = nil
        logs = []
        durationMilliseconds = nil
        analyze()

        do {
            let execution = try await runnerClient.execute(request(
                capability: capability,
                text: input,
                configuration: currentConfiguration(),
                systemTimeZoneIdentifier: TimeZone.current.identifier
            ))
            output = execution.response.output
            runtimeError = execution.response.error
            logs = execution.response.logs
            durationMilliseconds = milliseconds(execution.duration)
        } catch {
            runtimeError = PluginRuntimeErrorPayload(
                code: "runner_failure",
                message: error.localizedDescription
            )
        }
    }

    func runFixtures() async {
        guard !isRunning else { return }
        fixtureResults = []
        guard let fixtures = loadFixtures() else {
            fixtureResults = [PluginDebugFixtureResult(
                id: "fixtures_missing",
                passed: false,
                detail: "插件没有可读取的 Tests/cases.json"
            )]
            return
        }

        isRunning = true
        defer { isRunning = false }
        var results: [PluginDebugFixtureResult] = []
        for fixture in fixtures {
            guard let capability = package.definition.capabilities.first(where: {
                $0.descriptor.id == fixture.capabilityID
            }) else {
                results.append(.init(id: fixture.name, passed: false, detail: "能力不存在"))
                continue
            }
            do {
                let execution = try await runnerClient.execute(request(
                    capability: capability,
                    text: fixture.input,
                    configuration: fixture.configuration,
                    systemTimeZoneIdentifier: fixture.systemTimeZoneIdentifier ?? "UTC"
                ))
                results.append(verify(fixture: fixture, response: execution.response))
            } catch {
                results.append(.init(id: fixture.name, passed: false, detail: error.localizedDescription))
            }
        }
        fixtureResults = results
    }

    private func request(
        capability: ExternalCapabilityDefinition,
        text: String,
        configuration: [String: PluginRuntimeConfigurationValue],
        systemTimeZoneIdentifier: String
    ) -> PluginRuntimeRequest {
        PluginRuntimeRequest(
            script: package.script,
            sourceName: package.definition.runtimeEntry,
            handler: capability.handler,
            input: PluginRuntimeInput(
                text: text,
                configuration: configuration,
                localeIdentifier: Locale.current.identifier,
                systemTimeZoneIdentifier: systemTimeZoneIdentifier
            ),
            capturesLogs: true
        )
    }

    private func currentConfiguration() -> [String: PluginRuntimeConfigurationValue] {
        configurationStore.resolvedValues(pluginID: package.definition.descriptor.id).reduce(into: [:]) {
            result, pair in
            switch pair.value {
            case let .string(value): result[pair.key] = .string(value)
            case let .bool(value): result[pair.key] = .bool(value)
            }
        }
    }

    private func loadFixtures() -> [PluginDebugFixture]? {
        let url = package.packageURL.appendingPathComponent("Tests/cases.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([PluginDebugFixture].self, from: data)
    }

    private func verify(
        fixture: PluginDebugFixture,
        response: PluginRuntimeResponse
    ) -> PluginDebugFixtureResult {
        if let expectedError = fixture.expectError {
            let actual = response.error?.code
            return PluginDebugFixtureResult(
                id: fixture.name,
                passed: response.status == .failure && actual == expectedError,
                detail: actual == expectedError ? expectedError : "期望 \(expectedError)，实际 \(actual ?? "success")"
            )
        }

        guard response.status == .success,
              let output = response.output,
              let expectation = fixture.expect else {
            return .init(
                id: fixture.name,
                passed: false,
                detail: response.error?.code ?? "invalid_response"
            )
        }
        if let subtitle = expectation.subtitle, subtitle != output.subtitle {
            return .init(id: fixture.name, passed: false, detail: "subtitle 不匹配")
        }
        let values = Dictionary(uniqueKeysWithValues: output.items.map { ($0.id, $0.value) })
        if let mismatch = expectation.itemValues.first(where: { values[$0.key] != $0.value }) {
            return .init(id: fixture.name, passed: false, detail: "\(mismatch.key) 不匹配")
        }
        return .init(id: fixture.name, passed: true, detail: "通过")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
