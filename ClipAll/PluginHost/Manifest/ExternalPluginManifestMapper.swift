import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              String(major) == parts[0],
              String(minor) == parts[1],
              String(patch) == parts[2] else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct ExternalPluginManifestMapper: Sendable {
    let hostVersion: SemanticVersion

    init(hostVersion: String = "0.0.9") {
        guard let version = SemanticVersion(hostVersion) else {
            preconditionFailure("宿主版本必须是三段 SemVer")
        }
        self.hostVersion = version
    }

    func map(_ manifest: ExternalPluginManifest, source: PluginSource) throws -> ExternalPluginDefinition {
        guard manifest.manifestVersion == 1 else {
            throw issue("manifest_version", "不支持 manifestVersion \(manifest.manifestVersion)", "$.manifestVersion")
        }
        guard source.isExternal else {
            throw issue("invalid_source", "外置 manifest 不能注册为内置插件")
        }
        try validatePluginIdentifier(manifest.id.rawValue, location: "$.id")
        guard let version = SemanticVersion(manifest.version) else {
            throw issue("invalid_version", "插件版本必须是三段 SemVer", "$.version")
        }
        _ = version
        guard let minimumVersion = SemanticVersion(manifest.minimumClipAllVersion) else {
            throw issue("invalid_version", "最低 ClipAll 版本必须是三段 SemVer", "$.minimumClipAllVersion")
        }
        guard minimumVersion <= hostVersion else {
            throw issue(
                "incompatible_host",
                "插件需要 ClipAll \(manifest.minimumClipAllVersion) 或更新版本",
                "$.minimumClipAllVersion"
            )
        }
        try validateDisplayString(manifest.name, maximum: 80, location: "$.name")
        try validateDisplayString(manifest.summary, maximum: 240, location: "$.summary")
        try validateSymbol(manifest.symbolName, location: "$.symbolName")
        guard manifest.runtime.kind == .javascriptCore else {
            throw issue("unsupported_runtime", "外置插件 v1 只支持 JavaScriptCore")
        }
        try validateEntry(manifest.runtime.entry)

        let configurationFields = try mapConfiguration(manifest.configuration)
        let capabilities = try mapCapabilities(manifest.capabilities, pluginID: manifest.id)

        return ExternalPluginDefinition(
            descriptor: PluginDescriptor(
                id: manifest.id,
                name: manifest.name,
                summary: manifest.summary,
                symbolName: manifest.symbolName,
                version: manifest.version,
                source: source,
                configurationFields: configurationFields
            ),
            runtimeEntry: manifest.runtime.entry,
            capabilities: capabilities
        )
    }

    private func mapConfiguration(
        _ manifests: [ExternalPluginConfigurationFieldManifest]
    ) throws -> [PluginConfigurationField] {
        guard manifests.count <= 32 else {
            throw issue("manifest_limit", "配置字段不能超过 32 个", "$.configuration")
        }

        var identifiers: Set<String> = []
        var fields: [PluginConfigurationField] = []
        for (index, field) in manifests.enumerated() {
            let path = "$.configuration[\(index)]"
            try validateSimpleIdentifier(field.id, location: "\(path).id")
            guard identifiers.insert(field.id).inserted else {
                throw issue("duplicate_identifier", "配置字段 ID 重复", "\(path).id")
            }
            try validateDisplayString(field.title, maximum: 80, location: "\(path).title")
            if let summary = field.summary {
                try validateOptionalString(summary, maximum: 240, location: "\(path).summary")
            }

            let kind: PluginConfigurationFieldKind
            switch field.type {
            case .choice:
                let options = field.options ?? []
                guard !options.isEmpty, options.count <= 32 else {
                    throw issue("invalid_configuration", "choice 必须包含 1 到 32 个选项", "\(path).options")
                }
                var optionIDs: Set<String> = []
                for (optionIndex, option) in options.enumerated() {
                    try validateSimpleIdentifier(option.id, location: "\(path).options[\(optionIndex)].id")
                    guard optionIDs.insert(option.id).inserted else {
                        throw issue("duplicate_identifier", "选项 ID 重复", "\(path).options[\(optionIndex)].id")
                    }
                    try validateDisplayString(
                        option.title,
                        maximum: 80,
                        location: "\(path).options[\(optionIndex)].title"
                    )
                }
                kind = .choice(options: options)
            case .toggle:
                guard field.options == nil, field.placeholder == nil else {
                    throw issue("invalid_configuration", "toggle 不能声明 options 或 placeholder", path)
                }
                kind = .toggle
            case .text:
                guard field.options == nil else {
                    throw issue("invalid_configuration", "text 不能声明 options", path)
                }
                if let placeholder = field.placeholder {
                    try validateOptionalString(placeholder, maximum: 240, location: "\(path).placeholder")
                }
                kind = .text(placeholder: field.placeholder)
            }

            guard kind.accepts(field.defaultValue) else {
                throw issue("invalid_configuration", "默认值与字段类型或选项不匹配", "\(path).defaultValue")
            }
            fields.append(PluginConfigurationField(
                id: field.id,
                title: field.title,
                summary: field.summary,
                kind: kind,
                defaultValue: field.defaultValue,
                visibleWhen: field.visibleWhen
            ))
        }

        let byID = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })
        for (index, field) in fields.enumerated() {
            guard let condition = field.visibleWhen else { continue }
            guard let referenced = byID[condition.fieldID] else {
                throw issue(
                    "invalid_configuration",
                    "visibleWhen 引用了不存在的字段",
                    "$.configuration[\(index)].visibleWhen.fieldID"
                )
            }
            guard referenced.kind.accepts(condition.equals) else {
                throw issue(
                    "invalid_configuration",
                    "visibleWhen 比较值与目标字段类型不匹配",
                    "$.configuration[\(index)].visibleWhen.equals"
                )
            }
        }
        return fields
    }

    private func mapCapabilities(
        _ manifests: [ExternalCapabilityManifest],
        pluginID: PluginID
    ) throws -> [ExternalCapabilityDefinition] {
        guard !manifests.isEmpty, manifests.count <= 64 else {
            throw issue("manifest_limit", "插件必须声明 1 到 64 个能力", "$.capabilities")
        }

        var identifiers: Set<CapabilityID> = []
        return try manifests.enumerated().map { index, capability in
            let path = "$.capabilities[\(index)]"
            try validateSimpleIdentifier(capability.id.rawValue, location: "\(path).id")
            guard capability.id.rawValue.hasPrefix(pluginID.rawValue + ".") else {
                throw issue("invalid_identifier", "能力 ID 必须以插件 ID 为前缀", "\(path).id")
            }
            guard identifiers.insert(capability.id).inserted else {
                throw issue("duplicate_identifier", "能力 ID 重复", "\(path).id")
            }
            try validateDisplayString(capability.name, maximum: 80, location: "\(path).name")
            try validateDisplayString(capability.purpose, maximum: 240, location: "\(path).purpose")
            try validateSymbol(capability.symbolName, location: "\(path).symbolName")
            try validateHandler(capability.handler, location: "\(path).handler")
            guard capability.executionKind == .resultPanel else {
                throw issue("unsupported_execution", "外置插件 v1 只支持 resultPanel", "\(path).executionKind")
            }

            let supportedKinds = Set(capability.supportedContentKinds)
            guard !supportedKinds.isEmpty,
                  supportedKinds.count == capability.supportedContentKinds.count else {
                throw issue("invalid_capability", "supportedContentKinds 不能为空或重复", "\(path).supportedContentKinds")
            }
            guard !capability.routingRules.isEmpty, capability.routingRules.count <= 16 else {
                throw issue("invalid_capability", "能力必须声明 1 到 16 条匹配规则", "\(path).routingRules")
            }
            var declaredFormatCount = 0
            for (ruleIndex, rule) in capability.routingRules.enumerated() {
                guard supportedKinds.contains(rule.contentKind), (0...100).contains(rule.score) else {
                    throw issue(
                        "invalid_capability",
                        "匹配规则必须引用受支持内容且分数位于 0 到 100",
                        "\(path).routingRules[\(ruleIndex)]"
                    )
                }
                try validateDisplayString(
                    rule.reason,
                    maximum: 120,
                    location: "\(path).routingRules[\(ruleIndex)].reason"
                )
                guard rule.inputMatchers.count <= 4 else {
                    throw issue(
                        "manifest_limit",
                        "每条匹配规则最多声明 4 个输入匹配器",
                        "\(path).routingRules[\(ruleIndex)].inputMatchers"
                    )
                }
                for (matcherIndex, matcher) in rule.inputMatchers.enumerated() {
                    let matcherPath = "\(path).routingRules[\(ruleIndex)].inputMatchers[\(matcherIndex)]"
                    guard matcher.type == .dateFormat,
                          !matcher.formats.isEmpty,
                          matcher.formats.count <= 16,
                          Set(matcher.formats).count == matcher.formats.count else {
                        throw issue(
                            "invalid_capability",
                            "dateFormat 匹配器必须声明 1 到 16 个不重复格式",
                            "\(matcherPath).formats"
                        )
                    }
                    declaredFormatCount += matcher.formats.count
                    for (formatIndex, format) in matcher.formats.enumerated() {
                        guard SupportedDateFormats.isValidDeclaration(format) else {
                            throw issue(
                                "invalid_capability",
                                "日期格式包含不支持的字段或结构",
                                "\(matcherPath).formats[\(formatIndex)]"
                            )
                        }
                    }
                }
            }
            guard declaredFormatCount <= 32 else {
                throw issue(
                    "manifest_limit",
                    "每个能力最多声明 32 个日期输入格式",
                    "\(path).routingRules"
                )
            }

            return ExternalCapabilityDefinition(
                descriptor: CapabilityDescriptor(
                    id: capability.id,
                    pluginID: pluginID,
                    name: capability.name,
                    symbolName: capability.symbolName,
                    purpose: capability.purpose,
                    supportedContentKinds: supportedKinds,
                    examples: Array(capability.examples.prefix(12)),
                    routingRules: capability.routingRules
                ),
                handler: capability.handler
            )
        }
    }

    private func validatePluginIdentifier(_ value: String, location: String) throws {
        guard value.range(
            of: #"^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#,
            options: .regularExpression
        ) != nil, value.count <= 160 else {
            throw issue("invalid_identifier", "插件 ID 必须是反向域名格式", location)
        }
    }

    private func validateSimpleIdentifier(_ value: String, location: String) throws {
        guard value.range(of: #"^[A-Za-z][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
              value.count <= 160 else {
            throw issue("invalid_identifier", "标识符格式无效", location)
        }
    }

    private func validateHandler(_ value: String, location: String) throws {
        guard value.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil,
              value.count <= 80 else {
            throw issue("invalid_identifier", "handler 名称无效", location)
        }
    }

    private func validateEntry(_ value: String) throws {
        let path = NSString(string: value).standardizingPath
        guard !value.hasPrefix("/"),
              !value.contains("\\"),
              path == value,
              !path.split(separator: "/").contains(".."),
              value.lowercased().hasSuffix(".js"),
              value.count <= 240 else {
            throw issue("unsafe_path", "runtime entry 必须是包内规范化 JavaScript 相对路径", "$.runtime.entry")
        }
    }

    private func validateSymbol(_ value: String, location: String) throws {
        guard value.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil,
              value.count <= 100 else {
            throw issue("invalid_symbol", "SF Symbol 名称格式无效", location)
        }
    }

    private func validateDisplayString(_ value: String, maximum: Int, location: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= maximum else {
            throw issue("manifest_limit", "文本不能为空且不能超过 \(maximum) 个字符", location)
        }
    }

    private func validateOptionalString(_ value: String, maximum: Int, location: String) throws {
        guard value.count <= maximum else {
            throw issue("manifest_limit", "文本不能超过 \(maximum) 个字符", location)
        }
    }

    private func issue(_ code: String, _ message: String, _ location: String? = nil) -> PluginValidationIssue {
        PluginValidationIssue(code: code, message: message, location: location)
    }
}
