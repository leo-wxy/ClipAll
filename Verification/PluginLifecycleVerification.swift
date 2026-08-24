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
        try await verifyDeferredFinalizeCleanup(
            root: root.appendingPathComponent("DeferredFinalizeCleanup", isDirectory: true),
            fixtureURL: fixtureURL
        )

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

        try await verifyInterruptedUninstallRecovery(
            root: root.appendingPathComponent("InterruptedUninstall", isDirectory: true),
            fixtureURL: fixtureURL,
            sourcePackage: sourcePackage
        )
        try await verifyQuarantinedRecoveryRecords(
            root: root.appendingPathComponent("RecoveryQuarantine", isDirectory: true),
            fixtureURL: fixtureURL,
            replacementFixtureURL: replacementFixtureURL
        )
        try await verifyReceiptSymlinkRejection(
            root: root.appendingPathComponent("ReceiptSymlink", isDirectory: true),
            fixtureURL: fixtureURL
        )
        try await verifyDisabledBundledRepair(
            root: root.appendingPathComponent("DisabledBundledRepair", isDirectory: true),
            fixtureURL: fixtureURL,
            replacementFixtureURL: replacementFixtureURL,
            replacementSourcePackage: replacementSourcePackage
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
        try expect(
            restoredAfterRollback.definition.descriptor.version
                == installed.definition.descriptor.version,
            "replacement rollback 应恢复旧 version"
        )
        let restoredReceipt = try Data(contentsOf: receiptURL)
        try expect(
            restoredReceipt == originalReceipt,
            "replacement rollback 应原样恢复旧 receipt"
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

    private static func verifyDeferredFinalizeCleanup(
        root: URL,
        fixtureURL: URL
    ) async throws {
        let store = PluginInstallationStore(rootDirectory: root)
        let prepared = try await store.prepareImport(from: fixtureURL)
        let pending = try await store.commit(prepared, replacingExisting: false)
        let staging = root.appendingPathComponent(".Staging", isDirectory: true)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: staging.path
        )
        do {
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: staging.path
                )
            }
            try await store.finalize(pending)
        }

        let installedAfterCleanupRetry = try await store.validateInstalled(
            pluginID: .timestampTools
        )
        try expect(
            installedAfterCleanupRetry.fingerprint == pending.package.fingerprint,
            "finalize 延迟清理不得回滚已激活的新包"
        )
        let stagingEmpty = try stagingIsEmpty(root)
        try expect(stagingEmpty, "下一次 Store 操作应重试 finalize 残留清理")
        do {
            try await store.rollback(pending)
            throw PluginLifecycleVerificationError.failed("finalize 后 token 必须已消费")
        } catch let error as PluginInstallationError {
            try expect(error == .unknownTransaction, "finalize 后 rollback 应返回 unknownTransaction")
        }
    }

    private static func verifyInterruptedUninstallRecovery(
        root: URL,
        fixtureURL: URL,
        sourcePackage: ValidatedExternalPluginPackage
    ) async throws {
        let store = PluginInstallationStore(rootDirectory: root)
        let prepared = try await store.prepareImport(from: fixtureURL)
        let pending = try await store.commit(prepared, replacingExisting: false)
        try await store.finalize(pending)

        for moveReceipt in [true, false] {
            let installedPackage = root
                .appendingPathComponent("Installed", isDirectory: true)
                .appendingPathComponent(
                    "\(PluginID.timestampTools.rawValue).clipallplugin",
                    isDirectory: true
                )
            let installedReceipt = root
                .appendingPathComponent("Receipts", isDirectory: true)
                .appendingPathComponent("\(PluginID.timestampTools.rawValue).json")
            let operation = root
                .appendingPathComponent(".Staging", isDirectory: true)
                .appendingPathComponent("Uninstall-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: operation,
                withIntermediateDirectories: false
            )
            try writeUninstallRecovery(operation: operation, hadPreviousReceipt: true)
            try FileManager.default.moveItem(
                at: installedPackage,
                to: operation.appendingPathComponent(
                    installedPackage.lastPathComponent,
                    isDirectory: true
                )
            )
            if moveReceipt {
                try FileManager.default.moveItem(
                    at: installedReceipt,
                    to: operation.appendingPathComponent("receipt.json")
                )
            }

            let restarted = PluginInstallationStore(rootDirectory: root)
            let recovered = try await restarted.validateInstalled(pluginID: .timestampTools)
            try expect(
                recovered.fingerprint == sourcePackage.fingerprint,
                "卸载中断后必须恢复原 package 与 receipt"
            )
            let stagingEmpty = try stagingIsEmpty(root)
            try expect(stagingEmpty, "卸载中断恢复后不应残留 staging")
        }

        let withoutReceiptRoot = root.appendingPathComponent(
            "WithoutReceipt",
            isDirectory: true
        )
        let withoutReceiptStore = PluginInstallationStore(rootDirectory: withoutReceiptRoot)
        let withoutReceiptPrepared = try await withoutReceiptStore.prepareImport(from: fixtureURL)
        let withoutReceiptPending = try await withoutReceiptStore.commit(
            withoutReceiptPrepared,
            replacingExisting: false
        )
        try await withoutReceiptStore.finalize(withoutReceiptPending)
        let withoutReceiptPackage = withoutReceiptRoot
            .appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent(
                "\(PluginID.timestampTools.rawValue).clipallplugin",
                isDirectory: true
            )
        let withoutReceiptURL = withoutReceiptRoot
            .appendingPathComponent("Receipts", isDirectory: true)
            .appendingPathComponent("\(PluginID.timestampTools.rawValue).json")
        try FileManager.default.removeItem(at: withoutReceiptURL)
        let withoutReceiptOperation = withoutReceiptRoot
            .appendingPathComponent(".Staging", isDirectory: true)
            .appendingPathComponent("Uninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: withoutReceiptOperation,
            withIntermediateDirectories: false
        )
        try writeUninstallRecovery(
            operation: withoutReceiptOperation,
            hadPreviousReceipt: false
        )
        try FileManager.default.moveItem(
            at: withoutReceiptPackage,
            to: withoutReceiptOperation.appendingPathComponent(
                withoutReceiptPackage.lastPathComponent,
                isDirectory: true
            )
        )

        let restartedWithoutReceipt = PluginInstallationStore(rootDirectory: withoutReceiptRoot)
        _ = try await restartedWithoutReceipt.loadInstalled()
        let recoveredWithoutReceipt = try PluginPackageValidator().validate(
            packageURL: withoutReceiptPackage,
            source: .installed
        )
        try expect(
            recoveredWithoutReceipt.fingerprint == sourcePackage.fingerprint,
            "无 receipt 的卸载中断仍应恢复原 package"
        )
        try expect(
            !FileManager.default.fileExists(atPath: withoutReceiptURL.path),
            "恢复不得凭空生成原本不存在的 receipt"
        )
        let withoutReceiptStagingEmpty = try stagingIsEmpty(withoutReceiptRoot)
        try expect(withoutReceiptStagingEmpty, "无 receipt 的卸载恢复后不应残留 staging")
    }

    private static func verifyQuarantinedRecoveryRecords(
        root: URL,
        fixtureURL: URL,
        replacementFixtureURL: URL
    ) async throws {
        let malformedRoot = root.appendingPathComponent("Malformed", isDirectory: true)
        let malformedStore = PluginInstallationStore(rootDirectory: malformedRoot)
        let malformedInitial = try await malformedStore.prepareImport(from: fixtureURL)
        let malformedInitialPending = try await malformedStore.commit(
            malformedInitial,
            replacingExisting: false
        )
        try await malformedStore.finalize(malformedInitialPending)
        let malformedReplacement = try await malformedStore.prepareImport(
            from: replacementFixtureURL
        )
        _ = try await malformedStore.commit(malformedReplacement, replacingExisting: true)
        let malformedOperation = try onlyStagingOperation(malformedRoot)
        try Data("{".utf8).write(
            to: malformedOperation.appendingPathComponent("transaction.json"),
            options: .atomic
        )

        let restartedAfterMalformed = PluginInstallationStore(rootDirectory: malformedRoot)
        _ = try await restartedAfterMalformed.validateInstalled(pluginID: .timestampTools)
        let malformedQuarantineCount = try quarantineEntries(malformedRoot).count
        try expect(
            malformedQuarantineCount == 1,
            "损坏的恢复记录应被隔离"
        )
        let restartedAgain = PluginInstallationStore(rootDirectory: malformedRoot)
        _ = try await restartedAgain.validateInstalled(pluginID: .timestampTools)

        let traversalRoot = root.appendingPathComponent("Traversal", isDirectory: true)
        let traversalStore = PluginInstallationStore(rootDirectory: traversalRoot)
        let traversalInitial = try await traversalStore.prepareImport(from: fixtureURL)
        let traversalInitialPending = try await traversalStore.commit(
            traversalInitial,
            replacingExisting: false
        )
        try await traversalStore.finalize(traversalInitialPending)
        let traversalReplacement = try await traversalStore.prepareImport(
            from: replacementFixtureURL
        )
        _ = try await traversalStore.commit(traversalReplacement, replacingExisting: true)
        let traversalOperation = try onlyStagingOperation(traversalRoot)
        let recoveryURL = traversalOperation.appendingPathComponent("transaction.json")
        var recovery = try JSONSerialization.jsonObject(
            with: Data(contentsOf: recoveryURL)
        ) as! [String: Any]
        recovery["pluginID"] = "../Escape"
        try JSONSerialization.data(
            withJSONObject: recovery,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: recoveryURL, options: .atomic)

        let sentinelPackage = traversalRoot.appendingPathComponent(
            "Escape.clipallplugin",
            isDirectory: true
        )
        let sentinelMarker = sentinelPackage.appendingPathComponent("sentinel")
        let sentinelReceipt = traversalRoot.appendingPathComponent("Escape.json")
        let sentinelPackageData = Data("package-sentinel".utf8)
        let sentinelReceiptData = Data("receipt-sentinel".utf8)
        try FileManager.default.createDirectory(
            at: sentinelPackage,
            withIntermediateDirectories: false
        )
        try sentinelPackageData.write(to: sentinelMarker)
        try sentinelReceiptData.write(to: sentinelReceipt)

        let restartedAfterTraversal = PluginInstallationStore(rootDirectory: traversalRoot)
        _ = try await restartedAfterTraversal.validateInstalled(pluginID: .timestampTools)
        let preservedPackageData = try Data(contentsOf: sentinelMarker)
        let preservedReceiptData = try Data(contentsOf: sentinelReceipt)
        let traversalQuarantineCount = try quarantineEntries(traversalRoot).count
        try expect(
            preservedPackageData == sentinelPackageData,
            "越界恢复记录不得覆盖目录外 package"
        )
        try expect(
            preservedReceiptData == sentinelReceiptData,
            "越界恢复记录不得覆盖目录外 receipt"
        )
        try expect(
            traversalQuarantineCount == 1,
            "越界恢复记录应被隔离"
        )

        let symlinkRoot = root.appendingPathComponent("Symlink", isDirectory: true)
        let symlinkStore = PluginInstallationStore(rootDirectory: symlinkRoot)
        _ = try await symlinkStore.loadInstalled()
        let externalOperation = root.appendingPathComponent(
            "ExternalUninstallOperation",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: externalOperation,
            withIntermediateDirectories: false
        )
        try writeUninstallRecovery(
            operation: externalOperation,
            hadPreviousReceipt: false
        )
        let externalPackage = externalOperation.appendingPathComponent(
            "\(PluginID.timestampTools.rawValue).clipallplugin",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: fixtureURL, to: externalPackage)
        let symlinkOperation = symlinkRoot
            .appendingPathComponent(".Staging", isDirectory: true)
            .appendingPathComponent("Uninstall-Symlink", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: symlinkOperation,
            withDestinationURL: externalOperation
        )

        let restartedAfterSymlink = PluginInstallationStore(rootDirectory: symlinkRoot)
        _ = try await restartedAfterSymlink.loadInstalled()
        let preservedExternalPackage = try PluginPackageValidator().validate(
            packageURL: externalPackage,
            source: .installed
        )
        try expect(
            preservedExternalPackage.definition.descriptor.id == .timestampTools,
            "恢复不得沿 staging 符号链接移动外部 package"
        )
        let symlinkQuarantineCount = try quarantineEntries(symlinkRoot).count
        try expect(symlinkQuarantineCount == 1, "staging 符号链接应被隔离")
    }

    private static func verifyReceiptSymlinkRejection(
        root: URL,
        fixtureURL: URL
    ) async throws {
        let store = PluginInstallationStore(rootDirectory: root)
        let prepared = try await store.prepareImport(from: fixtureURL)
        let pending = try await store.commit(prepared, replacingExisting: false)
        try await store.finalize(pending)

        let receipt = root
            .appendingPathComponent("Receipts", isDirectory: true)
            .appendingPathComponent("\(PluginID.timestampTools.rawValue).json")
        let externalReceipt = root.appendingPathComponent("ExternalReceipt.json")
        let originalReceipt = try Data(contentsOf: receipt)
        try FileManager.default.moveItem(at: receipt, to: externalReceipt)

        for (target, label) in [
            (externalReceipt, "existing"),
            (root.appendingPathComponent("MissingReceipt.json"), "dangling"),
        ] {
            try? FileManager.default.removeItem(at: receipt)
            try FileManager.default.createSymbolicLink(
                at: receipt,
                withDestinationURL: target
            )
            do {
                _ = try await store.validateInstalled(pluginID: .timestampTools)
                throw PluginLifecycleVerificationError.failed(
                    "\(label) receipt symlink 必须被拒绝"
                )
            } catch let error as PluginInstallationError {
                try expect(
                    error == .receiptMismatch(.timestampTools),
                    "\(label) receipt symlink 应返回 receiptMismatch"
                )
            }
        }

        let preservedExternalReceipt = try Data(contentsOf: externalReceipt)
        try expect(
            preservedExternalReceipt == originalReceipt,
            "receipt symlink 校验不得修改外部目标"
        )
    }

    private static func verifyDisabledBundledRepair(
        root: URL,
        fixtureURL: URL,
        replacementFixtureURL: URL,
        replacementSourcePackage: ValidatedExternalPluginPackage
    ) async throws {
        let store = PluginInstallationStore(rootDirectory: root)
        let prepared = try await store.prepareImport(from: fixtureURL)
        let pending = try await store.commit(prepared, replacingExisting: false)
        try await store.finalize(pending)

        let installedManifest = root
            .appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent(
                "\(PluginID.timestampTools.rawValue).clipallplugin",
                isDirectory: true
            )
            .appendingPathComponent("plugin.json")
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: installedManifest)
        ) as! [String: Any]
        manifest["minimumClipAllVersion"] = "99.0.0"
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: installedManifest, options: .atomic)

        let suite = "ClipAll.DisabledBundledRepair.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw PluginLifecycleVerificationError.failed("无法创建自动修复测试 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.setPlugin(.timestampTools, isEnabled: false)
        let registry = CapabilityRegistry()
        let lifecycle = PluginLifecycleController(
            installationStore: store,
            registry: registry,
            settings: settings,
            configurationStore: PluginConfigurationStore(defaults: defaults),
            runnerClient: PluginRunnerClient(runnerURL: URL(fileURLWithPath: "/usr/bin/false")),
            developmentStore: DevelopmentPluginStore(defaults: defaults),
            deletePluginSecrets: { _ in }
        )
        await lifecycle.loadInstalled()
        try expect(
            lifecycle.invalidPlugins.contains { $0.issue.code == "incompatible_host" },
            "过期内置插件应进入自动修复路径"
        )
        let repairedBundledPlugin = try await lifecycle.repairBundledPluginIfNeeded(
            pluginID: .timestampTools,
            from: replacementFixtureURL
        )
        try expect(
            repairedBundledPlugin,
            "内置插件应完成自动修复"
        )
        try expect(
            lifecycle.plugin(id: .timestampTools)?.state == .disabled,
            "自动修复必须保留用户停用状态"
        )
        try expect(registry.plugin(for: .timestampTools) == nil, "停用插件不得被自动激活")
        try expect(!settings.isPluginEnabled(.timestampTools), "停用状态不得被改写")
        try expect(
            !SettingsStore(defaults: defaults).isPluginEnabled(.timestampTools),
            "停用状态必须持久化"
        )
        let repaired = try await store.validateInstalled(pluginID: .timestampTools)
        try expect(
            repaired.fingerprint == replacementSourcePackage.fingerprint,
            "自动修复应安装随 App 提供的新包"
        )
        let repairStagingEmpty = try stagingIsEmpty(root)
        try expect(
            repairStagingEmpty,
            "停用插件自动修复 finalize 后不应残留 staging"
        )
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

    private static func writeUninstallRecovery(
        operation: URL,
        hadPreviousReceipt: Bool
    ) throws {
        try JSONSerialization.data(
            withJSONObject: [
                "pluginID": PluginID.timestampTools.rawValue,
                "hadPreviousReceipt": hadPreviousReceipt,
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: operation.appendingPathComponent("uninstall.json"), options: .atomic)
    }

    private static func quarantineEntries(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".Staging", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".Quarantine-") }
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
