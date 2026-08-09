import Foundation

struct CapabilityRouter: Sendable {
    let recommendationThreshold: Int

    init(recommendationThreshold: Int = 50) {
        self.recommendationThreshold = recommendationThreshold
    }

    func route(
        descriptors: [CapabilityDescriptor],
        features: ContentFeatures,
        sourceText: String = "",
        pinnedCapabilityIDs: Set<CapabilityID>
    ) -> CapabilityRoutingResult {
        let normalizedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = descriptors.compactMap { descriptor -> CapabilityMatch? in
            let matchingRules = descriptor.routingRules.filter {
                features.contains($0.contentKind) ||
                    $0.inputMatchers.contains(where: { matcherMatches($0, text: normalizedText) })
            }
            guard let strongest = matchingRules.max(by: ruleOrdering) else {
                return nil
            }

            let supportingRuleCount = matchingRules.filter { $0.score > 0 }.count
            let score = strongest.score + max(0, supportingRuleCount - 1)
            return CapabilityMatch(
                capability: descriptor,
                score: score,
                reason: strongest.reason
            )
        }
        .sorted(by: matchOrdering)

        let recommendation = matches.first {
            $0.score >= recommendationThreshold && !pinnedCapabilityIDs.contains($0.id)
        }

        return CapabilityRoutingResult(
            rankedMatches: matches,
            recommendation: recommendation
        )
    }

    private func ruleOrdering(_ lhs: CapabilityRoutingRule, _ rhs: CapabilityRoutingRule) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        return lhs.contentKind.rawValue > rhs.contentKind.rawValue
    }

    private func matcherMatches(_ matcher: CapabilityInputMatcher, text: String) -> Bool {
        switch matcher.type {
        case .dateFormat:
            SupportedDateFormats.matches(text, declaredFormats: matcher.formats)
        }
    }

    private func matchOrdering(_ lhs: CapabilityMatch, _ rhs: CapabilityMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.id < rhs.id
    }
}
