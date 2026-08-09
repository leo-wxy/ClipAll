import AppKit
import Foundation

@MainActor
protocol ClipboardWriting: AnyObject {
    @discardableResult
    func write(_ text: String) -> Bool
}

@MainActor
final class ClipboardService: ClipboardWriting {
    @discardableResult
    func write(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
