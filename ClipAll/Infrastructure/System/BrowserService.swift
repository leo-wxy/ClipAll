import AppKit
import Foundation

@MainActor
protocol BrowserOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool
}

@MainActor
final class BrowserService: BrowserOpening {
    @discardableResult
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
