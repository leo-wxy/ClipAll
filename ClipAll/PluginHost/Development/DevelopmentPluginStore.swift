import Foundation

struct DevelopmentPluginReference: Identifiable, Sendable {
    let id: PluginID
    let url: URL
}

@MainActor
final class DevelopmentPluginStore {
    private static let storageKey = "developmentPluginBookmarks.v1"

    private let defaults: UserDefaults
    private var bookmarks: [PluginID: Data]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let payload = (try? PropertyListDecoder().decode(
            [String: Data].self,
            from: defaults.data(forKey: Self.storageKey) ?? Data()
        )) ?? [:]
        bookmarks = Dictionary(uniqueKeysWithValues: payload.map { (PluginID($0.key), $0.value) })
    }

    func save(pluginID: PluginID, url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        bookmarks[pluginID] = data
        persist()
    }

    func remove(pluginID: PluginID) {
        bookmarks.removeValue(forKey: pluginID)
        persist()
    }

    func resolve(pluginID: PluginID) throws -> DevelopmentPluginReference {
        guard let bookmark = bookmarks[pluginID] else {
            throw PluginValidationIssue(code: "development_reference", message: "开发插件引用不存在")
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { try save(pluginID: pluginID, url: url) }
        return DevelopmentPluginReference(id: pluginID, url: url)
    }

    func resolveAll() -> [Result<DevelopmentPluginReference, Error>] {
        bookmarks.keys.sorted().map { pluginID in
            Result { try resolve(pluginID: pluginID) }
        }
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.key.rawValue, $0.value) })
        guard let data = try? PropertyListEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
