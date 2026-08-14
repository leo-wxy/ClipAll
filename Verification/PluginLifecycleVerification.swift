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

        let installed = try await store.commit(prepared, replacingExisting: false)
        try expect(
            installed.definition.descriptor.id == .timestampTools,
            "首次安装应保留插件 ID"
        )
        let initialStagingEmpty = try stagingIsEmpty(root)
        try expect(initialStagingEmpty, "首次安装成功后不应残留 staging")

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

        // Replacing is a separate explicit operation and remains valid after
        // receipt checks have been restored.
        let replacement = try await store.prepareImport(from: fixtureURL)
        _ = try await store.commit(replacement, replacingExisting: true)
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw PluginLifecycleVerificationError.failed(message)
        }
    }
}
