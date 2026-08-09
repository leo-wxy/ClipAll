import Foundation

struct ExternalPluginManifestDecoder: Sendable {
    func decode(_ data: Data) throws -> ExternalPluginManifest {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PluginValidationIssue(code: "manifest_json", message: "plugin.json 不是有效 JSON")
        }

        guard let object = json as? [String: Any] else {
            throw PluginValidationIssue(code: "manifest_schema", message: "plugin.json 顶层必须是对象")
        }
        try validateKnownKeys(in: object)

        do {
            return try JSONDecoder().decode(ExternalPluginManifest.self, from: data)
        } catch let error as DecodingError {
            throw decodingIssue(error)
        } catch {
            throw PluginValidationIssue(code: "manifest_schema", message: "plugin.json 无法解码")
        }
    }

    private func validateKnownKeys(in object: [String: Any]) throws {
        try rejectUnknown(
            object,
            allowed: [
                "manifestVersion", "id", "name", "version", "minimumClipAllVersion",
                "summary", "symbolName", "runtime", "configuration", "capabilities",
            ],
            path: "$"
        )

        if let runtime = object["runtime"] as? [String: Any] {
            try rejectUnknown(runtime, allowed: ["kind", "entry"], path: "$.runtime")
        }

        if let fields = object["configuration"] as? [Any] {
            for (index, rawField) in fields.enumerated() {
                guard let field = rawField as? [String: Any] else { continue }
                let type = field["type"] as? String
                var allowed: Set<String> = [
                    "id", "title", "summary", "type", "defaultValue", "visibleWhen",
                ]
                if type == "choice" { allowed.insert("options") }
                if type == "text" { allowed.insert("placeholder") }
                try rejectUnknown(field, allowed: allowed, path: "$.configuration[\(index)]")

                if let options = field["options"] as? [Any] {
                    for (optionIndex, rawOption) in options.enumerated() {
                        if let option = rawOption as? [String: Any] {
                            try rejectUnknown(
                                option,
                                allowed: ["id", "title"],
                                path: "$.configuration[\(index)].options[\(optionIndex)]"
                            )
                        }
                    }
                }

                if let condition = field["visibleWhen"] as? [String: Any] {
                    try rejectUnknown(
                        condition,
                        allowed: ["fieldID", "equals"],
                        path: "$.configuration[\(index)].visibleWhen"
                    )
                }
            }
        }

        if let capabilities = object["capabilities"] as? [Any] {
            for (index, rawCapability) in capabilities.enumerated() {
                guard let capability = rawCapability as? [String: Any] else { continue }
                try rejectUnknown(
                    capability,
                    allowed: [
                        "id", "name", "symbolName", "purpose", "supportedContentKinds",
                        "examples", "exclusions", "executionKind", "handler", "routingRules",
                    ],
                    path: "$.capabilities[\(index)]"
                )
                if let rules = capability["routingRules"] as? [Any] {
                    for (ruleIndex, rawRule) in rules.enumerated() {
                        if let rule = rawRule as? [String: Any] {
                            try rejectUnknown(
                                rule,
                                allowed: ["contentKind", "score", "reason"],
                                path: "$.capabilities[\(index)].routingRules[\(ruleIndex)]"
                            )
                        }
                    }
                }
            }
        }
    }

    private func rejectUnknown(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw PluginValidationIssue(
                code: "manifest_unknown_field",
                message: "发现未知字段 \(key)",
                location: "\(path).\(key)"
            )
        }
    }

    private func decodingIssue(_ error: DecodingError) -> PluginValidationIssue {
        let context: DecodingError.Context
        switch error {
        case let .dataCorrupted(value),
             let .keyNotFound(_, value),
             let .typeMismatch(_, value),
             let .valueNotFound(_, value):
            context = value
        @unknown default:
            return PluginValidationIssue(code: "manifest_schema", message: "plugin.json 不符合 v1 schema")
        }

        let location = context.codingPath.reduce("$") { partial, key in
            if let index = key.intValue { return "\(partial)[\(index)]" }
            return "\(partial).\(key.stringValue)"
        }
        return PluginValidationIssue(
            code: "manifest_schema",
            message: "字段缺失或类型不正确",
            location: location
        )
    }
}
