import Foundation

struct PluginInstallationReceipt: Codable, Equatable, Sendable {
    let pluginID: PluginID
    let version: String
    let fingerprint: String
}

struct PreparedPluginImport: Identifiable, Sendable {
    var id: UUID { token }
    let token: UUID
    let sourceDisplayName: String
    let stagingURL: URL
    let package: ValidatedExternalPluginPackage
    let replacesExistingPlugin: Bool
}

struct PendingPluginInstallation: Identifiable, Sendable {
    var id: UUID { token }
    let token: UUID
    let package: ValidatedExternalPluginPackage
}

enum InstalledPluginLoadResult: Sendable {
    case valid(ValidatedExternalPluginPackage)
    case invalid(packageURL: URL, issue: PluginValidationIssue)
}

enum PluginInstallationError: Error, LocalizedError, Equatable, Sendable {
    case unknownPreparation
    case unknownTransaction
    case pluginAlreadyInstalled(PluginID)
    case pluginNotInstalled(PluginID)
    case receiptMismatch(PluginID)
    case transactionFailed

    var errorDescription: String? {
        switch self {
        case .unknownPreparation:
            "插件安装准备已失效，请重新导入"
        case .unknownTransaction:
            "插件安装事务已失效"
        case let .pluginAlreadyInstalled(id):
            "插件已安装：\(id.rawValue)"
        case let .pluginNotInstalled(id):
            "插件尚未安装：\(id.rawValue)"
        case let .receiptMismatch(id):
            "插件文件在安装后发生变化：\(id.rawValue)"
        case .transactionFailed:
            "插件安装事务失败，已保留可恢复数据"
        }
    }
}

actor PluginInstallationStore {
    private enum InstallationPhase: String, Codable, Sendable {
        case committing
        case backedUp
        case pending
        case rollingBack
        case restored
    }

    private struct InstallationRecoveryRecord: Codable, Sendable {
        let pluginID: PluginID
        let newVersion: String
        let newFingerprint: String
        let hadPreviousPackage: Bool
        let hadPreviousReceipt: Bool
        var phase: InstallationPhase
    }

    private struct PendingInstallationRecord: Sendable {
        let operationDirectory: URL
        var recovery: InstallationRecoveryRecord

        var backupPackage: URL {
            operationDirectory.appendingPathComponent(
                "Previous.clipallplugin",
                isDirectory: true
            )
        }

        var backupReceipt: URL {
            operationDirectory.appendingPathComponent("Previous.receipt.json")
        }
    }

    private let rootDirectory: URL
    private let installedDirectory: URL
    private let stagingDirectory: URL
    private let receiptsDirectory: URL
    private let validator: PluginPackageValidator
    private var preparedURLs: [UUID: URL] = [:]
    private var pendingTransactions: [UUID: PendingInstallationRecord] = [:]
    private static let recoveryFileName = "transaction.json"

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
    ) throws -> PendingPluginInstallation {
        guard preparedURLs[prepared.token] == prepared.stagingURL else {
            throw PluginInstallationError.unknownPreparation
        }

        let operationDirectory = prepared.stagingURL.deletingLastPathComponent()
        var removeOperationOnExit = true
        defer {
            preparedURLs.removeValue(forKey: prepared.token)
            if removeOperationOnExit {
                try? FileManager.default.removeItem(at: operationDirectory)
            }
        }
        try ensureDirectories()

        let staged = try validator.validate(packageURL: prepared.stagingURL, source: .installed)
        guard staged.definition.descriptor.id == prepared.package.definition.descriptor.id,
              staged.fingerprint == prepared.package.fingerprint else {
            throw PluginInstallationError.unknownPreparation
        }
        let pluginID = staged.definition.descriptor.id
        let destination = installedURL(for: pluginID)
        let receipt = receiptURL(for: pluginID)
        let exists = FileManager.default.fileExists(atPath: destination.path)
        guard replacingExisting || !exists else {
            throw PluginInstallationError.pluginAlreadyInstalled(pluginID)
        }

        let hadPreviousReceipt = exists && FileManager.default.fileExists(atPath: receipt.path)
        var record = PendingInstallationRecord(
            operationDirectory: operationDirectory,
            recovery: InstallationRecoveryRecord(
                pluginID: pluginID,
                newVersion: staged.definition.descriptor.version,
                newFingerprint: staged.fingerprint,
                hadPreviousPackage: exists,
                hadPreviousReceipt: hadPreviousReceipt,
                phase: .committing
            )
        )
        var backupsCommitted = false

        do {
            try writeRecoveryRecord(record.recovery, operationDirectory: operationDirectory)
            if exists {
                try FileManager.default.copyItem(at: destination, to: record.backupPackage)
            }
            if hadPreviousReceipt {
                try FileManager.default.copyItem(at: receipt, to: record.backupReceipt)
            }
            record.recovery.phase = .backedUp
            try writeRecoveryRecord(record.recovery, operationDirectory: operationDirectory)
            backupsCommitted = true

            if exists {
                try FileManager.default.removeItem(at: destination)
            }
            if hadPreviousReceipt {
                try FileManager.default.removeItem(at: receipt)
            }

            try FileManager.default.moveItem(at: prepared.stagingURL, to: destination)
            let installed = try validator.validate(packageURL: destination, source: .installed)
            let newReceipt = PluginInstallationReceipt(
                pluginID: pluginID,
                version: installed.definition.descriptor.version,
                fingerprint: installed.fingerprint
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(newReceipt).write(to: receipt, options: .atomic)
            record.recovery.phase = .pending
            try writeRecoveryRecord(record.recovery, operationDirectory: operationDirectory)

            let transaction = PendingPluginInstallation(
                token: UUID(),
                package: installed
            )
            pendingTransactions[transaction.token] = record
            removeOperationOnExit = false
            return transaction
        } catch {
            do {
                if backupsCommitted {
                    try restorePreviousInstallation(record)
                    record.recovery.phase = .restored
                    try writeRecoveryRecord(
                        record.recovery,
                        operationDirectory: operationDirectory
                    )
                }
            } catch {
                removeOperationOnExit = false
            }
            throw PluginInstallationError.transactionFailed
        }
    }

    func finalize(_ pending: PendingPluginInstallation) throws {
        guard let record = pendingTransactions.removeValue(forKey: pending.token) else {
            throw PluginInstallationError.unknownTransaction
        }
        try? removeIfPresent(record.operationDirectory)
    }

    func rollback(_ pending: PendingPluginInstallation) throws {
        guard var record = pendingTransactions[pending.token] else {
            throw PluginInstallationError.unknownTransaction
        }

        do {
            record.recovery.phase = .rollingBack
            try writeRecoveryRecord(
                record.recovery,
                operationDirectory: record.operationDirectory
            )
            pendingTransactions[pending.token] = record
            try restorePreviousInstallation(record)
            record.recovery.phase = .restored
            try writeRecoveryRecord(
                record.recovery,
                operationDirectory: record.operationDirectory
            )
            pendingTransactions.removeValue(forKey: pending.token)
            try? removeIfPresent(record.operationDirectory)
        } catch {
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
                    guard receiptMatchesPackage(receipt, package: package) else {
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
        guard package.definition.descriptor.id == pluginID,
              receiptMatchesPackage(receipt, package: package) else {
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
        try cleanupOrphanedStaging()
    }

    private func cleanupOrphanedStaging() throws {
        let activeOperationPaths = Set(preparedURLs.values.map {
            $0.deletingLastPathComponent().standardizedFileURL.path
        }).union(pendingTransactions.values.map {
            $0.operationDirectory.standardizedFileURL.path
        })
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return
        }

        for entry in entries where !activeOperationPaths.contains(entry.standardizedFileURL.path) {
            let recoveryURL = entry.appendingPathComponent(Self.recoveryFileName)
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                do {
                    let recovery = try JSONDecoder().decode(
                        InstallationRecoveryRecord.self,
                        from: Data(contentsOf: recoveryURL)
                    )
                    try recoverOrphanedInstallation(
                        recovery,
                        operationDirectory: entry
                    )
                } catch {
                    throw PluginInstallationError.transactionFailed
                }
            } else {
                try removeIfPresent(entry)
            }
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
        do {
            return try decoder.decode(
                PluginInstallationReceipt.self,
                from: Data(contentsOf: receiptURL(for: pluginID))
            )
        } catch {
            throw PluginInstallationError.receiptMismatch(pluginID)
        }
    }

    private func writeRecoveryRecord(
        _ recovery: InstallationRecoveryRecord,
        operationDirectory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(recovery).write(
            to: operationDirectory.appendingPathComponent(Self.recoveryFileName),
            options: .atomic
        )
    }

    private func restorePreviousInstallation(_ record: PendingInstallationRecord) throws {
        let destination = installedURL(for: record.recovery.pluginID)
        let receipt = receiptURL(for: record.recovery.pluginID)

        if record.recovery.hadPreviousPackage {
            guard FileManager.default.fileExists(atPath: record.backupPackage.path) else {
                throw PluginInstallationError.transactionFailed
            }
            try removeIfPresent(destination)
            try FileManager.default.copyItem(at: record.backupPackage, to: destination)
        } else {
            try removeIfPresent(destination)
        }

        if record.recovery.hadPreviousReceipt {
            guard FileManager.default.fileExists(atPath: record.backupReceipt.path) else {
                throw PluginInstallationError.transactionFailed
            }
            try removeIfPresent(receipt)
            try FileManager.default.copyItem(at: record.backupReceipt, to: receipt)
        } else {
            try removeIfPresent(receipt)
        }
    }

    private func recoverOrphanedInstallation(
        _ recovery: InstallationRecoveryRecord,
        operationDirectory: URL
    ) throws {
        let record = PendingInstallationRecord(
            operationDirectory: operationDirectory,
            recovery: recovery
        )

        if recovery.phase == .pending, isCompleteNewInstallation(recovery) {
            try removeIfPresent(operationDirectory)
            return
        }

        if recovery.phase == .committing || recovery.phase == .restored {
            try removeIfPresent(operationDirectory)
            return
        }

        try restorePreviousInstallation(record)
        var restored = recovery
        restored.phase = .restored
        try writeRecoveryRecord(restored, operationDirectory: operationDirectory)
        try? removeIfPresent(operationDirectory)
    }

    private func isCompleteNewInstallation(_ recovery: InstallationRecoveryRecord) -> Bool {
        guard let package = try? validator.validate(
            packageURL: installedURL(for: recovery.pluginID),
            source: .installed
        ),
        let receipt = try? JSONDecoder().decode(
            PluginInstallationReceipt.self,
            from: Data(contentsOf: receiptURL(for: recovery.pluginID))
        ) else {
            return false
        }
        return package.definition.descriptor.id == recovery.pluginID
            && package.definition.descriptor.version == recovery.newVersion
            && package.fingerprint == recovery.newFingerprint
            && receiptMatchesPackage(receipt, package: package)
    }

    private func receiptMatchesPackage(
        _ receipt: PluginInstallationReceipt,
        package: ValidatedExternalPluginPackage
    ) -> Bool {
        receipt.pluginID == package.definition.descriptor.id
            && receipt.version == package.definition.descriptor.version
            && receipt.fingerprint == package.fingerprint
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
