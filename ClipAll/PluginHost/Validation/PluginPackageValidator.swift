import CryptoKit
import Foundation

struct PluginPackageLimits: Sendable {
    let maximumManifestBytes: Int
    let maximumScriptBytes: Int
    let maximumPackageBytes: Int
    let maximumFileCount: Int

    static let standard = PluginPackageLimits(
        maximumManifestBytes: 256_000,
        maximumScriptBytes: 1_000_000,
        maximumPackageBytes: 5_000_000,
        maximumFileCount: 256
    )
}

struct PluginPackageValidator: Sendable {
    let limits: PluginPackageLimits
    let manifestDecoder: ExternalPluginManifestDecoder
    let manifestMapper: ExternalPluginManifestMapper

    init(
        limits: PluginPackageLimits = .standard,
        hostVersion: String = "0.0.6"
    ) {
        self.limits = limits
        manifestDecoder = ExternalPluginManifestDecoder()
        manifestMapper = ExternalPluginManifestMapper(hostVersion: hostVersion)
    }

    func validate(packageURL: URL, source: PluginSource) throws -> ValidatedExternalPluginPackage {
        let root = packageURL.standardizedFileURL
        guard root.pathExtension.lowercased() == "clipallplugin" else {
            throw issue("invalid_package", "请选择 .clipallplugin 插件包")
        }

        let rootValues = try resourceValues(for: root)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw issue("invalid_package", "插件包必须是普通目录，不能是符号链接")
        }

        let files = try inspectFiles(in: root)
        let manifestURL = root.appendingPathComponent("plugin.json", isDirectory: false)
        guard let manifestFile = files.first(where: { $0.url == manifestURL }) else {
            throw issue("manifest_missing", "插件包缺少 plugin.json", "plugin.json")
        }
        guard manifestFile.size <= limits.maximumManifestBytes else {
            throw issue("manifest_too_large", "plugin.json 超过 256 KB", "plugin.json")
        }

        let manifestData = try read(manifestURL, maximum: limits.maximumManifestBytes)
        let manifest = try manifestDecoder.decode(manifestData)
        let definition = try manifestMapper.map(manifest, source: source)

        let entryURL = root.appendingPathComponent(definition.runtimeEntry).standardizedFileURL
        guard contains(entryURL, in: root),
              let entryFile = files.first(where: { $0.url == entryURL }) else {
            throw issue("unsafe_path", "runtime entry 不在插件包内", "$.runtime.entry")
        }
        guard entryFile.size <= limits.maximumScriptBytes else {
            throw issue("script_too_large", "入口脚本超过 1 MB", definition.runtimeEntry)
        }
        let scriptData = try read(entryURL, maximum: limits.maximumScriptBytes)
        guard let script = String(data: scriptData, encoding: .utf8) else {
            throw issue("script_encoding", "入口脚本必须使用 UTF-8", definition.runtimeEntry)
        }

        return ValidatedExternalPluginPackage(
            packageURL: root,
            definition: definition,
            script: script,
            fingerprint: try fingerprint(files: files, root: root)
        )
    }

    private func inspectFiles(in root: URL) throws -> [InspectedFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw issue("package_read", "无法读取插件包")
        }

        var files: [InspectedFile] = []
        var totalBytes = 0
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            guard contains(standardized, in: root) else {
                throw issue("unsafe_path", "插件文件路径离开了包目录", relativePath(of: url, root: root))
            }

            let relativePath = relativePath(of: standardized, root: root)
            guard !relativePath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
                throw issue("unsafe_path", "插件包不能包含隐藏文件", relativePath)
            }

            let values = try resourceValues(for: standardized)
            guard values.isSymbolicLink != true else {
                throw issue("unsafe_path", "插件包不能包含符号链接", relativePath)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else {
                throw issue("unsafe_path", "插件包只能包含普通文件", relativePath)
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: standardized.path)
            if let references = attributes[.referenceCount] as? NSNumber, references.intValue > 1 {
                throw issue("unsafe_path", "插件包不能包含硬链接", relativePath)
            }
            if let permissions = attributes[.posixPermissions] as? NSNumber,
               permissions.intValue & 0o111 != 0 {
                throw issue("unsafe_path", "插件包不能包含可执行文件", relativePath)
            }

            let size = values.fileSize ?? 0
            totalBytes += size
            files.append(InspectedFile(url: standardized, relativePath: relativePath, size: size))
            guard files.count <= limits.maximumFileCount else {
                throw issue("package_too_large", "插件包文件不能超过 \(limits.maximumFileCount) 个")
            }
            guard totalBytes <= limits.maximumPackageBytes else {
                throw issue("package_too_large", "插件包总大小不能超过 5 MB")
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private func fingerprint(files: [InspectedFile], root: URL) throws -> String {
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: try read(file.url, maximum: limits.maximumPackageBytes))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func resourceValues(for url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            throw issue("package_read", "无法读取插件文件属性", url.lastPathComponent)
        }
    }

    private func read(_ url: URL, maximum: Int) throws -> Data {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximum else {
                throw issue("package_too_large", "插件文件超过允许大小", url.lastPathComponent)
            }
            return data
        } catch let issue as PluginValidationIssue {
            throw issue
        } catch {
            throw issue("package_read", "无法读取插件文件", url.lastPathComponent)
        }
    }

    private func contains(_ candidate: URL, in root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func relativePath(of url: URL, root: URL) -> String {
        String(url.path.dropFirst(min(url.path.count, root.path.count + 1)))
    }

    private func issue(_ code: String, _ message: String, _ location: String? = nil) -> PluginValidationIssue {
        PluginValidationIssue(code: code, message: message, location: location)
    }

    private struct InspectedFile {
        let url: URL
        let relativePath: String
        let size: Int
    }
}
