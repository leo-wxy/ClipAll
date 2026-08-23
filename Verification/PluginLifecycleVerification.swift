import Foundation

private enum PluginLifecycleVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
@MainActor
enum PluginLifecycleVerification {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw PluginLifecycleVerificationError.failed(
                "用法：plugin-lifecycle-verification <plugin>"
            )
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let sourcePackage = try PluginPackageValidator().validate(
            packageURL: fixtureURL,
            source: .installed
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipAll-PluginLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let replacementFixtureURL = root.appendingPathComponent(
            "Replacement.clipallplugin",
            isDirectory: true
        )
        try makeReplacementFixture(from: fixtureURL, to: replacementFixtureURL)
        let replacementSourcePackage = try PluginPackageValidator().validate(
            packageURL: replacementFixtureURL,
            source: .installed
        )
        try expect(
            replacementSourcePackage.fingerprint != sourcePackage.fingerprint,
            "替换测试包必须具有不同指纹"
        )

        let firstInstallRollbackRoot = root.appendingPathComponent(
            "FirstInstallRollback",
            isDirectory: true
        )
        let firstInstallRollbackStore = PluginInstallationStore(
            rootDirectory: firstInstallRollbackRoot
        )
        let firstInstallPrepared = try await firstInstallRollbackStore.prepareImport(
            from: fixtureURL
        )
        let firstInstallPending = try await firstInstallRollbackStore.commit(
            firstInstallPrepared,
            replacingExisting: false
        )
        _ = try await firstInstallRollbackStore.validateInstalled(pluginID: .timestampTools)
        let firstInstallPendingStagingEmpty = try stagingIsEmpty(firstInstallRollbackRoot)
        try expect(
            !firstInstallPendingStagingEmpty,
            "pending 首次安装应保留事务目录"
        )
        try await firstInstallRollbackStore.rollback(firstInstallPending)
        let firstInstallLoadedAfterRollback = try await firstInstallRollbackStore.loadInstalled()
        try expect(
            firstInstallLoadedAfterRollback.isEmpty,
            "首次安装 rollback 应移除新包与 receipt"
        )
        let firstInstallRollbackStagingEmpty = try stagingIsEmpty(firstInstallRollbackRoot)
        try expect(
            firstInstallRollbackStagingEmpty,
            "首次安装 rollback 后不应残留 staging"
        )
        do {
            try await firstInstallRollbackStore.rollback(firstInstallPending)
            throw PluginLifecycleVerificationError.failed("pending rollback 只能消费一次")
        } catch let error as PluginInstallationError {
            try expect(error == .unknownTransaction, "重复 rollback 应返回 unknownTransaction")
        }

        let crashRecoveryRoot = root.appendingPathComponent(
            "CrashRecovery",
            isDirectory: true
        )
        let crashStore = PluginInstallationStore(rootDirectory: crashRecoveryRoot)
        let crashInitialPrepared = try await crashStore.prepareImport(from: fixtureURL)
        let crashInitialPending = try await crashStore.commit(
            crashInitialPrepared,
            replacingExisting: false
        )
        try await crashStore.finalize(crashInitialPending)
        let interruptedPrepared = try await crashStore.prepareImport(
            from: replacementFixtureURL
        )
        _ = try await crashStore.commit(interruptedPrepared, replacingExisting: true)
        let interruptedOperation = try onlyStagingOperation(crashRecoveryRoot)
        try setRecoveryPhase("backedUp", operation: interruptedOperation)
        try FileManager.default.removeItem(
            at: crashRecoveryRoot
                .appendingPathComponent("Installed", isDirectory: true)
                .appendingPathComponent(
                    "\(PluginID.timestampTools.rawValue).clipallplugin",
                    isDirectory: true
                )
        )
        try FileManager.default.removeItem(
            at: crashRecoveryRoot
                .appendingPathComponent("Receipts", isDirectory: true)
                .appendingPathComponent("\(PluginID.timestampTools.rawValue).json")
        )
        let restartedAfterInterruptedCommit = PluginInstallationStore(
            rootDirectory: crashRecoveryRoot
        )
        let recoveredAfterInterruptedCommit = try await restartedAfterInterruptedCommit
            .validateInstalled(pluginID: .timestampTools)
        try expect(
            recoveredAfterInterruptedCommit.fingerprint == sourcePackage.fingerprint,
            "commit 中断后应从持久化记录恢复旧版本"
        )
        let interruptedCommitStagingEmpty = try stagingIsEmpty(crashRecoveryRoot)
        try expect(
            interruptedCommitStagingEmpty,
            "commit 中断恢复后不应残留 staging"
        )

        let rollingBackBeforeRestart = try await restartedAfterInterruptedCommit.prepareImport(
            from: replacementFixtureURL
        )
        _ = try await restartedAfterInterruptedCommit.commit(
            rollingBackBeforeRestart,
            replacingExisting: true
        )
        try setRecoveryPhase(
            "rollingBack",
            operation: onlyStagingOperation(crashRecoveryRoot)
        )
        let restartedDuringRollback = PluginInstallationStore(
            rootDirectory: crashRecoveryRoot
        )
        let recoveredDuringRollback = try await restartedDuringRollback.validateInstalled(
            pluginID: .timestampTools
        )
        try expect(
            recoveredDuringRollback.fingerprint == sourcePackage.fingerprint,
            "rollback 中断后应继续恢复旧版本"
        )
        let rollingBackStagingEmpty = try stagingIsEmpty(crashRecoveryRoot)
        try expect(
            rollingBackStagingEmpty,
            "rollback 中断恢复后不应残留 staging"
        )

        let completedBeforeRestart = try await restartedDuringRollback.prepareImport(
            from: replacementFixtureURL
        )
        _ = try await restartedDuringRollback.commit(
            completedBeforeRestart,
            replacingExisting: true
        )
        let restartedAfterPendingCommit = PluginInstallationStore(
            rootDirectory: crashRecoveryRoot
        )
        let recoveredPendingCommit = try await restartedAfterPendingCommit.validateInstalled(
            pluginID: .timestampTools
        )
        try expect(
            recoveredPendingCommit.fingerprint == replacementSourcePackage.fingerprint,
            "完整 pending 安装在重启后应保留新版本"
        )
        let pendingCommitStagingEmpty = try stagingIsEmpty(crashRecoveryRoot)
        try expect(
            pendingCommitStagingEmpty,
            "完整 pending 安装恢复后不应残留 staging"
        )

        // Leave an abandoned operation behind before the first store call. The
        // first-use directory setup must remove it without touching the fixture.
        let orphanDirectory = root
            .appendingPathComponent(".Staging", isDirectory: true)
            .appendingPathComponent("orphan-operation", isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: orphanDirectory.appendingPathComponent("marker"))

        let store = PluginInstallationStore(rootDirectory: root)
        let prepared = try await store.prepareImport(from: fixtureURL)
        try expect(
            !FileManager.default.fileExists(atPath: orphanDirectory.path),
            "首次使用应清理孤儿 staging"
        )
        try expect(
            prepared.package.fingerprint == sourcePackage.fingerprint,
            "staging 校验后的指纹应与源包一致"
        )

        let initialPending = try await store.commit(prepared, replacingExisting: false)
        let installed = initialPending.package
        try expect(
            installed.definition.descriptor.id == .timestampTools,
            "首次安装应保留插件 ID"
        )
        let initialPendingStagingEmpty = try stagingIsEmpty(root)
        try expect(
            !initialPendingStagingEmpty,
            "pending 安装应保留事务目录"
        )
        try await store.finalize(initialPending)
        let initialStagingEmpty = try stagingIsEmpty(root)
        try expect(initialStagingEmpty, "首次安装成功后不应残留 staging")
        do {
            try await store.finalize(initialPending)
            throw PluginLifecycleVerificationError.failed("pending finalize 只能消费一次")
        } catch let error as PluginInstallationError {
            try expect(error == .unknownTransaction, "重复 finalize 应返回 unknownTransaction")
        }

        let loaded = try await store.loadInstalled()
        guard loaded.count == 1, case let .valid(loadedPackage) = loaded[0] else {
            throw PluginLifecycleVerificationError.failed("loadInstalled 应返回一个有效插件")
        }
        try expect(
            loadedPackage.fingerprint == installed.fingerprint,
            "loadInstalled 应返回 receipt 匹配的包"
        )
        let validated = try await store.validateInstalled(pluginID: .timestampTools)
        try expect(
            validated.definition.descriptor.version == installed.definition.descriptor.version,
            "validateInstalled 应校验并返回安装版本"
        )

        // Corrupt a staged replacement after prepare.  Validation must fail,
        // remove the single-use staging operation, and keep the old install
        // usable (the non-destructive rollback contract).
        let failedReplacement = try await store.prepareImport(from: fixtureURL)
        try FileManager.default.removeItem(
            at: failedReplacement.stagingURL.appendingPathComponent("main.js")
        )
        var replacementFailed = false
        do {
            _ = try await store.commit(failedReplacement, replacingExisting: true)
        } catch {
            replacementFailed = true
        }
        try expect(replacementFailed, "损坏的 staged replacement 应失败")
        let failedReplacementStagingEmpty = try stagingIsEmpty(root)
        try expect(failedReplacementStagingEmpty, "失败 replacement 后不应残留 staging")
        _ = try await store.validateInstalled(pluginID: .timestampTools)

        let changedAfterPrepare = try await store.prepareImport(from: fixtureURL)
        let changedManifestURL = changedAfterPrepare.stagingURL.appendingPathComponent("plugin.json")
        var changedManifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: changedManifestURL)
        ) as! [String: Any]
        changedManifest["version"] = "1.1.1"
        try JSONSerialization.data(
            withJSONObject: changedManifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: changedManifestURL, options: [.atomic])
        do {
            _ = try await store.commit(changedAfterPrepare, replacingExisting: true)
            throw PluginLifecycleVerificationError.failed("prepare 后变更的合法 package 必须被拒绝")
        } catch let error as PluginInstallationError {
            try expect(
                error == .unknownPreparation,
                "prepare 后 package 指纹变化应返回 unknownPreparation"
            )
        }
        let changedAfterPrepareStagingEmpty = try stagingIsEmpty(root)
        try expect(
            changedAfterPrepareStagingEmpty,
            "prepare 后 package 变化失败不应残留 staging"
        )

        // A second install with the same ID must be explicit, and the rejected
        // single-use preparation must not be commit-able a second time.
        let duplicate = try await store.prepareImport(from: fixtureURL)
        do {
            _ = try await store.commit(duplicate, replacingExisting: false)
            throw PluginLifecycleVerificationError.failed("重复安装应被拒绝")
        } catch let error as PluginInstallationError {
            try expect(
                error == .pluginAlreadyInstalled(.timestampTools),
                "重复安装应返回 pluginAlreadyInstalled"
            )
        }
        let duplicateStagingEmpty = try stagingIsEmpty(root)
        try expect(duplicateStagingEmpty, "重复安装失败后不应残留 staging")
        do {
            _ = try await store.commit(duplicate, replacingExisting: false)
            throw PluginLifecycleVerificationError.failed("失败的 preparation 不应再次提交")
        } catch let error as PluginInstallationError {
            try expect(error == .unknownPreparation, "失败的 preparation 应失效")
        }

        let receiptURL = root
            .appendingPathComponent("Receipts", isDirectory: true)
            .appendingPathComponent("\(PluginID.timestampTools.rawValue).json")
        let originalReceipt = try Data(contentsOf: receiptURL)
        for (field, value) in [
            ("pluginID", "com.clipall.plugin.tampered"),
            ("version", "9.9.9"),
            ("fingerprint", String(repeating: "0", count: 64)),
        ] {
            guard var receipt = try JSONSerialization.jsonObject(with: originalReceipt) as? [String: Any] else {
                throw PluginLifecycleVerificationError.failed("安装 receipt 不是 JSON object")
            }
            receipt[field] = value
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted])
                .write(to: receiptURL, options: [.atomic])

            let tamperedResults = try await store.loadInstalled()
            guard tamperedResults.count == 1,
                  case let .invalid(_, issue) = tamperedResults[0] else {
                throw PluginLifecycleVerificationError.failed(
                    "篡改 receipt.\(field) 后 loadInstalled 应拒绝"
                )
            }
            try expect(
                issue.code == "receipt_mismatch",
                "篡改 receipt.\(field) 应报告 receipt_mismatch"
            )
            do {
                _ = try await store.validateInstalled(pluginID: .timestampTools)
                throw PluginLifecycleVerificationError.failed(
                    "篡改 receipt.\(field) 后 validateInstalled 应拒绝"
                )
            } catch let error as PluginInstallationError {
                try expect(
                    error == .receiptMismatch(.timestampTools),
                    "篡改 receipt.\(field) 应返回 receiptMismatch"
                )
            }
            try originalReceipt.write(to: receiptURL, options: [.atomic])
        }
        _ = try await store.validateInstalled(pluginID: .timestampTools)

        let replacementRollback = try await store.prepareImport(from: replacementFixtureURL)
        let replacementPending = try await store.commit(
            replacementRollback,
            replacingExisting: true
        )
        try expect(
            replacementPending.package.fingerprint == replacementSourcePackage.fingerprint,
            "pending replacement 应写入新版本"
        )
        try await store.rollback(replacementPending)
        let restoredAfterRollback = try await store.validateInstalled(pluginID: .timestampTools)
        try expect(
            restoredAfterRollback.fingerprint == installed.fingerprint,
            "replacement rollback 应恢复旧 package 与 receipt"
        )
        let replacementRollbackStagingEmpty = try stagingIsEmpty(root)
        try expect(
            replacementRollbackStagingEmpty,
            "replacement rollback 后不应残留 staging"
        )

        // Replacing is a separate explicit operation and remains valid after
        // receipt checks have been restored.
        let replacement = try await store.prepareImport(from: fixtureURL)
        let finalizedReplacement = try await store.commit(replacement, replacingExisting: true)
        try await store.finalize(finalizedReplacement)
        _ = try await store.validateInstalled(pluginID: .timestampTools)
        let replacementStagingEmpty = try stagingIsEmpty(root)
        try expect(replacementStagingEmpty, "替换成功后不应残留 staging")

        let discarded = try await store.prepareImport(from: fixtureURL)
        await store.discard(discarded)
        await store.discard(discarded)
        let discardedStagingEmpty = try stagingIsEmpty(root)
        try expect(discardedStagingEmpty, "discard 后不应残留 staging")
        do {
            _ = try await store.commit(discarded, replacingExisting: true)
            throw PluginLifecycleVerificationError.failed("discard 后 preparation 应失效")
        } catch let error as PluginInstallationError {
            try expect(error == .unknownPreparation, "discard 后应返回 unknownPreparation")
        }

        let conflictSuite = "ClipAll.PluginLifecycleConflictVerification.\(UUID().uuidString)"
        guard let conflictDefaults = UserDefaults(suiteName: conflictSuite) else {
            throw PluginLifecycleVerificationError.failed("无法创建冲突测试 UserDefaults")
        }
        defer { conflictDefaults.removePersistentDomain(forName: conflictSuite) }
        let conflictRegistry = CapabilityRegistry()
        let conflictConfiguration = PluginConfigurationStore(defaults: conflictDefaults)
        conflictConfiguration.register(sourcePackage.definition.descriptor)
        try conflictConfiguration.set(
            .string("utc"),
            pluginID: .timestampTools,
            fieldID: "timeZone"
        )
        let conflictRunner = PluginRunnerClient(
            runnerURL: URL(fileURLWithPath: "/usr/bin/false")
        )
        let conflictExecutors: [any CapabilityExecuting] = sourcePackage.definition.capabilities.map {
            ExternalPluginExecutor(
                definition: $0,
                script: sourcePackage.script,
                sourceName: sourcePackage.definition.runtimeEntry,
                configurationStore: conflictConfiguration,
                runnerClient: conflictRunner
            )
        }
        try conflictRegistry.register(
            descriptor: sourcePackage.definition.descriptor,
            capabilities: conflictExecutors
        )
        let lifecycleWithConflict = PluginLifecycleController(
            installationStore: store,
            registry: conflictRegistry,
            settings: SettingsStore(defaults: conflictDefaults),
            configurationStore: conflictConfiguration,
            runnerClient: conflictRunner,
            developmentStore: DevelopmentPluginStore(defaults: conflictDefaults),
            deletePluginSecrets: { _ in }
        )
        let beforeActivationFailure = try await store.validateInstalled(
            pluginID: .timestampTools
        )
        let activationFailurePrepared = try await lifecycleWithConflict.prepareImport(
            from: replacementFixtureURL
        )
        do {
            try await lifecycleWithConflict.install(
                activationFailurePrepared,
                replacingExisting: true
            )
            throw PluginLifecycleVerificationError.failed("registry 激活失败时安装必须失败")
        } catch let error as CapabilityRegistry.RegistryError {
            try expect(
                error == .duplicatePlugin(.timestampTools),
                "激活失败测试应命中 duplicatePlugin"
            )
        }
        let afterActivationFailure = try await store.validateInstalled(
            pluginID: .timestampTools
        )
        try expect(
            afterActivationFailure.fingerprint == beforeActivationFailure.fingerprint,
            "激活失败必须恢复旧 package 与 receipt"
        )
        try expect(
            conflictRegistry.plugin(for: .timestampTools) != nil,
            "激活失败不得删除既有 registry 插件"
        )
        try expect(
            lifecycleWithConflict.plugin(id: .timestampTools) == nil,
            "激活失败不得写入 managed state"
        )
        try expect(
            conflictConfiguration.string(
                pluginID: .timestampTools,
                fieldID: "timeZone"
            ) == "utc",
            "激活失败必须恢复原始配置值"
        )
        let activationFailureStagingEmpty = try stagingIsEmpty(root)
        try expect(
            activationFailureStagingEmpty,
            "激活失败 rollback 后不应残留 staging"
        )

        let suite = "ClipAll.PluginLifecycleVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw PluginLifecycleVerificationError.failed("无法创建隔离 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let registry = CapabilityRegistry()
        let settings = SettingsStore(defaults: defaults)
        let configuration = PluginConfigurationStore(defaults: defaults)
        var shouldFailSecretDeletion = true
        var deletedSecretPluginIDs: [PluginID] = []
        let lifecycle = PluginLifecycleController(
            installationStore: store,
            registry: registry,
            settings: settings,
            configurationStore: configuration,
            runnerClient: PluginRunnerClient(runnerURL: URL(fileURLWithPath: "/usr/bin/false")),
            developmentStore: DevelopmentPluginStore(defaults: defaults),
            deletePluginSecrets: { pluginID in
                deletedSecretPluginIDs.append(pluginID)
                if shouldFailSecretDeletion {
                    throw PluginLifecycleVerificationError.failed("模拟 Keychain 删除失败")
                }
            }
        )
        await lifecycle.loadInstalled()
        try expect(lifecycle.plugin(id: .timestampTools) != nil, "controller 应载入已安装插件")
        try configuration.set(.string("utc"), pluginID: .timestampTools, fieldID: "timeZone")

        do {
            try await lifecycle.uninstall(pluginID: .timestampTools)
            throw PluginLifecycleVerificationError.failed("Keychain 删除失败时卸载必须失败")
        } catch PluginLifecycleVerificationError.failed("模拟 Keychain 删除失败") {
            // Expected.
        }
        try expect(lifecycle.plugin(id: .timestampTools) != nil, "失败卸载不得移除 managed state")
        try expect(registry.plugin(for: .timestampTools) != nil, "失败卸载不得注销 registry")
        try expect(
            configuration.string(pluginID: .timestampTools, fieldID: "timeZone") == "utc",
            "失败卸载不得清除普通配置"
        )
        _ = try await store.validateInstalled(pluginID: .timestampTools)

        shouldFailSecretDeletion = false
        try await lifecycle.uninstall(pluginID: .timestampTools)
        try expect(
            deletedSecretPluginIDs == [.timestampTools, .timestampTools],
            "卸载应按精确 pluginID 清理 Keychain"
        )
        try expect(lifecycle.plugin(id: .timestampTools) == nil, "卸载后不应保留 managed state")
        try expect(registry.plugin(for: .timestampTools) == nil, "卸载后不应保留 registry")
        try expect(configuration.value(pluginID: .timestampTools, fieldID: "timeZone") == nil, "卸载应清除普通配置")
        try expect(settings.pluginEnabledStates[.timestampTools] == nil, "卸载应清除启停状态")

        let uninstallStagingEmpty = try stagingIsEmpty(root)
        try expect(uninstallStagingEmpty, "卸载成功后不应残留 staging")
        let loadedAfterUninstall = try await store.loadInstalled()
        try expect(loadedAfterUninstall.isEmpty, "卸载后不应有已安装插件")
        do {
            _ = try await store.validateInstalled(pluginID: .timestampTools)
            throw PluginLifecycleVerificationError.failed("卸载后 validateInstalled 应失败")
        } catch let error as PluginInstallationError {
            try expect(error == .pluginNotInstalled(.timestampTools), "卸载后应返回 pluginNotInstalled")
        }
        let sourceAfterLifecycle = try PluginPackageValidator().validate(
            packageURL: fixtureURL,
            source: .installed
        )
        try expect(
            sourceAfterLifecycle.fingerprint == sourcePackage.fingerprint,
            "安装与卸载不应修改源插件包"
        )

        print("Plugin lifecycle verification passed")
    }

    private static func stagingIsEmpty(_ root: URL) throws -> Bool {
        let staging = root.appendingPathComponent(".Staging", isDirectory: true)
        guard FileManager.default.fileExists(atPath: staging.path) else { return true }
        return try FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil,
            options: []
        ).isEmpty
    }

    private static func onlyStagingOperation(_ root: URL) throws -> URL {
        let operations = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".Staging", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: []
        )
        guard operations.count == 1 else {
            throw PluginLifecycleVerificationError.failed("预期只有一个 staging 事务")
        }
        return operations[0]
    }

    private static func setRecoveryPhase(_ phase: String, operation: URL) throws {
        let recoveryURL = operation.appendingPathComponent("transaction.json")
        var recovery = try JSONSerialization.jsonObject(
            with: Data(contentsOf: recoveryURL)
        ) as! [String: Any]
        recovery["phase"] = phase
        try JSONSerialization.data(
            withJSONObject: recovery,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: recoveryURL, options: [.atomic])
    }

    private static func makeReplacementFixture(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)

        let manifestURL = destination.appendingPathComponent("plugin.json")
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        manifest["version"] = "1.1.1"
        var configuration = manifest["configuration"] as! [[String: Any]]
        configuration[0]["type"] = "toggle"
        configuration[0]["defaultValue"] = false
        configuration[0].removeValue(forKey: "options")
        manifest["configuration"] = configuration
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: manifestURL, options: [.atomic])
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw PluginLifecycleVerificationError.failed(message)
        }
    }
}
