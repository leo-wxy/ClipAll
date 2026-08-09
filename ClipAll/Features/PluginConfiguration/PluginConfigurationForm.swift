import Combine
import SwiftUI

struct PluginConfigurationForm: View {
    let descriptor: PluginDescriptor
    @ObservedObject var configurationStore: PluginConfigurationStore
    let secretStore: PluginSecretStore

    var body: some View {
        if descriptor.configurationFields.isEmpty {
            Text("这个插件没有配置项。")
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visibleFields.enumerated()), id: \.element.id) { index, field in
                    fieldView(field)
                    if index < visibleFields.count - 1 { Divider() }
                }
            }
        }
    }

    private var visibleFields: [PluginConfigurationField] {
        descriptor.configurationFields.filter {
            configurationStore.isVisible($0, pluginID: descriptor.id)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: PluginConfigurationField) -> some View {
        HStack(alignment: .center, spacing: ClipAllTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.title)
                    .font(.callout.weight(.semibold))
                if let summary = field.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 230, alignment: .leading)

            Spacer(minLength: ClipAllTheme.Spacing.md)

            switch field.kind {
            case let .choice(options):
                Picker("", selection: stringBinding(field)) {
                    ForEach(options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 250)
            case .toggle:
                Toggle("", isOn: boolBinding(field))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
            case let .text(placeholder):
                TextField(placeholder ?? "", text: stringBinding(field))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            case let .secret(placeholder):
                SecretConfigurationField(
                    pluginID: descriptor.id,
                    field: field,
                    placeholder: placeholder,
                    secretStore: secretStore
                )
            }
        }
        .padding(.horizontal, ClipAllTheme.Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stringBinding(_ field: PluginConfigurationField) -> Binding<String> {
        Binding(
            get: {
                configurationStore.string(
                    pluginID: descriptor.id,
                    fieldID: field.id,
                    fallback: field.defaultValue.stringValue ?? ""
                )
            },
            set: { value in
                try? configurationStore.set(.string(value), pluginID: descriptor.id, fieldID: field.id)
            }
        )
    }

    private func boolBinding(_ field: PluginConfigurationField) -> Binding<Bool> {
        Binding(
            get: {
                configurationStore.bool(
                    pluginID: descriptor.id,
                    fieldID: field.id,
                    fallback: field.defaultValue.boolValue ?? false
                )
            },
            set: { value in
                try? configurationStore.set(.bool(value), pluginID: descriptor.id, fieldID: field.id)
            }
        )
    }
}

private struct SecretConfigurationField: View {
    let pluginID: PluginID
    let field: PluginConfigurationField
    let placeholder: String?
    let secretStore: PluginSecretStore

    @StateObject private var model: SecretConfigurationFieldModel

    init(
        pluginID: PluginID,
        field: PluginConfigurationField,
        placeholder: String?,
        secretStore: PluginSecretStore
    ) {
        self.pluginID = pluginID
        self.field = field
        self.placeholder = placeholder
        self.secretStore = secretStore
        _model = StateObject(wrappedValue: SecretConfigurationFieldModel(
            pluginID: pluginID,
            fieldID: field.id,
            secretStore: secretStore
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField(model.isStored ? "已设置，输入新值可替换" : (placeholder ?? ""), text: $model.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("保存") { model.save() }
                    .disabled(model.value.isEmpty)
                if model.isStored {
                    Button("清除", role: .destructive) { model.clear() }
                }
            }
            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 360, alignment: .leading)
    }
}

@MainActor
private final class SecretConfigurationFieldModel: ObservableObject {
    @Published var value = ""
    @Published private(set) var isStored: Bool
    @Published private(set) var message: String?

    private let pluginID: PluginID
    private let fieldID: String
    private let secretStore: PluginSecretStore

    init(pluginID: PluginID, fieldID: String, secretStore: PluginSecretStore) {
        self.pluginID = pluginID
        self.fieldID = fieldID
        self.secretStore = secretStore
        isStored = secretStore.hasSecret(pluginID: pluginID, fieldID: fieldID)
    }

    func save() {
        do {
            try secretStore.setSecret(value, pluginID: pluginID, fieldID: fieldID)
            value = ""
            isStored = true
            message = "已保存到 Keychain"
        } catch {
            message = error.localizedDescription
        }
    }

    func clear() {
        do {
            try secretStore.deleteSecret(pluginID: pluginID, fieldID: fieldID)
            value = ""
            isStored = false
            message = "已从 Keychain 清除"
        } catch {
            message = error.localizedDescription
        }
    }
}
