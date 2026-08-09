import Foundation

struct CapabilityRouter: Sendable {
    let recommendationThreshold: Int

    init(recommendationThreshold: Int = 50) {
        self.recommendationThreshold = recommendationThreshold
    }

    func route(
        descriptors: [CapabilityDescriptor],
        features: ContentFeatures,
        pinnedCapabilityIDs: Set<CapabilityID>
    ) -> CapabilityRoutingResult {
        let matches = descriptors.compactMap { descriptor -> CapabilityMatch? in
            let matchingRules = descriptor.routingRules.filter {
                features.contains($0.contentKind)
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

    private func matchOrdering(_ lhs: CapabilityMatch, _ rhs: CapabilityMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.id < rhs.id
    }
}
