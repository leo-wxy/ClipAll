import Foundation

struct PluginInstallationReceipt: Codable, Equatable, Sendable {
    let pluginID: PluginID
    let version: String
    let fingerprint: String
    let installedAt: Date
}

struct PreparedPluginImport: Identifiable, Sendable {
    var id: UUID { token }
    let token: UUID
    let sourceDisplayName: String
    let stagingURL: URL
    let package: ValidatedExternalPluginPackage
    let replacesExistingPlugin: Bool
}

enum InstalledPluginLoadResult: Sendable {
    case valid(ValidatedExternalPluginPackage)
    case invalid(packageURL: URL, issue: PluginValidationIssue)
}

enum PluginInstallationError: Error, LocalizedError, Equatable, Sendable {
    case unknownPreparation
    case pluginAlreadyInstalled(PluginID)
    case pluginNotInstalled(PluginID)
    case receiptMismatch(PluginID)
    case transactionFailed

    var errorDescription: String? {
        switch self {
        case .unknownPreparation:
            "插件安装准备已失效，请重新导入"
        case let .pluginAlreadyInstalled(id):
            "插件已安装：\(id.rawValue)"
        case let .pluginNotInstalled(id):
            "插件尚未安装：\(id.rawValue)"
        case let .receiptMismatch(id):
            "插件文件在安装后发生变化：\(id.rawValue)"
        case .transactionFailed:
            "插件安装事务失败，原版本已保留"
        }
    }
}

actor PluginInstallationStore {
    private let rootDirectory: URL
    private let installedDirectory: URL
    private let stagingDirectory: URL
    private let receiptsDirectory: URL
    private let validator: PluginPackageValidator
    private var preparedURLs: [UUID: URL] = [:]

    init(rootDirectory: URL, validator: PluginPackageValidator = PluginPackageValidator()) {
        self.rootDirectory = rootDirectory
        installedDirectory = rootDirectory.appendingPathComponent("Installed", isDirectory: true)
        stagingDirectory = rootDirectory.appendingPathComponent(".Staging", isDirectory: true)
        receiptsDirectory = rootDirectory.appendingPathComponent("Receipts", isDirectory: true)
        self.validator = validator
    }

    func prepareImport(from sourceURL: URL) throws -> PreparedPluginImport {
        try ensureDirectories()
        _ = try validator.validate(packageURL: sourceURL, source: .installed)

        let token = UUID()
        let operationDirectory = stagingDirectory.appendingPathComponent(token.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: operationDirectory, withIntermediateDirectories: false)
        let stagedURL = operationDirectory.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: true
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
            let package = try validator.validate(packageURL: stagedURL, source: .installed)
            preparedURLs[token] = stagedURL
            return PreparedPluginImport(
                token: token,
                sourceDisplayName: sourceURL.lastPathComponent,
                stagingURL: stagedURL,
                package: package,
                replacesExistingPlugin: FileManager.default.fileExists(
                    atPath: installedURL(for: package.definition.descriptor.id).path
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: operationDirectory)
            throw error
        }
    }

    func discard(_ prepared: PreparedPluginImport) {
        guard preparedURLs.removeValue(forKey: prepared.token) == prepared.stagingURL else { return }
        try? FileManager.default.removeItem(at: prepared.stagingURL.deletingLastPathComponent())
    }

    func commit(
        _ prepared: PreparedPluginImport,
        replacingExisting: Bool
    ) throws -> ValidatedExternalPluginPackage {
        guard preparedURLs[prepared.token] == prepared.stagingURL else {
            throw PluginInstallationError.unknownPreparation
        }

        let operationDirectory = prepared.stagingURL.deletingLastPathComponent()
        defer {
            // A preparation is single-use.  This also clears failed validation,
            // duplicate-install, and transaction paths instead of leaving a
            // token that points at a directory which is no longer usable.
            preparedURLs.removeValue(forKey: prepared.token)
            try? FileManager.default.removeItem(at: operationDirectory)
        }
        try ensureDirectories()

        let staged = try validator.validate(packageURL: prepared.stagingURL, source: .installed)
        let pluginID = staged.definition.descriptor.id
        let destination = installedURL(for: pluginID)
        let receipt = receiptURL(for: pluginID)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        guard replacingExisting || !exists else {
            throw PluginInstallationError.pluginAlreadyInstalled(pluginID)
        }

        let backupPackage = operationDirectory.appendingPathComponent("Previous.clipallplugin", isDirectory: true)
        let backupReceipt = operationDirectory.appendingPathComponent("Previous.receipt.json")
        var movedPreviousPackage = false
        var movedPreviousReceipt = false
        var installedNewPackage = false
        var attemptedNewReceiptWrite = false

        do {
            if exists {
                try FileManager.default.moveItem(at: destination, to: backupPackage)
                movedPreviousPackage = true
            }
            if FileManager.default.fileExists(atPath: receipt.path) {
                try FileManager.default.moveItem(at: receipt, to: backupReceipt)
                movedPreviousReceipt = true
            }

            try FileManager.default.moveItem(at: prepared.stagingURL, to: destination)
            installedNewPackage = true
            let installed = try validator.validate(packageURL: destination, source: .installed)
            let newReceipt = PluginInstallationReceipt(
                pluginID: pluginID,
                version: installed.definition.descriptor.version,
                fingerprint: installed.fingerprint,
                installedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            attemptedNewReceiptWrite = true
            try encoder.encode(newReceipt).write(to: receipt, options: .atomic)
            return installed
        } catch {
            // Remove a newly written receipt before restoring the previous one.
            // Without this, restoring a backed-up receipt can fail because the
            // destination path is still occupied by the new receipt.
            if attemptedNewReceiptWrite {
                try? FileManager.default.removeItem(at: receipt)
            }
            if installedNewPackage {
                try? FileManager.default.removeItem(at: destination)
            }
            if movedPreviousPackage {
                try? FileManager.default.moveItem(at: backupPackage, to: destination)
            }
            if movedPreviousReceipt {
                try? FileManager.default.moveItem(at: backupReceipt, to: receipt)
            }
            throw PluginInstallationError.transactionFailed
        }
    }

    func loadInstalled() throws -> [InstalledPluginLoadResult] {
        try ensureDirectories()
        let urls = try FileManager.default.contentsOfDirectory(
            at: installedDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension.lowercased() == "clipallplugin" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                do {
                    let package = try validator.validate(packageURL: url, source: .installed)
                    let receipt = try loadReceipt(pluginID: package.definition.descriptor.id)
                    guard receipt.pluginID == package.definition.descriptor.id,
                          receipt.version == package.definition.descriptor.version,
                          receipt.fingerprint == package.fingerprint else {
                        throw PluginInstallationError.receiptMismatch(package.definition.descriptor.id)
                    }
                    return .valid(package)
                } catch let issue as PluginValidationIssue {
                    return .invalid(packageURL: url, issue: issue)
                } catch let error as PluginInstallationError {
                    return .invalid(
                        packageURL: url,
                        issue: PluginValidationIssue(
                            code: "receipt_mismatch",
                            message: error.localizedDescription,
                            location: url.lastPathComponent
                        )
                    )
                } catch {
                    return .invalid(
                        packageURL: url,
                        issue: PluginValidationIssue(
                            code: "package_read",
                            message: "无法载入已安装插件",
                            location: url.lastPathComponent
                        )
                    )
                }
            }
    }

    func validateInstalled(pluginID: PluginID) throws -> ValidatedExternalPluginPackage {
        try ensureDirectories()
        let destination = installedURL(for: pluginID)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw PluginInstallationError.pluginNotInstalled(pluginID)
        }
        let package = try validator.validate(packageURL: destination, source: .installed)
        let receipt = try loadReceipt(pluginID: pluginID)
        guard receipt.pluginID == pluginID,
              receipt.pluginID == package.definition.descriptor.id,
              receipt.version == package.definition.descriptor.version,
              receipt.fingerprint == package.fingerprint else {
            throw PluginInstallationError.receiptMismatch(pluginID)
        }
        return package
    }

    func uninstall(pluginID: PluginID) throws {
        try ensureDirectories()
        let package = installedURL(for: pluginID)
        let receipt = receiptURL(for: pluginID)
        guard FileManager.default.fileExists(atPath: package.path) else {
            throw PluginInstallationError.pluginNotInstalled(pluginID)
        }

        let operationDirectory = stagingDirectory.appendingPathComponent(
            "Uninstall-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: operationDirectory, withIntermediateDirectories: false)
        let stagedPackage = operationDirectory.appendingPathComponent(package.lastPathComponent, isDirectory: true)
        let stagedReceipt = operationDirectory.appendingPathComponent("receipt.json")
        var movedPackage = false
        var movedReceipt = false

        defer {
            // Success removes this directory in the transaction body; on a
            // failed uninstall this guarantees no half-completed operation is
            // retained after the original files have been restored.
            try? FileManager.default.removeItem(at: operationDirectory)
        }

        do {
            try FileManager.default.moveItem(at: package, to: stagedPackage)
            movedPackage = true
            if FileManager.default.fileExists(atPath: receipt.path) {
                try FileManager.default.moveItem(at: receipt, to: stagedReceipt)
                movedReceipt = true
            }
            try FileManager.default.removeItem(at: operationDirectory)
        } catch {
            if movedPackage, FileManager.default.fileExists(atPath: stagedPackage.path) {
                try? FileManager.default.moveItem(at: stagedPackage, to: package)
            }
            if movedReceipt, FileManager.default.fileExists(atPath: stagedReceipt.path) {
                try? FileManager.default.moveItem(at: stagedReceipt, to: receipt)
            }
            throw PluginInstallationError.transactionFailed
        }
    }

    private func ensureDirectories() throws {
        for directory in [rootDirectory, installedDirectory, stagingDirectory, receiptsDirectory] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        cleanupOrphanedStaging()
    }

    private func cleanupOrphanedStaging() {
        let activeOperationPaths = Set(
            preparedURLs.values.map {
                $0.deletingLastPathComponent().standardizedFileURL.path
            }
        )
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return
        }

        for entry in entries where !activeOperationPaths.contains(entry.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func installedURL(for pluginID: PluginID) -> URL {
        installedDirectory.appendingPathComponent(
            "\(pluginID.rawValue).clipallplugin",
            isDirectory: true
        )
    }

    private func receiptURL(for pluginID: PluginID) -> URL {
        receiptsDirectory.appendingPathComponent("\(pluginID.rawValue).json")
    }

    private func loadReceipt(pluginID: PluginID) throws -> PluginInstallationReceipt {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(
                PluginInstallationReceipt.self,
                from: Data(contentsOf: receiptURL(for: pluginID))
            )
        } catch {
            throw PluginInstallationError.receiptMismatch(pluginID)
        }
    }
}
