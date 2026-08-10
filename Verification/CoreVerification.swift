import Foundation

private enum VerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
enum CoreVerification {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw VerificationError.failed("需要传入时间工具插件目录")
        }
        let package = try PluginPackageValidator().validate(
            packageURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            source: .installed
        )
        try verifyExternalPlugin(package)
        try verifyTimestampRouting(package)
        try verifyMatcherCompatibility()
        try verifyDiscoveryBounds()
        print("Core verification passed")
    }

    private static func verifyExternalPlugin(_ package: ValidatedExternalPluginPackage) throws {
        let definition = package.definition
        try expect(definition.descriptor.id == .timestampTools, "时间工具插件 ID 应保持稳定")
        try expect(definition.descriptor.source == .installed, "示例必须走外置插件来源")
        try expect(definition.descriptor.version == "1.1.0", "时间工具插件应使用独立 SemVer")
        try expect(definition.capabilities.count == 2, "时间工具应声明两个独立能力")
        try expect(
            definition.descriptor.configurationFields.map(\.id) == ["timeZone", "displayFormat"],
            "时间工具应声明时区和显示格式"
        )
        try expect(!package.script.isEmpty, "外置入口脚本不能为空")
        try expect(package.fingerprint.count == 64, "安装指纹应为 SHA-256")
        let dateCapability = definition.capabilities.first { $0.descriptor.id == .dateToTimestamp }
        let declaredFormats = dateCapability?.descriptor.routingRules.flatMap(\.inputMatchers).flatMap(\.formats) ?? []
        try expect(declaredFormats.contains("yyyy年M月d日"), "日期能力应由 manifest 声明中文输入格式")
        try expect(declaredFormats.contains("yyyy/MM/dd"), "manifest 格式应覆盖插件可执行的斜杠日期")
    }

    private static func verifyTimestampRouting(_ package: ValidatedExternalPluginPackage) throws {
        let descriptors = package.definition.capabilities.map(\.descriptor)
        let extractor = ContentFeatureExtractor()
        let router = CapabilityRouter()

        let timestampFeatures = extractor.extract(from: "1712345678", targetLanguageIdentifier: "zh")
        let timestampRoute = router.route(
            descriptors: descriptors,
            features: timestampFeatures,
            sourceText: "1712345678",
            pinnedCapabilityIDs: []
        )
        try expect(timestampRoute.recommendation?.id == .timestampToDate, "时间戳应推荐转换到日期")

        let dateFeatures = extractor.extract(from: "2024-04-05T19:34:38Z", targetLanguageIdentifier: "zh")
        let dateRoute = router.route(
            descriptors: descriptors,
            features: dateFeatures,
            sourceText: "2024-04-05T19:34:38Z",
            pinnedCapabilityIDs: []
        )
        try expect(dateRoute.recommendation?.id == .dateToTimestamp, "日期应推荐转换到时间戳")

        let chineseDate = "2026年4月26日"
        let chineseFeatures = extractor.extract(from: chineseDate, targetLanguageIdentifier: "zh")
        try expect(!chineseFeatures.contains(.dateTime), "宿主不应硬编码插件中文日期格式")
        let chineseRoute = router.route(
            descriptors: descriptors,
            features: chineseFeatures,
            sourceText: chineseDate,
            pinnedCapabilityIDs: []
        )
        try expect(
            chineseRoute.recommendation?.id == .dateToTimestamp,
            "manifest dateFormat 匹配器应推荐中文日期转换"
        )

        let slashDate = "2024/04/05"
        let slashFeatures = extractor.extract(from: slashDate, targetLanguageIdentifier: "zh")
        try expect(!slashFeatures.contains(.dateTime), "宿主不应硬编码插件斜杠日期格式")
        let slashRoute = router.route(
            descriptors: descriptors,
            features: slashFeatures,
            sourceText: slashDate,
            pinnedCapabilityIDs: []
        )
        try expect(
            slashRoute.recommendation?.id == .dateToTimestamp,
            "manifest 与 handler 共同支持的斜杠日期应获得推荐"
        )

        for invalidDate in [
            "2023-02-29",
            "2023年2月29日",
            "2024-01-01T12:00:00.1234Z",
            "2024-01-01T12:00:00+0800",
        ] {
            let invalidFeatures = extractor.extract(
                from: invalidDate,
                targetLanguageIdentifier: "zh"
            )
            try expect(
                !invalidFeatures.contains(.dateTime),
                "不受插件支持或无效的日期不应触发日期推荐：\(invalidDate)"
            )
            let invalidRoute = router.route(
                descriptors: descriptors,
                features: invalidFeatures,
                sourceText: invalidDate,
                pinnedCapabilityIDs: []
            )
            try expect(
                invalidRoute.recommendation == nil,
                "无效日期不应命中插件输入匹配器：\(invalidDate)"
            )
        }

        let pinnedRoute = router.route(
            descriptors: descriptors,
            features: timestampFeatures,
            sourceText: "1712345678",
            pinnedCapabilityIDs: [.timestampToDate]
        )
        try expect(pinnedRoute.recommendation == nil, "固定能力不应在推荐行重复")
    }

    private static func verifyMatcherCompatibility() throws {
        let legacyRuleJSON = #"{"contentKind":"text","score":25,"reason":"旧规则"}"#
        let legacyRule = try JSONDecoder().decode(
            CapabilityRoutingRule.self,
            from: Data(legacyRuleJSON.utf8)
        )
        try expect(legacyRule.inputMatchers.isEmpty, "旧 v1 routingRules 应继续解码")
        let nullMatchersJSON = #"{"contentKind":"text","score":25,"reason":"无效规则","inputMatchers":null}"#
        var rejectedNullMatchers = false
        do {
            _ = try JSONDecoder().decode(
                CapabilityRoutingRule.self,
                from: Data(nullMatchersJSON.utf8)
            )
        } catch {
            rejectedNullMatchers = true
        }
        try expect(rejectedNullMatchers, "显式 null inputMatchers 必须按 schema 拒绝")
        try expect(
            SupportedDateFormats.isValidDeclaration("yyyy年M月d日 HH:mm:ss"),
            "受限日期格式应接受完整年月日时分秒"
        )
        try expect(
            !SupportedDateFormats.isValidDeclaration("yyyy年QQ月dd日"),
            "日期格式不得接受未知字段"
        )
        try expect(
            !SupportedDateFormats.isValidDeclaration("yyyy-MM-dd'\n'HH:mm:ss"),
            "日期格式的引号常量不得包含控制字符"
        )
    }

    private static func verifyDiscoveryBounds() throws {
        let descriptors = (0..<12).map { index in
            CapabilityDescriptor(
                id: CapabilityID("test.\(index)"),
                pluginID: .system,
                name: "测试能力 \(index)",
                symbolName: "bolt",
                purpose: "用于验证能力结果上限",
                supportedContentKinds: [.text],
                examples: [],
                routingRules: [
                    CapabilityRoutingRule(contentKind: .text, score: 60 - index, reason: "普通文本")
                ]
            )
        }
        let matches = descriptors.enumerated().map { offset, descriptor in
            CapabilityMatch(capability: descriptor, score: 100 - offset, reason: "测试")
        }
        let sections = CapabilityDiscoveryModel().sections(
            query: "",
            descriptors: descriptors,
            routedMatches: matches,
            recentCapabilityIDs: descriptors.reversed().map(\.id),
            pluginNames: [.system: "系统"]
        )

        try expect(sections.matches.count == 5, "上下文匹配最多显示 5 项")
        try expect(sections.recent.count == 3, "最近使用最多显示 3 项")
        try expect(Set(sections.matches.map(\.id)).isDisjoint(with: sections.recent.map(\.id)), "两组结果应去重")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VerificationError.failed(message) }
    }
}
