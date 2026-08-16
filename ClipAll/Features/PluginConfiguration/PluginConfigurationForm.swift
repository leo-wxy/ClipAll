import Combine
import SwiftUI

struct PluginConfigurationForm: View {
    let descriptor: PluginDescriptor
    @ObservedObject var configurationStore: PluginConfigurationStore
    let secretStore: PluginSecretStore

    var body: some View {
        if descriptor.configurationFields.isEmpty {
            ClipAllEmptyState(
                title: "无需配置",
                systemImage: "checkmark.circle",
                message: "这个插件安装后即可使用。",
                minimumHeight: 80
            )
        } else {
            VStack(spacing: ClipAllTheme.Spacing.xs) {
                ForEach(visibleFields) { field in
                    fieldView(field)
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
        ClipAllSettingsRow(alignment: .top, minimumHeight: 68) {
            VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xxs) {
                Text(field.title)
                    .font(ClipAllTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(ClipAllTheme.textPrimary)
                if let summary = field.summary {
                    Text(summary)
                        .font(ClipAllTheme.Typography.supporting)
                        .foregroundStyle(ClipAllTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(
                minWidth: 140,
                idealWidth: 190,
                maxWidth: ClipAllTheme.Size.formLabel,
                alignment: .leading
            )
        } trailing: {
            switch field.kind {
            case let .choice(options):
                let selection = stringBinding(field)
                Menu {
                    ForEach(options) { option in
                        Button {
                            selection.wrappedValue = option.id
                        } label: {
                            if selection.wrappedValue == option.id {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: ClipAllTheme.Spacing.xs) {
                        Text(
                            options.first(where: { $0.id == selection.wrappedValue })?.title
                                ?? selection.wrappedValue
                        )
                            .foregroundStyle(ClipAllTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: ClipAllTheme.Spacing.xs)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ClipAllTheme.textSecondary)
                    }
                    .clipAllControlSlot()
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(field.title)
                .frame(
                    minWidth: 180,
                    idealWidth: 260,
                    maxWidth: ClipAllTheme.Size.formControl
                )
            case .toggle:
                Toggle("", isOn: boolBinding(field))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(field.title)
                    .frame(
                        minWidth: 180,
                        idealWidth: 260,
                        maxWidth: ClipAllTheme.Size.formControl,
                        alignment: .trailing
                    )
            case let .text(placeholder):
                TextField(placeholder ?? "", text: stringBinding(field))
                    .textFieldStyle(.plain)
                    .clipAllControlSlot()
                    .accessibilityLabel(field.title)
                    .frame(
                        minWidth: 180,
                        idealWidth: 260,
                        maxWidth: ClipAllTheme.Size.formControl
                    )
            case let .secret(placeholder):
                SecretConfigurationField(
                    pluginID: descriptor.id,
                    field: field,
                    placeholder: placeholder,
                    secretStore: secretStore
                )
            }
        }
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
        VStack(alignment: .leading, spacing: ClipAllTheme.Spacing.xs) {
            HStack(spacing: ClipAllTheme.Spacing.xs) {
                SecureField(
                    model.isStored ? "已设置，输入新值可替换" : (placeholder ?? ""),
                    text: $model.value
                )
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(field.title)

                if model.isStored {
                    ClipAllTag("已保存", tone: .success, systemImage: "key.fill")
                }

                Button("保存") { model.save() }
                    .buttonStyle(ClipAllButtonStyle(variant: .primary))
                    .disabled(model.value.isEmpty)
                if model.isStored {
                    Button("清除", role: .destructive) { model.clear() }
                        .buttonStyle(.borderless)
                }
            }
            .clipAllControlSlot(minimumHeight: 40)

            if let message = model.message {
                Text(message)
                    .font(ClipAllTheme.Typography.supporting)
                    .foregroundStyle(ClipAllTheme.textSecondary)
            }
        }
        .frame(
            minWidth: 180,
            idealWidth: 260,
            maxWidth: ClipAllTheme.Size.formControl,
            alignment: .leading
        )
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
