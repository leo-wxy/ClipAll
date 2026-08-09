import Foundation

struct CapabilityDiscoverySections: Equatable, Sendable {
    let matches: [CapabilityDescriptor]
    let recent: [CapabilityDescriptor]
}

struct CapabilityDiscoveryModel: Sendable {
    static let maximumContextMatches = 5
    static let maximumRecentItems = 3

    func sections(
        query: String,
        descriptors: [CapabilityDescriptor],
        routedMatches: [CapabilityMatch],
        recentCapabilityIDs: [CapabilityID],
        pluginNames: [PluginID: String]
    ) -> CapabilityDiscoverySections {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            return CapabilityDiscoverySections(
                matches: search(
                    query: trimmedQuery,
                    descriptors: descriptors,
                    pluginNames: pluginNames
                ),
                recent: []
            )
        }

        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let matches = routedMatches
            .compactMap { descriptorByID[$0.id] }
            .uniqued(by: \.id)
            .prefix(Self.maximumContextMatches)

        let matchedIDs = Set(matches.map(\.id))
        let recent = recentCapabilityIDs
            .filter { !matchedIDs.contains($0) }
            .compactMap { descriptorByID[$0] }
            .uniqued(by: \.id)
            .prefix(Self.maximumRecentItems)

        return CapabilityDiscoverySections(
            matches: Array(matches),
            recent: Array(recent)
        )
    }

    private func search(
        query: String,
        descriptors: [CapabilityDescriptor],
        pluginNames: [PluginID: String]
    ) -> [CapabilityDescriptor] {
        descriptors
            .compactMap { descriptor -> (descriptor: CapabilityDescriptor, score: Int)? in
                let name = descriptor.name.localizedCaseInsensitiveContains(query)
                let purpose = descriptor.purpose.localizedCaseInsensitiveContains(query)
                let plugin = pluginNames[descriptor.pluginID]?.localizedCaseInsensitiveContains(query) == true
                guard name || purpose || plugin else { return nil }

                let prefix = descriptor.name.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive, .anchored]
                ) != nil
                let score = (prefix ? 100 : 0) + (name ? 50 : 0) + (purpose ? 20 : 0) + (plugin ? 10 : 0)
                return (descriptor, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.descriptor.id < $1.descriptor.id
            }
            .map(\.descriptor)
    }
}

private extension Sequence {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen: Set<ID> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
