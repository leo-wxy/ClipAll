import Foundation

struct CapabilityMatch: Identifiable, Equatable, Sendable {
    var id: CapabilityID { capability.id }

    let capability: CapabilityDescriptor
    let score: Int
    let reason: String
}

struct CapabilityRoutingResult: Equatable, Sendable {
    let rankedMatches: [CapabilityMatch]
    let recommendation: CapabilityMatch?
}
