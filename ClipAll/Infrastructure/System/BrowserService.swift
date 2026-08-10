import AppKit
import Foundation

@MainActor
final class BrowserService {
    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
