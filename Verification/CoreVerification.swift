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
        try verifyDiscoveryBounds()
        print("Core verification passed")
    }

    private static func verifyExternalPlugin(_ package: ValidatedExternalPluginPackage) throws {
        let definition = package.definition
        try expect(definition.descriptor.id == .timestampTools, "时间工具插件 ID 应保持稳定")
        try expect(definition.descriptor.source == .installed, "示例必须走外置插件来源")
        try expect(definition.capabilities.count == 2, "时间工具应声明两个独立能力")
        try expect(
            definition.descriptor.configurationFields.map(\.id) == ["timeZone", "displayFormat"],
            "时间工具应声明时区和显示格式"
        )
        try expect(!package.script.isEmpty, "外置入口脚本不能为空")
        try expect(package.fingerprint.count == 64, "安装指纹应为 SHA-256")
    }

    private static func verifyTimestampRouting(_ package: ValidatedExternalPluginPackage) throws {
        let descriptors = package.definition.capabilities.map(\.descriptor)
        let extractor = ContentFeatureExtractor()
        let router = CapabilityRouter()

        let timestampFeatures = extractor.extract(from: "1712345678", targetLanguageIdentifier: "zh")
        let timestampRoute = router.route(
            descriptors: descriptors,
            features: timestampFeatures,
            pinnedCapabilityIDs: []
        )
        try expect(timestampRoute.recommendation?.id == .timestampToDate, "时间戳应推荐转换到日期")

        let dateFeatures = extractor.extract(from: "2024-04-05T19:34:38Z", targetLanguageIdentifier: "zh")
        let dateRoute = router.route(
            descriptors: descriptors,
            features: dateFeatures,
            pinnedCapabilityIDs: []
        )
        try expect(dateRoute.recommendation?.id == .dateToTimestamp, "日期应推荐转换到时间戳")

        for invalidDate in [
            "2023-02-29",
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
        }

        let pinnedRoute = router.route(
            descriptors: descriptors,
            features: timestampFeatures,
            pinnedCapabilityIDs: [.timestampToDate]
        )
        try expect(pinnedRoute.recommendation == nil, "固定能力不应在推荐行重复")
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
                exclusions: [],
                executionKind: .immediate,
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
