enum CapabilityResultValueStyle: String, Codable, Hashable, Sendable {
    case body
    case monospaced
}

struct CapabilityResultItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
    let value: String
    let annotation: String?
    let style: CapabilityResultValueStyle

    init(
        id: String,
        label: String,
        value: String,
        annotation: String? = nil,
        style: CapabilityResultValueStyle = .body
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.annotation = annotation
        self.style = style
    }
}

struct CapabilityResult: Codable, Equatable, Sendable {
    let title: String
    let subtitle: String?
    let items: [CapabilityResultItem]
}

enum CapabilityOutput: Equatable, Sendable {
    case result(CapabilityResult)
    case external
    case translation(TranslationRequest)
}
