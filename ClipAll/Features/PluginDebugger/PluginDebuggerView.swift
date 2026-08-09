import ClipAllPluginProtocol
import SwiftUI

struct PluginDebuggerView: View {
    @ObservedObject var session: PluginDebugSession
    @ObservedObject var configurationStore: PluginConfigurationStore
    let secretStore: PluginSecretStore

    var body: some View {
        VStack(spacing: 0) {
            debuggerHeader
            Divider()
            HSplitView {
                inputPane
                    .frame(minWidth: 360, idealWidth: 430)
                resultPane
                    .frame(minWidth: 440, idealWidth: 520)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(ClipAllTheme.canvas)
        .tint(ClipAllTheme.accent)
    }

    private var debuggerHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "ladybug")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ClipAllTheme.accent)
                .frame(width: 38, height: 38)
                .background(ClipAllTheme.accent.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("插件调试器")
                    .font(.headline)
                Text(session.package.definition.descriptor.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let duration = session.durationMilliseconds {
                Text(String(format: "%.1f ms", duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button("运行 Fixtures") {
                Task { await session.runFixtures() }
            }
            .disabled(session.isRunning)
            Button("运行") {
                Task { await session.executeSelected() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(session.isRunning)
        }
        .padding(16)
    }

    private var inputPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("能力", selection: $session.selectedCapabilityID) {
                    ForEach(session.capabilities, id: \.descriptor.id) { capability in
                        Text(capability.descriptor.name).tag(capability.descriptor.id)
                    }
                }

                if !session.package.definition.descriptor.configurationFields.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("当前配置")
                            .font(.headline)
                        PluginConfigurationForm(
                            descriptor: session.package.definition.descriptor,
                            configurationStore: configurationStore,
                            secretStore: secretStore
                        )
                        .padding(12)
                        .background(
                            ClipAllTheme.quietFill,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("输入")
                        .font(.headline)
                    TextEditor(text: $session.input)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(ClipAllTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ClipAllTheme.border)
                        }
                        .onChange(of: session.input) { _, _ in session.analyze() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("内容特征")
                            .font(.headline)
                        Spacer()
                        Button("重新分析") { session.analyze() }
                    }
                    Text(featureSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("匹配结果")
                        .font(.headline)
                    if session.matches.isEmpty {
                        Text("当前输入没有匹配到能力规则。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.matches) { match in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.capability.name)
                                        .fontWeight(.medium)
                                    Text(match.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(match.score)")
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                            }
                            .padding(10)
                            .background(
                                ClipAllTheme.quietFill,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(ClipAllTheme.sidebar)
    }

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if session.isRunning {
                    ProgressView("正在执行…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = session.runtimeError {
                    debugSection("错误") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.code)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.red)
                            Text(error.message)
                            if let location = error.sourceLocation {
                                Text(location)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let output = session.output {
                    debugSection("输出") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(output.title)
                                .font(.headline)
                            if let subtitle = output.subtitle {
                                Text(subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(output.items, id: \.id) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.value)
                                        .font(item.style == .monospaced ? .system(.body, design: .monospaced) : .body)
                                        .textSelection(.enabled)
                                    if let annotation = item.annotation {
                                        Text(annotation)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    ClipAllTheme.quietFill,
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                            }
                        }
                    }
                }

                if !session.fixtureResults.isEmpty {
                    debugSection("Fixtures") {
                        VStack(spacing: 7) {
                            ForEach(session.fixtureResults) { result in
                                HStack {
                                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.passed ? .green : .red)
                                    Text(result.id)
                                    Spacer()
                                    Text(result.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                debugSection("日志") {
                    if session.logs.isEmpty {
                        Text("本次执行没有日志。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(session.logs.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(18)
        }
    }

    private var featureSummary: String {
        guard let features = session.features else { return "尚未分析" }
        let kinds = features.kinds.map(\.rawValue).sorted().joined(separator: ", ")
        return "类型：\(kinds.isEmpty ? "无" : kinds)\n语言：\(features.languageIdentifier ?? "未知")"
    }

    private func debugSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipAllSurface(cornerRadius: 12)
    }
}
