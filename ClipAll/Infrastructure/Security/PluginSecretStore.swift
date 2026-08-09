import Foundation
import Security

@MainActor
protocol PluginSecretProviding: AnyObject {
    func secret(pluginID: PluginID, fieldID: String) throws -> String?
}

@MainActor
final class PluginSecretStore: PluginSecretProviding {
    enum SecretError: Error, LocalizedError, Equatable {
        case keychain(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case let .keychain(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 错误：\(status)"
            case .invalidData:
                "Keychain 中的配置无法读取"
            }
        }
    }

    private let service: String

    init(service: String = "com.wxy.ClipAll.plugin-config") {
        self.service = service
    }

    func setSecret(_ secret: String, pluginID: PluginID, fieldID: String) throws {
        if secret.isEmpty {
            try deleteSecret(pluginID: pluginID, fieldID: fieldID)
            return
        }

        let account = account(pluginID: pluginID, fieldID: fieldID)
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretError.keychain(addStatus) }
        default:
            throw SecretError.keychain(updateStatus)
        }
    }

    func secret(pluginID: PluginID, fieldID: String) throws -> String? {
        var query = baseQuery(account: account(pluginID: pluginID, fieldID: fieldID))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretError.invalidData
        }
        return value
    }

    func hasSecret(pluginID: PluginID, fieldID: String) -> Bool {
        (try? secret(pluginID: pluginID, fieldID: fieldID)) != nil
    }

    func deleteSecret(pluginID: PluginID, fieldID: String) throws {
        let status = SecItemDelete(
            baseQuery(account: account(pluginID: pluginID, fieldID: fieldID)) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretError.keychain(status)
        }
    }

    private func account(pluginID: PluginID, fieldID: String) -> String {
        "\(pluginID.rawValue).\(fieldID)"
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
